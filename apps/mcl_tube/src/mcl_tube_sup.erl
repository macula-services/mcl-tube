%% @doc Supervises the service's own processes: the HTTP listener serving the
%% owner's web UI and the QRY read API on one port, and the provider-grant
%% check behind health.
%%
%% The listener has no authentication of its own, and the container runs on
%% host networking, so it binds LOOPBACK unless `http_ip' says otherwise: an
%% owner reaches it over an SSH tunnel. Binding it wider hands upload,
%% reconfigure and retract to anyone who can reach the port.
-module(mcl_tube_sup).

-behaviour(supervisor).

-export([start_link/0, init/1, socket_opts/0]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10},
          [http_listener(),
           #{id => check_provider_grant,
             start => {check_provider_grant, start_link, []},
             restart => permanent, shutdown => 5000, type => worker,
             modules => [check_provider_grant]}]}}.

http_listener() ->
    Routes = tube_owner_ui_routes:routes() ++ query_tube_sup:routes(),
    Dispatch = cowboy_router:compile([{'_', Routes}]),
    ranch:child_spec(mcl_tube_http, ranch_tcp, socket_opts(),
                     cowboy_clear, #{env => #{dispatch => Dispatch}}).

%% @doc The listener's port and bind address.
-spec socket_opts() -> [{port, inet:port_number()} | {ip, inet:ip_address()}].
socket_opts() ->
    [{port, application:get_env(mcl_tube, http_port, 8491)},
     {ip, address(application:get_env(mcl_tube, http_ip, "127.0.0.1"))}].

address(Text) when is_binary(Text) -> address(binary_to_list(Text));
address(Text) ->
    {ok, Ip} = inet:parse_strict_address(Text),
    Ip.
