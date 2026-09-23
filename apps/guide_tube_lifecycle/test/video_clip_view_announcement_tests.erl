%%% @doc A view is announced once, live, when it is recorded.
%%%
%%% The portal adds one to a clip's view count per video_clip_viewed_v1 fact.
%%% hecate-tube published the fact from an evoq event handler, and evoq replays
%%% the whole store to every handler on each boot, so every restart announced
%%% every historical view again and inflated every count.
-module(video_clip_view_announcement_tests).

-include_lib("eunit/include/eunit.hrl").

-define(CLIP, <<"clip-1">>).
-define(CHANNEL, <<"channel-1">>).

the_fact_is_the_view_test() ->
    ?assertEqual(#{clip_id => ?CLIP, channel_id => ?CHANNEL, viewed_at => 1000},
                 video_clip_view_announcement:fact(
                   #{clip_id => ?CLIP, channel_id => ?CHANNEL, viewed_at => 1000,
                     event_type => <<"video_clip_viewed_v1">>})).

a_recorded_view_is_announced_once_test() ->
    with_mocks(fun() ->
        meck:expect(evoq_router, dispatch,
                    fun(_) -> {ok, 1, [#{clip_id => ?CLIP, channel_id => ?CHANNEL,
                                         viewed_at => 1000}]} end),
        {ok, 1, _} = maybe_record_video_clip_view:dispatch(#{clip_id => ?CLIP,
                                                              channel_id => ?CHANNEL}),
        ?assertEqual([#{clip_id => ?CLIP, channel_id => ?CHANNEL, viewed_at => 1000}],
                     announced())
    end).

a_refused_view_is_not_announced_test() ->
    with_mocks(fun() ->
        meck:expect(evoq_router, dispatch, fun(_) -> {error, not_published} end),
        {error, not_published} = maybe_record_video_clip_view:dispatch(
                                   #{clip_id => ?CLIP, channel_id => ?CHANNEL}),
        ?assertEqual([], announced())
    end).

%% The guard against the old path coming back: nothing that evoq replays on
%% boot may react to a view.
no_event_handler_reacts_to_a_view_test() ->
    _ = application:load(guide_tube_lifecycle),
    {ok, Mods} = application:get_key(guide_tube_lifecycle, modules),
    Reacting = [M || M <- Mods,
                     _ <- [code:ensure_loaded(M)],
                     erlang:function_exported(M, interested_in, 0),
                     lists:member(<<"video_clip_viewed_v1">>, M:interested_in())],
    ?assertEqual([], Reacting).

%% --- helpers ---

with_mocks(Test) ->
    ok = meck:new(evoq_router, [non_strict]),
    ok = meck:new(video_clip_view_announcement, [passthrough]),
    ok = meck:expect(video_clip_view_announcement, announce, fun(_) -> ok end),
    try Test()
    after meck:unload()
    end.

announced() ->
    [Fact || {_, {video_clip_view_announcement, announce, [Event]}, _}
                 <- meck:history(video_clip_view_announcement),
             Fact <- [video_clip_view_announcement:fact(Event)]].
