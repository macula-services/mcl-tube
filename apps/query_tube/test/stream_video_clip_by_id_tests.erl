-module(stream_video_clip_by_id_tests).

-include_lib("eunit/include/eunit.hrl").

%% This module is also the stand-in streamer the retraction tests stream to.
-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, terminate/2]).

-define(CHUNK, 65536).

setup() ->
    {ok, Store} = project_tube_store:start_link(),
    Store.

teardown(Store) ->
    _ = catch gen_server:stop(Store),
    ok.

%% macula's frame decoder makes `clip_id' an atom key only when the atom
%% already exists in the receiving VM; otherwise the key stays as it was
%% sent. A handler that matched only the atom form rejected every other
%% form with `bad_request'. Each case below reaches the store lookup and
%% gets `not_found' for an unknown clip instead.
atom_keyed_args_are_not_rejected_as_bad_request_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            Result = stream_video_clip_by_id:handle_open(
                       #{clip_id => <<"nonexistent-clip">>}, undefined),
            ?assertEqual({stop, not_found, undefined}, Result)
        end
     end}.

binary_keyed_args_are_not_rejected_as_bad_request_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            Result = stream_video_clip_by_id:handle_open(
                       #{<<"clip_id">> => <<"nonexistent-clip">>}, undefined),
            ?assertEqual({stop, not_found, undefined}, Result)
        end
     end}.

text_valued_clip_id_is_not_rejected_as_bad_request_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            Result = stream_video_clip_by_id:handle_open(
                       #{clip_id => {text, <<"nonexistent-clip">>}}, undefined),
            ?assertEqual({stop, not_found, undefined}, Result)
        end
     end}.

missing_clip_id_is_a_bad_request_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        fun() ->
            ?assertEqual({stop, bad_request, undefined},
                         stream_video_clip_by_id:handle_open(#{}, undefined))
        end
     end}.

%% ==========================================================================
%% A STREAM ALREADY OPEN ENDS WHEN ITS CLIP STOPS BEING PUBLISHED (#9, #17).
%% The open checks the clip once; a long clip can stream for minutes after
%% that. The sender reads the clip's state before every chunk and, once it is
%% retracted or archived, stops the streamer with a non-normal reason, so the
%% viewer gets a STREAM_ERROR rather than a clean end of a truncated file.
%%
%% The streamer is a stand-in gen_server (this module's callbacks below) that
%% reports each send, a close and its termination to the test.
%% ==========================================================================

init({Parent, OnSend}) -> {ok, {Parent, OnSend, 0}}.

handle_call({send, Chunk}, _From, {Parent, OnSend, N}) ->
    Parent ! {sent, N + 1, byte_size(Chunk)},
    OnSend(N + 1),
    {reply, ok, {Parent, OnSend, N + 1}};
handle_call(close, _From, {Parent, _OnSend, _N} = State) ->
    Parent ! closed,
    {stop, normal, ok, State}.

handle_cast(_Msg, State) -> {noreply, State}.

terminate(Reason, {Parent, _OnSend, _N}) ->
    Parent ! {terminated, Reason},
    ok.

%% A published clip three chunks long, on disk.
published_clip(ClipId) ->
    Path = filename:join("/tmp", "stream_video_clip_by_id_tests_" ++
                             integer_to_list(erlang:unique_integer([positive])) ++ ".bin"),
    ok = file:write_file(Path, binary:copy(<<0>>, 3 * ?CHUNK)),
    ok = project_tube_store:put_clip(ClipId, #{clip_id => ClipId, channel_id => <<"channel-1">>,
                                               local_ref => Path, status => <<"published">>}),
    Path.

set_status(ClipId, Status) ->
    {ok, Row} = project_tube_store:get_clip(ClipId),
    ok = project_tube_store:put_clip(ClipId, Row#{status => Status}).

%% Streams `ClipId' to a stand-in streamer that runs `OnSend(N)' after the
%% N-th chunk, and returns every report it made, in order.
stream_through_stand_in(ClipId, Path, OnSend) ->
    {ok, Streamer} = gen_server:start(?MODULE, {self(), OnSend}, []),
    {ok, Fd} = file:open(Path, [read, binary]),
    spawn(fun() -> stream_video_clip_by_id:send_chunks(Streamer, Fd, ClipId, <<"channel-1">>) end),
    reports([]).

reports(Acc) ->
    receive
        {terminated, _} = Done -> lists:reverse([Done | Acc]);
        Report -> reports([Report | Acc])
    after 2000 -> lists:reverse([timeout | Acc])
    end.

a_stream_ends_with_an_error_when_its_clip_is_retracted_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        Path = published_clip(<<"clip-retracted">>),
        Reports = stream_through_stand_in(<<"clip-retracted">>, Path,
                                          fun(1) -> set_status(<<"clip-retracted">>, <<"uploaded">>);
                                             (_) -> ok
                                          end),
        ?_assertEqual([{sent, 1, ?CHUNK}, {terminated, {shutdown, video_clip_not_published}}],
                      Reports)
     end}.

a_stream_ends_with_an_error_when_its_clip_is_archived_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        Path = published_clip(<<"clip-archived">>),
        Reports = stream_through_stand_in(<<"clip-archived">>, Path,
                                          fun(2) -> set_status(<<"clip-archived">>, <<"archived">>);
                                             (_) -> ok
                                          end),
        ?_assertEqual([{sent, 1, ?CHUNK}, {sent, 2, ?CHUNK},
                       {terminated, {shutdown, video_clip_not_published}}],
                      Reports)
     end}.

%% The control: a clip that stays published streams every chunk. (Retracted
%% after the last one, so the sender stops before EOF and records no view,
%% which needs the event store.)
a_clip_that_stays_published_streams_every_chunk_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Store) ->
        Path = published_clip(<<"clip-kept">>),
        Reports = stream_through_stand_in(<<"clip-kept">>, Path,
                                          fun(3) -> set_status(<<"clip-kept">>, <<"uploaded">>);
                                             (_) -> ok
                                          end),
        ?_assertEqual([{sent, 1, ?CHUNK}, {sent, 2, ?CHUNK}, {sent, 3, ?CHUNK},
                       {terminated, {shutdown, video_clip_not_published}}],
                      Reports)
     end}.
