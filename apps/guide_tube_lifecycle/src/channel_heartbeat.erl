%% @doc Timer-driven re-publish of every channel's current snapshot,
%% every 60s regardless of new writes (Demon #45 -- fire-once publishing
%% over an unreliable transport is a previously-burned bug in this
%% workspace), and of ONE PAGE of published clips per tick.
%%
%% Clips are re-announced because a restart no longer replays the catalog
%% (the publishing handlers skip replay, evoq 1.24), so this is how a
%% catalogue that starts late learns about clips published before it. A page
%% per tick keeps a tick's cost bounded by the page size (`clip_heartbeat_page',
%% default 25) however many clips there are. The cursor walks the sorted list
%% of published clip ids and wraps, so every published clip is re-announced
%% once per cycle of ceil(clips / page) ticks, and the page grows with the
%% catalog so a cycle never exceeds 5 ticks: macula-portal expires a clip
%% listing nobody re-announced, so a lost retraction cannot list it forever.
%%
%% A plain gen_server, not an evoq behaviour: this reacts to
%% a timer, not a domain event, so evoq_event_handler doesn't fit (its
%% callback module has no hook for arbitrary messages) and Demon #39 (no
%% raw gen_servers for event reaction) doesn't apply -- there is no event
%% here to react to.
-module(channel_heartbeat).

-behaviour(gen_server).

-export([start_link/0]).
-export([next_page/3, page_size/2, published_clip_ids/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(HEARTBEAT_MS, 60_000).
-define(DEFAULT_CLIP_PAGE, 25).
%% A cycle re-announces every published clip within this many ticks, whatever
%% the page setting: a catalogue expires a listing nobody re-announced, and
%% counts on this bound (#17).
-define(MAX_CYCLE_TICKS, 5).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% The state is the clip cursor: where the next page starts.
init([]) ->
    schedule(),
    {ok, 0}.

handle_call(_Msg, _From, State) -> {reply, {error, unknown_call}, State}.
handle_cast(_Msg, State) -> {noreply, State}.

handle_info(heartbeat, Cursor) ->
    lists:foreach(fun(ChannelId) -> channel_announcement:announce(ChannelId, <<"heartbeat">>) end,
                 project_tube_store:list_channel_ids()),
    Ids = published_clip_ids(),
    {Page, Next} = next_page(Ids, Cursor, page_size(length(Ids), clip_page())),
    lists:foreach(fun(ClipId) -> video_clip_publication:publish_to_mesh(#{clip_id => ClipId}) end,
                  Page),
    schedule(),
    {noreply, Next};
handle_info(_Msg, State) -> {noreply, State}.

terminate(_Reason, _State) -> ok.

schedule() -> erlang:send_after(?HEARTBEAT_MS, self(), heartbeat).

%% @doc The page of `Ids' starting at `Cursor', and where the next one starts.
%% A cursor past the end (the list shrank) starts over; the last page wraps
%% the cursor back to 0.
-spec next_page([term()], non_neg_integer(), pos_integer()) ->
    {[term()], non_neg_integer()}.
next_page([], _Cursor, _Size) ->
    {[], 0};
next_page(Ids, Cursor, Size) when Cursor >= length(Ids) ->
    next_page(Ids, 0, Size);
next_page(Ids, Cursor, Size) ->
    Page = lists:sublist(Ids, Cursor + 1, Size),
    {Page, wrapped(Cursor + length(Page), length(Ids))}.

wrapped(Next, Total) when Next >= Total -> 0;
wrapped(Next, _Total)                   -> Next.

%% @doc The page a tick announces: the configured size, grown so that `Count'
%% clips take at most ?MAX_CYCLE_TICKS ticks.
-spec page_size(non_neg_integer(), pos_integer()) -> pos_integer().
page_size(Count, Configured) ->
    max(Configured, (Count + ?MAX_CYCLE_TICKS - 1) div ?MAX_CYCLE_TICKS).

%% @doc Every published clip's id, sorted, so pages are stable between ticks.
-spec published_clip_ids() -> [binary()].
published_clip_ids() ->
    lists:sort([Id || ChannelId <- project_tube_store:list_channel_ids(),
                      #{clip_id := Id, status := <<"published">>}
                          <- project_tube_store:list_clips_by_channel(ChannelId)]).

clip_page() ->
    application:get_env(guide_tube_lifecycle, clip_heartbeat_page, ?DEFAULT_CLIP_PAGE).
