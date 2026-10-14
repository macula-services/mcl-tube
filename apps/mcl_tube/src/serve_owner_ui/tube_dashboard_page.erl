%% @doc Owner dashboard: current channel status (or a prompt to create one)
%% plus the clip list with publish/retract/archive actions -- the one entry
%% point every other owner-UI page links back to.
%%
%% The grid holds the clips the owner can act on. A clip they discarded is
%% not in it -- it stays in the read model and is listed, collapsed, below.
%% Route: GET /
-module(tube_dashboard_page).

-export([init/2, routes/0]).
-export([newest_first/1, split_archived/1, clip_section/1]). %% for tests

routes() -> [{"/", ?MODULE, []}].

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> -> handle_get(Req0, State);
        _         -> tube_owner_http:method_not_allowed(Req0, State)
    end.

handle_get(Req0, State) ->
    Flash = flash_param(Req0),
    Body = tube_html:page(<<"Dashboard">>, render(project_tube_store:list_channels(), Flash)),
    tube_owner_http:reply_html(Body, Req0, State).

render([], Flash) ->
    [tube_html:flash_banner(Flash),
     <<"<h1>Welcome</h1>"
       "<p>You have not configured a channel yet.</p>"
       "<p><a class=\"button\" href=\"/owner/channel/configure\">"
       "Configure your channel</a></p>">>];
render([Channel | _], Flash) ->
    ChannelId = maps:get(channel_id, Channel, undefined),
    [tube_html:flash_banner(Flash),
     channel_card(Channel),
     <<"<h2>Video Clips</h2>"
       "<p><a class=\"button\" href=\"/owner/clips/upload\">Upload a clip</a></p>">>,
     clip_section(ChannelId)].

channel_card(Channel) ->
    Name = maps:get(name, Channel, undefined),
    Description = maps:get(description, Channel, undefined),
    Tags = maps:get(tags, Channel, []),
    LogoMcid = maps:get(logo_mcid, Channel, undefined),
    [<<"<section class=\"card\">">>, logo_img(LogoMcid), <<"<h1>">>, tube_html:escape(Name), <<"</h1>"
       "<p>">>, tube_html:escape(Description), <<"</p>"
       "<p>">>, tag_spans(Tags), <<"</p>"
       "<p><a href=\"/owner/channel/configure\">Edit channel</a></p></section>">>].

logo_img(undefined) -> <<>>;
logo_img(LogoMcid) ->
    [<<"<img class=\"logo\" src=\"/owner/content/">>, binary:encode_hex(LogoMcid),
     <<"\" alt=\"\">">>].

tag_spans(Tags) ->
    [ [<<"<span class=\"tag\">">>, tube_html:escape(T), <<"</span>">>] || T <- Tags ].

%% @doc The grid the owner acts in, and the discarded clips below it.
clip_section(undefined) -> <<>>;
clip_section(ChannelId) ->
    {Active, Archived} = split_archived(project_tube_store:list_clips_by_channel(ChannelId)),
    [clip_grid(Active), archived_section(Archived)].

clip_grid([]) -> <<"<p class=\"empty\">No clips yet.</p>">>;
clip_grid(Active) ->
    [<<"<div class=\"clip-grid\">">>, [clip_card(C) || C <- Active], <<"</div>">>].

%% @doc The clips the owner can still act on, and the ones they discarded.
%%
%% Archive is a lifecycle state, not a delete: the row stays in the read
%% model, and the dashboard must still say the clip is there. It is not a
%% card, though -- nothing about an archived clip can be published, retracted
%% or discarded again -- and a grid of cards with no buttons is what the
%% owner read as a broken page. Both lists come back newest first.
-spec split_archived([map()]) -> {[map()], [map()]}.
split_archived(Clips) ->
    lists:partition(fun(C) -> maps:get(status, C, undefined) =/= <<"archived">> end,
                    newest_first(Clips)).

%% Collapsed, so the owner's grid holds only clips they can act on.
archived_section([]) -> <<>>;
archived_section(Archived) ->
    [<<"<details class=\"archived\"><summary>Archived (">>,
     integer_to_binary(length(Archived)), <<")</summary><ul>">>,
     [archived_entry(C) || C <- Archived],
     <<"</ul></details>">>].

%% Name and nothing else: no thumbnail, no views, no buttons.
archived_entry(Clip) ->
    [<<"<li>">>, tube_html:escape(maps:get(name, Clip, undefined)),
     <<" <span class=\"status status-archived\">archived</span></li>">>].

%% @doc Clip ids end in a UUIDv7 (reckon_gater_stream_id), so they sort
%% by upload time: the clip just uploaded heads the grid.
-spec newest_first([map()]) -> [map()].
newest_first(Clips) ->
    lists:sort(fun(A, B) -> maps:get(clip_id, A) >= maps:get(clip_id, B) end, Clips).

clip_card(Clip) ->
    ClipId = maps:get(clip_id, Clip, <<>>),
    Name = maps:get(name, Clip, undefined),
    Status = maps:get(status, Clip, <<"uploaded">>),
    ViewCount = maps:get(view_count, Clip, 0),
    [<<"<article class=\"card clip\"><h3>">>, tube_html:escape(Name), <<"</h3>"
       "<span class=\"status status-">>, Status, <<"\">">>, Status, <<"</span>"
       "<p class=\"muted\">">>, integer_to_binary(ViewCount), <<" views</p>">>,
     rejection_notice(Status, Clip),
     <<"<div class=\"actions\">">>, clip_actions(ClipId, Status), <<"</div></article>">>].

rejection_notice(<<"rejected">>, Clip) ->
    Reason = maps:get(rejected_reason, Clip, <<"unknown reason">>),
    [<<"<p class=\"muted\">Rejected: ">>, tube_html:escape(Reason), <<"</p>">>];
rejection_notice(_Status, _Clip) ->
    <<>>.

%% `ClipId'/`Status' are always system-generated (reckon_gater_stream_id /
%% this app's own projection), never user-supplied text -- safe to
%% interpolate directly, no escaping needed.
%%
%% No clause for `<<"archived">>': split_archived/1 keeps those rows out of
%% the grid, and they are the only status this can be reached with that has
%% nothing to offer the owner. `uploaded', `published' and `rejected' are
%% the rest of what the projection writes.
clip_actions(ClipId, <<"uploaded">>) ->
    [action_button(ClipId, <<"publish">>, <<"Publish">>, false),
     action_button(ClipId, <<"archive">>, <<"Discard">>, true)];
clip_actions(ClipId, <<"published">>) ->
    [action_button(ClipId, <<"retract">>, <<"Retract">>, false),
     action_button(ClipId, <<"archive">>, <<"Archive">>, true)];
clip_actions(_ClipId, <<"rejected">>) ->
    [<<"<span class=\"muted\">Try uploading again.</span>">>].

action_button(ClipId, Action, Label, Danger) ->
    Class = case Danger of true -> <<" class=\"danger\"">>; false -> <<>> end,
    [<<"<form method=\"post\" action=\"/owner/clips/">>, ClipId, <<"/">>, Action, <<"\">"
       "<button type=\"submit\"">>, Class, <<">">>, Label, <<"</button></form>">>].

flash_param(Req) ->
    proplists:get_value(<<"flash">>, cowboy_req:parse_qs(Req)).
