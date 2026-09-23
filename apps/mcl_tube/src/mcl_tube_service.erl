%% @doc The mcl_om service contract for mcl-tube.
%%
%% Video channels over the mesh. An owner uploads and publishes clips through
%% the local web UI; anyone looks a channel, a clip or its content up, and
%% streams a clip, over four org-namespaced procedures under `mcl-tube'. The
%% catalog is announced on io.macula/mcl-tube/tube/catalog/*_v1.
%%
%% SIX CALLBACKS, ALL REQUIRED. mcl_om resolves them BY NAME at startup, so the
%% `-behaviour' attribute below turns a missing one into a compile error.
-module(mcl_tube_service).

-behaviour(mcl_om_service).

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0]).
%% ==========================================================================
%% AND TWO OPTIONAL ONES, WHICH TURN THE STORE ON
%% ==========================================================================
%%
%% Generated because this service was scaffolded with `store=1'. Exporting
%% `store_id/0' and `data_dir/0' TOGETHER makes `mcl_om:boot/1' open a
%% reckon-db store before this module's `start/1' fires.
%%
%% ⚠ THE reckon-db APPLICATIONS RUN EITHER WAY. `reckon_db', `reckon_evoq',
%% `reckon_gater', `evoq', `khepri' and `ra' start with `mcl_om' whether these
%% callbacks exist or not. What the two add is a STORE: a data directory, an open
%% handle, and something written. A sibling service claimed for months that they
%% suppressed the whole stack while six of its thirty-one running applications
%% quietly disproved it.
%%
%% ⚠⚠ AND `config/sys.config.src' MUST CARRY THE `evoq' BLOCK, which is why it was
%% generated with one. mcl_om starts a per-store evoq subscription that reads
%% the global log, and that crashes on `{not_configured, event_store_adapter}'
%% without it. evoq starts as a release-boot application before any service's
%% `start/2' runs, so nothing can inject it later. A sibling put two of three
%% fleet nodes into a boot-crash loop this exact way.
-export([store_id/0, data_dir/0]).

info() ->
    #{name => <<"mcl-tube">>,
      version => <<"0.1.0">>,
      description => <<"Video channels over the mesh: owners publish clips, anyone looks them up and streams them">>}.

%% The realm name the catalog topics carry must be the realm the pool is in,
%% or every announcement goes where no catalogue listens.
start(_Opts) ->
    ok = tube_catalog_topic:check_realm_name(),
    mcl_tube_sup:start_link().

stop(_State) -> ok.

%% Nothing of the service's own can fail here. Whether callers can REACH it
%% (each procedure's realm-issued D25 provider grant) is reported by mcl_om's
%% /health itself, combined with this verdict.
health() -> ok.

%% The four procedures, registered by mcl_om as `mcl-tube/<name>' (the org
%% comes from config). The watch is a stream, served by macula_streamer; the
%% others are request and reply.
capabilities() ->
    [#{name => <<"lookup_channel">>, version => 1,
       handler => {advertise_channel_lookup, []}},
     #{name => <<"lookup_video_clip">>, version => 1,
       handler => {advertise_video_clip_lookup, []}},
     #{name => <<"lookup_content">>, version => 1,
       handler => {advertise_content_lookup, []}},
     #{name => <<"watch_video_clip">>, version => 1,
       handler => {stream_video_clip_by_id, []}, kind => streamer}].

%% THE AUTHORITY THIS SERVICE ASKS THE REALM FOR, and deliberately nothing more.
%% Ask for exactly the topics you publish and subscribe to. Popped, an attacker
%% gains precisely this and no more, which is the whole point of listing it.
%%
%% The scope is claimed now because it is the namespace every later resource
%% hangs under, and a scope costs nothing while a rename costs every deployed
%% peer.
identity_spec() ->
    #{scope => <<"mcl-tube">>,
      actions => [],
      resources => [],
      ttl_days => 30}.

%% ==========================================================================
%% The store
%% ==========================================================================

%% @doc The reckon-db store this service owns.
%%
%% ⚠ IT IS NAMED IN TWO PLACES, here and in the `evoq' block of
%% `config/sys.config.src', and nothing makes them agree by itself. Disagreeing
%% opens one store and addresses another. A generated test compares the two.
-spec store_id() -> atom().
store_id() -> mcl_tube_store.

%% @doc Where it lives on disk.
%%
%% ⚠ DEFAULTS TO A PATH INSIDE THE CONTAINER AND MUST NOT STAY THERE ON A NODE.
%% The fleet keeps application data on its `/bulk' drives and boots from a small
%% eMMC, so `deploy/docker-compose.yml' mounts a volume and sets this. The default
%% is what a laptop wants; a container without the mount loses its record on every
%% recreate, which is the same as not keeping one.
-spec data_dir() -> string().
data_dir() -> chosen(os:getenv("MCL_DATA_DIR")).

chosen(false) -> "/tmp/mcl_tube";
chosen("") -> "/tmp/mcl_tube";
chosen(Path) -> Path.
