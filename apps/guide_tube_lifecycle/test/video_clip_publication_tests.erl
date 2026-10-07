%% @doc The `video_clip_published_v1' and `video_clip_retracted_v1' fact's
%% wire shape: text as `{text, Bin}' (CBOR text) so non-BEAM subscribers
%% get strings, not bytes, while ids and the thumbnail mcid stay bytes.
-module(video_clip_publication_tests).

-include_lib("eunit/include/eunit.hrl").

fact_sends_text_as_text_and_ids_as_bytes_test() ->
    Row = #{clip_id => <<"clip-1">>, channel_id => <<"ch-1">>, name => <<"Nap">>,
            description => <<"A long nap">>, tags => [<<"cats">>, <<"sleep">>],
            thumbnail_mcid => <<4, 5, 6>>, local_ref => <<"/data/clip-1.mp4">>,
            status => <<"published">>},
    Fact = video_clip_publication:fact(Row, <<"clip-1">>),
    ?assert(is_integer(maps:get(sent_at, Fact))),
    ?assertEqual(#{clip_id => <<"clip-1">>,
                   channel_id => <<"ch-1">>,
                   name => {text, <<"Nap">>},
                   description => {text, <<"A long nap">>},
                   tags => [{text, <<"cats">>}, {text, <<"sleep">>}],
                   thumbnail_mcid => <<4, 5, 6>>},
                 maps:remove(sent_at, Fact)).

fact_keeps_an_absent_description_absent_test() ->
    Fact = video_clip_publication:fact(#{channel_id => <<"ch-1">>, name => <<"Nap">>},
                                       <<"clip-1">>),
    ?assertEqual(undefined, maps:get(description, Fact)),
    ?assertEqual([], maps:get(tags, Fact)).

%% ==========================================================================
%% A clip is announced published only while its row says so (#17). The
%% heartbeat lists published clips, then announces them one by one: a clip
%% retracted in between must not be re-listed by a published fact built from
%% its now-unpublished row, after its withdraw already went out.
%% ==========================================================================

announced(Status, Send) ->
    ok = application:set_env(guide_tube_lifecycle, realm_name, "io.macula"),
    Stop = store(project_tube_store:start_link()),
    ok = meck:new(mcl_om, [non_strict]),
    ok = meck:expect(mcl_om, mesh_handles, fun() -> {ok, pool, realm} end),
    ok = meck:new(macula_publisher, [non_strict]),
    ok = meck:expect(macula_publisher, start_link,
                     fun(_Mod, _Pool, _Realm, Topic, _Fact, _Args) -> {ok, Topic} end),
    try
        ok = project_tube_store:put_clip(<<"clip-r">>, #{clip_id => <<"clip-r">>,
                                                         channel_id => <<"ch-1">>,
                                                         name => <<"Nap">>, status => Status}),
        ok = Send(#{clip_id => <<"clip-r">>}),
        [Topic || {_, {_, start_link, [_, _, _, Topic, _, _]}, _} <- meck:history(macula_publisher)]
    after
        meck:unload(),
        Stop(),
        application:unset_env(guide_tube_lifecycle, realm_name)
    end.

%% The store, and how to leave it as found: another module's test may have
%% left one running.
store({ok, Store}) ->
    unlink(Store),
    fun() -> gen_server:stop(Store) end;
store({error, {already_started, _}}) ->
    fun() -> ok end.

a_published_clip_is_announced_test() ->
    ?assertEqual([topic(video_clip_published)],
                 announced(<<"published">>, fun video_clip_publication:publish_to_mesh/1)).

topic(Fact) ->
    ok = application:set_env(guide_tube_lifecycle, realm_name, "io.macula"),
    try tube_catalog_topic:topic(Fact)
    after application:unset_env(guide_tube_lifecycle, realm_name)
    end.

a_clip_no_longer_published_is_not_announced_published_test_() ->
    [?_assertEqual([], announced(Status, fun video_clip_publication:publish_to_mesh/1))
     || Status <- [<<"uploaded">>, <<"archived">>, <<"rejected">>]].

%% Its withdraw still goes out: that is what the row's new state calls for.
a_retracted_clip_is_withdrawn_test() ->
    ?assertEqual([topic(video_clip_retracted)],
                 announced(<<"uploaded">>, fun video_clip_publication:withdraw_from_mesh/1)).
