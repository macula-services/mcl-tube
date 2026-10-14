%% @doc Query: get a channel by id.
%% Route: GET /api/tube/channels/:channel_id
-module(get_channel_by_id_api).

-export([init/2, routes/0, json_reply/1]).

routes() -> [{"/api/tube/channels/:channel_id", ?MODULE, []}].

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> -> handle_get(Req0, State);
        _         -> method_not_allowed(Req0, State)
    end.

handle_get(Req0, State) ->
    ChannelId = cowboy_req:binding(channel_id, Req0),
    {Status, Body} = json_reply(project_tube_store:get_channel(ChannelId)),
    Req = cowboy_req:reply(Status, #{<<"content-type">> => <<"application/json">>}, Body, Req0),
    {ok, Req, State}.

%% @doc The reply this route sends for a lookup result. Exported so a test
%% can pin exactly what goes on the wire without a live request: the row's
%% MCIDs never reach `json:encode/1' as bytes (#15).
%%
%% `json:encode/1' returns iodata and cowboy writes it as it stands, so the
%% body is not copied into a binary on the way out.
-spec json_reply({ok, map()} | {error, not_found}) -> {200 | 404, iodata()}.
json_reply({ok, Row}) ->
    {200, json:encode(#{ok => true, channel => tube_json_view:row(Row)})};
json_reply({error, not_found}) ->
    {404, json:encode(#{ok => false, error => <<"channel_not_found">>})}.

method_not_allowed(Req0, State) ->
    Req = cowboy_req:reply(405, Req0),
    {ok, Req, State}.
