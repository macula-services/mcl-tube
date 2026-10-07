%% @doc The libraries this service runs resolve at or above its floors. The
%% rebar.config constraints are the pin (no lock is committed), so this reads
%% the versions actually built. mcl_om 0.38 opens no store, so this service
%% opens its own, and builds on macula 14; macula 14.1 seals calls and streams
%% end to end and puts every advertisement a caller seals to in the DHT
%% (macula#33); evoq 1.26.1 measures telemetry on the monotonic clock;
%% reckon_evoq 2.7.2 reads snapshots
%% back whole (2.7.0 read them back empty, so a reloaded aggregate rebuilt from
%% nothing).
-module(mcl_tube_dependency_floors_tests).
-include_lib("eunit/include/eunit.hrl").

mcl_om_is_at_least_0_38_test() ->
    ?assert(at_least(vsn(mcl_om), [0, 38, 0])).

macula_is_at_least_14_1_test() ->
    ?assert(at_least(vsn(macula), [14, 1, 0])).

evoq_is_at_least_1_26_1_test() ->
    ?assert(at_least(vsn(evoq), [1, 26, 1])).

reckon_evoq_is_at_least_2_7_2_test() ->
    ?assert(at_least(vsn(reckon_evoq), [2, 7, 2])).

vsn(App) ->
    _ = application:load(App),
    {ok, Vsn} = application:get_key(App, vsn),
    Vsn.

%% Numeric compare of the release part, so 0.40.0 is above 0.31.1.
at_least(Vsn, Floor) ->
    [Release | _] = string:split(Vsn, "-"),
    [list_to_integer(P) || P <- string:split(Release, ".", all)] >= Floor.
