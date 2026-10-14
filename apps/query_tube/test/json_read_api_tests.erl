%% @doc The read API's JSON replies (#15). A read-model row carries an MCID
%% as the raw bytes the mesh uses, and OTP's `json:encode/1' refuses the ones
%% that are not valid UTF-8: GET /api/tube/channels answered HTTP 500 for any
%% channel with a logo, and the clip routes failed the same way as soon as a
%% thumbnail had been scanned.
%%
%% Each test below pins the reply the handler sends -- status AND body -- so
%% a raw-byte id reaching `json:encode/1' fails here rather than in
%% production. The rows are put in the read-model store with the keys the
%% projections write.
-module(json_read_api_tests).

-include_lib("eunit/include/eunit.hrl").

-define(MCID(Bytes), <<2, 16#55, (crypto:hash(sha384, Bytes))/binary>>).

%% The store is a registered singleton whose ETS tables are public, and a
%% suite that ran before this one can leave it up: this one wants its own
%% empty store, and gives the VM back the same way it found it.
setup() ->
    _ = catch gen_server:stop(project_tube_store),
    {ok, Store} = project_tube_store:start_link(),
    Store.

teardown(Store) ->
    _ = catch gen_server:stop(Store),
    ok.

%% The body as it reaches the wire. `json:encode/1' hands back iodata and
%% cowboy writes it as it stands, so this copies it into a binary exactly
%% once, the way the socket does.
json_of(Body) ->
    json:decode(iolist_to_binary(Body)).

channels_page_answers_200_with_the_logo_mcid_as_hex_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            Logo = ?MCID(<<"logo">>),
            ok = project_tube_store:put_channel(<<"ch-1">>, channel(#{logo_mcid => Logo})),
            {Status, Body} = get_channels_page_api:json_reply(),
            ?assertEqual(200, Status),
            #{<<"ok">> := true, <<"channels">> := [Channel]} = json_of(Body),
            Hex = maps:get(<<"logo_mcid">>, Channel),
            ?assertEqual(100, byte_size(Hex)),
            ?assertEqual(binary:encode_hex(Logo, lowercase), Hex),
            %% the rest of the row is untouched
            ?assertEqual(<<"ch-1">>, maps:get(<<"channel_id">>, Channel)),
            ?assertEqual([<<"pets">>], maps:get(<<"tags">>, Channel))
        end
     end}.

%% The ordinary row, and the one this endpoint serves most of: nothing was
%% ever scanned, so the row's id is `undefined'. It must not be mistaken for
%% an id. What goes out is that atom's own text -- the API's long-standing
%% answer for a missing logo, untouched here and worth a `null' of its own.
channel_with_no_logo_still_answers_200_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            ok = project_tube_store:put_channel(<<"ch-1">>, channel(#{})),
            {Status, Body} = get_channels_page_api:json_reply(),
            ?assertEqual(200, Status),
            #{<<"channels">> := [#{<<"logo_mcid">> := NoLogo}]} = json_of(Body),
            ?assertEqual(<<"undefined">>, NoLogo)
        end
     end}.

channel_by_id_answers_200_with_the_logo_mcid_as_hex_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            Logo = ?MCID(<<"logo">>),
            ok = project_tube_store:put_channel(<<"ch-1">>, channel(#{logo_mcid => Logo})),
            {Status, Body} = get_channel_by_id_api:json_reply(project_tube_store:get_channel(<<"ch-1">>)),
            ?assertEqual(200, Status),
            #{<<"ok">> := true, <<"channel">> := Channel} = json_of(Body),
            ?assertEqual(binary:encode_hex(Logo, lowercase), maps:get(<<"logo_mcid">>, Channel))
        end
     end}.

clips_page_answers_200_with_the_thumbnail_mcid_as_hex_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            Thumbnail = ?MCID(<<"thumbnail">>),
            ok = project_tube_store:put_clip(<<"clip-1">>, clip(#{thumbnail_mcid => Thumbnail})),
            {Status, Body} = get_video_clips_page_api:json_reply(<<"ch-1">>),
            ?assertEqual(200, Status),
            #{<<"ok">> := true, <<"clips">> := [Clip]} = json_of(Body),
            ?assertEqual(binary:encode_hex(Thumbnail, lowercase),
                         maps:get(<<"thumbnail_mcid">>, Clip))
        end
     end}.

clip_by_id_answers_200_with_the_thumbnail_mcid_as_hex_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            Thumbnail = ?MCID(<<"thumbnail">>),
            ok = project_tube_store:put_clip(<<"clip-1">>, clip(#{thumbnail_mcid => Thumbnail})),
            {Status, Body} = get_video_clip_by_id_api:json_reply(project_tube_store:get_clip(<<"clip-1">>)),
            ?assertEqual(200, Status),
            #{<<"ok">> := true, <<"clip">> := Clip} = json_of(Body),
            ?assertEqual(binary:encode_hex(Thumbnail, lowercase),
                         maps:get(<<"thumbnail_mcid">>, Clip))
        end
     end}.

both_not_found_replies_stay_404_test() ->
    ?assertMatch({404, _}, get_channel_by_id_api:json_reply({error, not_found})),
    ?assertMatch({404, _}, get_video_clip_by_id_api:json_reply({error, not_found})).

%% The read model's own rows, as the projections write them
%% (channel_lifecycle_to_channels / video_clip_lifecycle_to_video_clips).
channel(Fields) ->
    maps:merge(#{channel_id => <<"ch-1">>, name => <<"Cats">>, description => <<>>,
                 owner => <<"acme">>, tags => [<<"pets">>], logo_mcid => undefined},
               Fields).

clip(Fields) ->
    maps:merge(#{clip_id => <<"clip-1">>, channel_id => <<"ch-1">>, name => <<"A clip">>,
                 description => <<>>, tags => [], thumbnail_mcid => undefined,
                 local_ref => <<"/data/clip-1.mp4">>, status => <<"uploaded">>},
               Fields).
