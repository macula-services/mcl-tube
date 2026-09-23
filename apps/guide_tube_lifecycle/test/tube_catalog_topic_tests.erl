%%% @doc The four catalog facts' topics: the public contract the portal's
%%% catalogue subscribes to. A change here is a new `_vN', not an edit.
-module(tube_catalog_topic_tests).

-include_lib("eunit/include/eunit.hrl").

catalog_topics_are_the_published_contract_test() ->
    [?assertEqual(<<"io.macula/mcl-tube/tube/catalog/", Name/binary, "_v1">>,
                  tube_catalog_topic:topic(<<"io.macula">>, binary_to_atom(Name)))
     || Name <- [<<"channel_announced">>, <<"video_clip_published">>,
                 <<"video_clip_retracted">>, <<"video_clip_viewed">>]].

every_topic_is_a_canonical_app_fact_test() ->
    [?assertMatch({ok, #{tier := app, org := <<"mcl-tube">>, app := <<"tube">>,
                         domain := <<"catalog">>, version := 1}},
                  macula_topic:parse(tube_catalog_topic:topic(<<"io.macula">>, F)))
     || F <- [channel_announced, video_clip_published, video_clip_retracted,
              video_clip_viewed]].

%% The topics carry the realm NAME; publishing needs it configured.
topic_reads_the_configured_realm_name_test() ->
    ok = application:set_env(guide_tube_lifecycle, realm_name, "io.macula"),
    try ?assertEqual(<<"io.macula/mcl-tube/tube/catalog/channel_announced_v1">>,
                     tube_catalog_topic:topic(channel_announced))
    after application:unset_env(guide_tube_lifecycle, realm_name)
    end.

an_unset_realm_name_is_refused_test() ->
    ok = application:unset_env(guide_tube_lifecycle, realm_name),
    ?assertError({mcl_tube_realm_name_unset, realm_name},
                 tube_catalog_topic:topic(channel_announced)).

realm_name_must_hash_to_the_realm_tag_test() ->
    ?assertEqual(ok, tube_catalog_topic:check_realm_name(
                       <<"io.macula">>, crypto:hash(sha256, <<"io.macula">>))),
    ?assertError({mcl_tube_realm_name_mismatch, <<"io.macula">>, _},
                 tube_catalog_topic:check_realm_name(<<"io.macula">>, <<0:256>>)).

%% No module still publishes on the old, non-canonical rendezvous.
no_source_names_the_old_topics_test() ->
    Src = filename:join(code:lib_dir(guide_tube_lifecycle), "src"),
    Files = filelib:wildcard(filename:join([Src, "**", "*.erl"])),
    ?assertNotEqual([], Files),
    [?assertEqual({F, nomatch}, {F, binary:match(element(2, file:read_file(F)), <<"tube-commons">>)})
     || F <- Files].
