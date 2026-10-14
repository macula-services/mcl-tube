%% @doc Query: list channels (owner's own view -- normally exactly one
%% per mcl-tube instance today, but the read model doesn't assume
%% that).
%% Route: GET /api/tube/channels
-module(get_channels_page_api).

-export([init/2, routes/0, json_reply/0]).

routes() -> [{"/api/tube/channels", ?MODULE, []}].

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> -> handle_get(Req0, State);
        _         -> method_not_allowed(Req0, State)
    end.

handle_get(Req0, State) ->
    {Status, Body} = json_reply(),
    Req = cowboy_req:reply(Status, #{<<"content-type">> => <<"application/json">>}, Body, Req0),
    {ok, Req, State}.

%% @doc The reply this route sends. Exported so a test can pin exactly what
%% goes on the wire without a live request: encoding starts from the reply
%% BODY, not from the handler, and the row's MCIDs never reach the encoder
%% as bytes (#15).
%%
%% `json:encode/1' returns iodata and cowboy writes it as it stands, so the
%% body is not copied into a binary on the way out.
-spec json_reply() -> {200, iodata()}.
json_reply() ->
    {200, json:encode(#{ok => true,
                        channels => [tube_json_view:row(Row)
                                     || Row <- project_tube_store:list_channels()]})}.

method_not_allowed(Req0, State) ->
    Req = cowboy_req:reply(405, Req0),
    {ok, Req, State}.
