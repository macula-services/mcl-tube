%% @doc The libraries this service runs resolve at or above its floors. The
%% rebar.config constraints are the pin (no lock is committed), so this reads
%% the versions actually built. mcl_om 1.6 is the macula-18 line: macula
%% arrives through it, and it refuses the boot of a handler-bearing capability
%% that names no caller, so a floor left on 1.0 would pass a build this service
%% could not boot on. macula 18.0 refuses an advertise that names no call class
%% (macula#147) and requires a topic subscription to name its sources, neither
%% of which the older 15.6 floor could see; it keeps what 15.6 was the floor
%% for — wire 1.0, calls and streams sealed end to end, every advertisement a
%% caller seals to in the DHT (macula#33), a stream's `required' reaching its
%% advertisement (macula#85). evoq 1.26.1 measures telemetry on the monotonic
%% clock; reckon_evoq 2.7.2 reads snapshots back whole (2.7.0 read them back
%% empty, so a reloaded aggregate rebuilt from nothing).
-module(mcl_tube_dependency_floors_tests).
-include_lib("eunit/include/eunit.hrl").

mcl_om_is_at_least_1_6_test() ->
    ?assert(at_least(vsn(mcl_om), [1, 6, 0])).

macula_is_at_least_18_0_test() ->
    ?assert(at_least(vsn(macula), [18, 0, 0])).

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
