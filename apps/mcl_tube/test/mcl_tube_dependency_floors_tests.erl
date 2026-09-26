%% @doc The store this service runs resolves at or above its floors. The
%% rebar.config constraints are the pin (no lock is committed), so this reads
%% the versions actually built. mcl_om 0.31.1 carries the floors every mcl
%% service inherits; reckon_evoq 2.7.2 reads snapshots back whole (2.7.0 read
%% them back empty, so a reloaded aggregate rebuilt from nothing).
-module(mcl_tube_dependency_floors_tests).
-include_lib("eunit/include/eunit.hrl").

mcl_om_is_at_least_0_31_1_test() ->
    ?assert(at_least(vsn(mcl_om), [0, 31, 1])).

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
