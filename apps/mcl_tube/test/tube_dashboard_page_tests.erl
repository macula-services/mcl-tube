%% @doc The dashboard's clip list (#21). Archiving a clip is a lifecycle
%% state, not a delete: `video_clip_lifecycle_to_video_clips' keeps the row
%% and sets its status to `<<"archived">>'. The grid rendered every row of
%% the channel, so a discarded clip sat in it as a card with nothing to
%% click -- which the owner reads as a broken page.
%%
%% These pin the split and the markup it produces: the grid holds the clips
%% the owner can act on, and a discarded one is named, escaped, below it.
-module(tube_dashboard_page_tests).

-include_lib("eunit/include/eunit.hrl").

-define(PAGE, tube_dashboard_page).

%%==============================================================================
%% The split
%%==============================================================================

split_archived_puts_only_discarded_clips_in_the_second_list_test() ->
    Old = live(oldest_id(), <<"Old">>),
    New = live(middle_id(), <<"New">>),
    Gone = discarded(<<"Discarded">>),
    {Active, Archived} = ?PAGE:split_archived([Old, Gone, New]),
    ?assertEqual([New, Old], Active),
    ?assertEqual([Gone], Archived).

%% Both lists are newest first, so the section below the grid reads in the
%% same order as the grid.
split_archived_keeps_both_lists_newest_first_test() ->
    Older = discarded_at(middle_id(), <<"Older">>),
    Newer = discarded(<<"Newer">>),
    {[], Archived} = ?PAGE:split_archived([Older, Newer]),
    ?assertEqual([Newer, Older], Archived).

%%==============================================================================
%% What the owner sees
%%==============================================================================

store_test_() ->
    {foreach,
     fun() -> store_up() end,
     fun(Pid) -> store_down(Pid) end,
     [fun the_grid_holds_the_discarded_clips_out/1,
      fun a_channel_whose_only_clip_is_discarded_still_says_so/1,
      fun a_named_clip_that_was_discarded_is_escaped/1]}.

the_grid_holds_the_discarded_clips_out(_Store) ->
    fun() ->
        ok = put(live(middle_id(), <<"Keep me">>)),
        ok = put(discarded(<<"Delete me">>)),
        {Grid, Archived} = grid_and_archived(<<"ch-1">>),
        %% One card, for the live clip: the discarded one used to render one
        %% too, with a name, a view count and no buttons.
        ?assertEqual(1, count(Grid, <<"card clip">>)),
        ?assertEqual(nomatch, binary:match(Grid, <<"Delete me">>)),
        ?assertNotEqual(nomatch, binary:match(Grid, <<"Keep me">>)),
        ?assertNotEqual(nomatch, binary:match(Archived, <<"Delete me">>)),
        %% Nothing to click: no form, so no publish, retract or archive.
        ?assertEqual(nomatch, binary:match(Archived, <<"<form">>))
    end.

a_channel_whose_only_clip_is_discarded_still_says_so(_Store) ->
    fun() ->
        ok = put(discarded(<<"Delete me">>)),
        {Grid, Archived} = grid_and_archived(<<"ch-1">>),
        ?assertNotEqual(nomatch, binary:match(Grid, <<"No clips yet.">>)),
        ?assertNotEqual(nomatch, binary:match(Archived, <<"Archived (1)">>))
    end.

%% The name is the owner's own text and it goes into the page, so it is
%% escaped here as everywhere else (tube_html's module doc).
a_named_clip_that_was_discarded_is_escaped(_Store) ->
    fun() ->
        ok = put(discarded(<<"<script>alert(1)</script>">>)),
        {Grid, Archived} = grid_and_archived(<<"ch-1">>),
        ?assertNotEqual(nomatch, binary:match(Archived, <<"&lt;script&gt;">>)),
        ?assertEqual(nomatch, binary:match(Grid, <<"<script>">>)),
        ?assertEqual(nomatch, binary:match(Archived, <<"<script>">>))
    end.

%% The rendered section, split where the grid ends: everything before the
%% collapsed list is the grid the owner acts in.
grid_and_archived(ChannelId) ->
    Markup = iolist_to_binary(?PAGE:clip_section(ChannelId)),
    [Grid, Archived] = binary:split(Markup, <<"<details">>),
    {Grid, Archived}.

count(Haystack, Needle) ->
    length(binary:matches(Haystack, Needle)).

%%==============================================================================
%% The rows, as the projection writes them
%%==============================================================================

%% Clip ids end in a UUIDv7 (reckon_gater_stream_id), so they sort by upload
%% time: three of them, oldest first, is what newest_first/1 reorders.
oldest_id() -> <<"clip-01a0f67a86b6796ba9d53632fd4074a4">>.
middle_id() -> <<"clip-01a106962ead7152b7d21012d4ab220c">>.
newest_id() -> <<"clip-01a1383dad1671acacbda1211bef3bb0">>.

live(ClipId, Name) -> clip(ClipId, Name, <<"uploaded">>).
discarded(Name) -> discarded_at(newest_id(), Name).
discarded_at(ClipId, Name) -> clip(ClipId, Name, <<"archived">>).

clip(ClipId, Name, Status) ->
    #{clip_id => ClipId, channel_id => <<"ch-1">>, name => Name, description => <<>>,
      tags => [], thumbnail_mcid => undefined, local_ref => <<"/data/x.mp4">>,
      status => Status, view_count => 0}.

put(Clip) -> project_tube_store:put_clip(maps:get(clip_id, Clip), Clip).

%%==============================================================================
%% The store
%%==============================================================================

%% The store is a registered singleton whose ETS tables are public, and a
%% suite that ran before this one can leave it up: this one wants its own
%% empty store, and gives the VM back the same way it found it.
store_up() ->
    _ = catch gen_server:stop(project_tube_store),
    {ok, Pid} = project_tube_store:start_link(),
    unlink(Pid),
    Pid.

store_down(Pid) ->
    exit(Pid, shutdown),
    Ref = monitor(process, Pid),
    receive {'DOWN', Ref, process, Pid, _} -> ok end.
