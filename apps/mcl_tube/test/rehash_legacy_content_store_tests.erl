%% @doc The boot migration end to end, against the store mcl_tube_app opens: a
%% channel initiated with a legacy BLAKE3 logo is told its SHA-384 MCID through
%% evoq, the aggregate takes it, the bytes move to their SHA-384 name, and a
%% second run finds nothing to do (macula-io/macula#46).
-module(rehash_legacy_content_store_tests).

-include_lib("eunit/include/eunit.hrl").

-define(BYTES, <<"a logo as tube stored it before">>).

store_test_() ->
    {setup, fun start/0, fun stop/1,
     [{timeout, 60, fun a_legacy_logo_is_rehashed_through_the_store/0}]}.

a_legacy_logo_is_rehashed_through_the_store() ->
    Legacy = <<1, 16#55, (crypto:hash(sha256, ?BYTES))/binary>>,
    Sha384 = <<2, 16#55, (crypto:hash(sha384, ?BYTES))/binary>>,
    LegacyFile = filename:join(tube_content_store:dir(),
                               <<(binary:encode_hex(Legacy, lowercase))/binary, ".bin">>),
    ok = filelib:ensure_dir(LegacyFile),
    ok = file:write_file(LegacyFile, ?BYTES),
    {ok, ChannelId, _, _} = maybe_initiate_channel:dispatch(
        #{name => <<"Rafael">>, owner => <<"acme">>, logo_mcid => Legacy}),

    ?assertMatch(#{rehashed := 1, failed := 0, removed := 1, leftover := 0},
                 rehash_legacy_content:run()),
    ?assertEqual({ok, ?BYTES}, tube_content_store:read(binary:encode_hex(Sha384, lowercase))),
    ?assertNot(filelib:is_regular(LegacyFile)),
    {ok, Rehashed} = evoq_event_store:read_events_by_types(
                       mcl_tube_store, [<<"channel_logo_rehashed_v1">>], 100),
    ?assertMatch([#{logo_mcid := Sha384, legacy_mcid := Legacy}],
                 [E || #{stream_id := S} = E <- Rehashed, S =:= ChannelId]),

    ?assertMatch(#{rehashed := 0, missing := 1, removed := 0}, rehash_legacy_content:run()).

start() ->
    Dir = filename:join("/tmp", "rehash_legacy_content_store_tests_" ++
                        integer_to_list(erlang:unique_integer([positive]))),
    os:putenv("MCL_DATA_DIR", Dir),
    _ = application:load(evoq),
    [ok = application:set_env(evoq, K, V)
     || {K, V} <- [{event_store_adapter, reckon_evoq_adapter},
                   {subscription_adapter, reckon_evoq_adapter},
                   {snapshot_store_adapter, reckon_evoq_adapter},
                   {store_id, mcl_tube_store}]],
    {ok, Started} = application:ensure_all_started([reckon_db, evoq, reckon_evoq]),
    ok = mcl_tube_store:open(mcl_tube_service:event_store()),
    {Dir, Started}.

stop({Dir, Started}) ->
    [application:stop(App) || App <- lists:reverse(Started)],
    os:unsetenv("MCL_DATA_DIR"),
    _ = file:del_dir_r(Dir),
    ok.
