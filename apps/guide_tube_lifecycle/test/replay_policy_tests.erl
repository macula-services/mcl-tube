%%% @doc What each event handler does with replay.
%%%
%%% evoq (>= 1.24) hands a restarted node every stored event again, marked
%%% `replaying => true'. A handler that publishes would repeat every
%%% publication on every restart, so it declares `skip'; a handler that
%%% rebuilds in-memory state would declare `deliver'. An undeclared handler
%%% still receives replay and logs a warning, so every handler here declares
%%% one, and this test finds any that does not.
-module(replay_policy_tests).

-include_lib("eunit/include/eunit.hrl").

every_event_handler_declares_a_replay_policy_test() ->
    Handlers = event_handlers(),
    ?assertNotEqual([], Handlers),
    ?assertEqual([], [M || M <- Handlers, not erlang:function_exported(M, replay_policy, 0)]).

%% All four publish to the mesh, so none of them may see replay.
every_publishing_handler_skips_replay_test() ->
    ?assertEqual([{channel_announced_v1_to_mesh, skip},
                  {on_video_clip_archived_withdraw_clip, skip},
                  {on_video_clip_published_publish_clip, skip},
                  {on_video_clip_retracted_withdraw_clip, skip}],
                 lists:sort([{M, M:replay_policy()} || M <- event_handlers()])).

event_handlers() ->
    _ = application:load(guide_tube_lifecycle),
    {ok, Mods} = application:get_key(guide_tube_lifecycle, modules),
    [M || M <- Mods,
          {module, M} =:= code:ensure_loaded(M),
          lists:member(evoq_event_handler, behaviours(M))].

behaviours(M) ->
    lists:append([B || {behaviour, B} <- M:module_info(attributes)]).
