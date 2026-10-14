%% @doc Query: list a channel's clips (owner's own view -- every clip
%% regardless of publish status, so the owner can manage drafts; the
%% mesh-facing view is advertise_channel_lookup / advertise_video_clip_lookup,
%% which filter to published only).
%% Route: GET /api/tube/channels/:channel_id/clips
-module(get_video_clips_page_api).

-export([init/2, routes/0, json_reply/1]).

routes() -> [{"/api/tube/channels/:channel_id/clips", ?MODULE, []}].

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> -> handle_get(Req0, State);
        _         -> method_not_allowed(Req0, State)
    end.

handle_get(Req0, State) ->
    ChannelId = cowboy_req:binding(channel_id, Req0),
    {Status, Body} = json_reply(ChannelId),
    Req = cowboy_req:reply(Status, #{<<"content-type">> => <<"application/json">>}, Body, Req0),
    {ok, Req, State}.

%% @doc The reply this route sends for a channel. Exported so a test can pin
%% exactly what goes on the wire without a live request: the rows' MCIDs
%% never reach `json:encode/1' as bytes (#15).
%%
%% `json:encode/1' returns iodata and cowboy writes it as it stands, so the
%% body is not copied into a binary on the way out.
-spec json_reply(binary()) -> {200, iodata()}.
json_reply(ChannelId) ->
    {200, json:encode(#{ok => true,
                        clips => [tube_json_view:row(Row)
                                  || Row <- project_tube_store:list_clips_by_channel(ChannelId)]})}.

method_not_allowed(Req0, State) ->
    Req = cowboy_req:reply(405, Req0),
    {ok, Req, State}.
