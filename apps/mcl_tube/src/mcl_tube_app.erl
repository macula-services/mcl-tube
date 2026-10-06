%% @doc OTP application entry.
%%
%% Opens this service's own reckon-db store and its evoq subscription
%% (mcl_tube_store, from mcl_tube_service:event_store/0), THEN lets
%% mcl_om:boot/1 wire the mesh, the realm identity, capabilities and health and
%% start the service. mcl_om opens no store (0.35, mcl-om#10).
%%
%% The three departments start before this app does (they are listed in the
%% .app.src applications tuple), so by the time the store subscription starts
%% its catch-up replay here, every projection is already registered.
-module(mcl_tube_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) ->
    ok = mcl_tube_store:open(mcl_tube_service:event_store()),
    mcl_om:boot(mcl_tube_service).

stop(_State) -> ok.
