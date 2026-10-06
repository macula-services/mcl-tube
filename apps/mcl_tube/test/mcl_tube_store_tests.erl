%% @doc The store mcl_tube_app opens at boot, through the same call, against a
%% real reckon-db: a command dispatched through evoq lands on its stream and
%% reads back by event type, and opening an open store is no error. mcl_om
%% opens no store from 0.35, so nothing else proves this one opens.
-module(mcl_tube_store_tests).

-include_lib("eunit/include/eunit.hrl").

store_test_() ->
    {setup, fun start/0, fun stop/1,
     [{timeout, 60, fun a_dispatched_channel_lands_in_the_store/0},
      {timeout, 60, fun opening_an_open_store_is_no_error/0}]}.

a_dispatched_channel_lands_in_the_store() ->
    {ok, ChannelId, _Version, [_Event]} =
        maybe_initiate_channel:dispatch(#{name => <<"Rafael">>, owner => <<"acme">>}),
    {ok, Read} = evoq_event_store:read_events_by_types(
                   mcl_tube_store, [<<"channel_initiated_v1">>], 100),
    ?assertMatch([_], [E || #{stream_id := S} = E <- Read, S =:= ChannelId]).

opening_an_open_store_is_no_error() ->
    ?assertEqual(ok, mcl_tube_store:open(mcl_tube_service:event_store())).

start() ->
    Dir = filename:join("/tmp", "mcl_tube_store_tests_" ++
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
