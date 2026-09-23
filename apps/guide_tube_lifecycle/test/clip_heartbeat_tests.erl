%%% @doc The heartbeat re-announces published clips, a page per tick.
%%%
%%% A restart no longer replays the catalog (evoq 1.24, replay_policy skip),
%%% so the heartbeat is how a catalogue that starts late learns about clips
%%% published before it. A page per tick keeps each tick's cost bounded by the
%%% page size however many clips there are; the cursor wraps, so every
%%% published clip is re-announced once per cycle.
-module(clip_heartbeat_tests).

-include_lib("eunit/include/eunit.hrl").

%%------------------------------------------------------------------------------
%% Paging, pure
%%------------------------------------------------------------------------------

pages_move_through_the_list_and_wrap_test() ->
    Ids = [a, b, c, d, e],
    ?assertEqual({[a, b], 2}, channel_heartbeat:next_page(Ids, 0, 2)),
    ?assertEqual({[c, d], 4}, channel_heartbeat:next_page(Ids, 2, 2)),
    ?assertEqual({[e], 0}, channel_heartbeat:next_page(Ids, 4, 2)).

%% The list shrinks when clips are retracted: a cursor past its end starts
%% over rather than announcing nothing.
a_cursor_past_the_end_starts_over_test() ->
    ?assertEqual({[a, b], 2}, channel_heartbeat:next_page([a, b, c], 7, 2)).

no_clips_is_no_page_test() ->
    ?assertEqual({[], 0}, channel_heartbeat:next_page([], 3, 25)).

%% The point of the whole thing: every published clip is announced within
%% one cycle of ceil(N / page) ticks, whatever the page size.
every_clip_is_announced_within_one_cycle_test() ->
    Ids = lists:seq(1, 53),
    Announced = cycle(Ids, 0, 10, 6, []),
    ?assertEqual(Ids, lists:usort(Announced)).

cycle(_Ids, _Cursor, _Page, 0, Acc) -> Acc;
cycle(Ids, Cursor, Page, Ticks, Acc) ->
    {Batch, Next} = channel_heartbeat:next_page(Ids, Cursor, Page),
    cycle(Ids, Next, Page, Ticks - 1, Acc ++ Batch).

%%------------------------------------------------------------------------------
%% What a tick announces
%%------------------------------------------------------------------------------

only_published_clips_are_listed_in_a_stable_order_test() ->
    ensure_started(project_tube_store:start_link()),
    Channel = <<"clip-heartbeat-tests-channel">>,
    [ok = project_tube_store:put_clip(Id, #{clip_id => Id, channel_id => Channel, status => S})
     || {Id, S} <- [{<<"chb-c">>, <<"published">>}, {<<"chb-a">>, <<"published">>},
                    {<<"chb-b">>, <<"uploaded">>}, {<<"chb-d">>, <<"retracted">>}]],
    ok = project_tube_store:put_channel(Channel, #{channel_id => Channel}),
    Listed = [Id || <<"chb-", _/binary>> = Id <- channel_heartbeat:published_clip_ids()],
    ?assertEqual([<<"chb-a">>, <<"chb-c">>], Listed).

a_tick_announces_channels_and_one_page_of_clips_test() ->
    ok = meck:new(project_tube_store, [non_strict]),
    ok = meck:expect(project_tube_store, list_channel_ids, fun() -> [<<"ch1">>] end),
    ok = meck:expect(project_tube_store, list_clips_by_channel,
                     fun(<<"ch1">>) -> [#{clip_id => Id, status => <<"published">>}
                                        || Id <- [<<"k1">>, <<"k2">>, <<"k3">>]] end),
    ok = meck:new(channel_announcement, [non_strict]),
    ok = meck:expect(channel_announcement, announce, fun(_, _) -> ok end),
    ok = meck:new(video_clip_publication, [non_strict]),
    ok = meck:expect(video_clip_publication, publish_to_mesh, fun(_) -> ok end),
    ok = application:set_env(guide_tube_lifecycle, clip_heartbeat_page, 2),
    try
        {noreply, Cursor} = channel_heartbeat:handle_info(heartbeat, 0),
        ?assertEqual(1, meck:num_calls(channel_announcement, announce, [<<"ch1">>, <<"heartbeat">>])),
        ?assertEqual([#{clip_id => <<"k1">>}, #{clip_id => <<"k2">>}],
                     [A || {_, {_, publish_to_mesh, [A]}, _} <- meck:history(video_clip_publication)]),
        ?assertEqual(2, Cursor)
    after
        application:unset_env(guide_tube_lifecycle, clip_heartbeat_page),
        meck:unload()
    end.

ensure_started({ok, _Pid}) -> ok;
ensure_started({error, {already_started, _Pid}}) -> ok.
