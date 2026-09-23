%% @doc Whether the realm has granted this node its provider authorization.
%%
%% On macula 12, serving an org-namespaced procedure (`mcl-tube/lookup_channel')
%% needs a D25 grant from the realm: an org_directory entry and a
%% procedure_delegation naming this node's id, issued after a human admits the
%% node on the realm. Without it mcl_om never manages to advertise, quietly
%% retrying on every republish tick, and every caller resolves to nothing
%% while this node looks healthy.
%%
%% So this asks macula, per procedure, whether the grant resolves, and keeps
%% the answer for mcl_tube_service:health/0. It changes nothing: advertising
%% stays mcl_om's job.
-module(check_provider_grant).
-behaviour(gen_server).

-export([start_link/0, status/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(INTERVAL_MS, 60000).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc `#{Procedure => granted | missing}' from the last check; empty before
%% the first one, or while the mesh has never been reachable.
-spec status() -> #{binary() => granted | missing}.
status() ->
    gen_server:call(?MODULE, status, 1000).

init([]) ->
    self() ! check,
    {ok, #{}}.

handle_call(status, _From, Status) -> {reply, Status, Status};
handle_call(_Req, _From, Status)   -> {reply, {error, unknown_call}, Status}.

handle_cast(_Msg, Status) -> {noreply, Status}.

handle_info(check, Status) ->
    erlang:send_after(?INTERVAL_MS, self(), check),
    {noreply, checked(mcl_om:mesh_handles(), Status)};
handle_info(_Msg, Status) ->
    {noreply, Status}.

terminate(_Reason, _Status) -> ok.

%% A dark mesh proves nothing about the grant, so the last answer stands.
checked({ok, Pool, Realm}, _Previous) ->
    maps:from_list([{Proc, grant(macula:provider_authorization(Pool, Realm, Proc))}
                    || Proc <- procedures()]);
checked({error, mesh_unavailable}, Previous) ->
    Previous.

grant({ok, _Authorization}) -> granted;
grant({error, _Reason})     -> missing.

procedures() ->
    Org = mcl_om_identity:org(),
    [mcl_om_capabilities:org_procedure(Org, Name)
     || #{name := Name} <- mcl_tube_service:capabilities()].
