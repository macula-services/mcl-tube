%% @doc `video_clip_scan:probe/3' already computes duration/size
%% synchronously as part of every upload (see video_clip_scan.erl) --
%% these were computed and then discarded before ever reaching the
%% owner. This pins the formatting that now surfaces them in the
%% post-upload flash message.
-module(tube_video_clip_upload_page_tests).

-include_lib("eunit/include/eunit.hrl").

-define(PAGE, tube_video_clip_upload_page).

format_duration_under_a_minute_test() ->
    ?assertEqual(<<"00:07">>, ?PAGE:format_duration(7_000)).

format_duration_over_a_minute_test() ->
    ?assertEqual(<<"01:23">>, ?PAGE:format_duration(83_000)).

format_duration_rounds_down_to_the_second_test() ->
    ?assertEqual(<<"00:01">>, ?PAGE:format_duration(1_999)).

format_size_under_a_megabyte_reads_as_kb_test() ->
    ?assertEqual(<<"512.0KB">>, ?PAGE:format_size(512_000)).

format_size_over_a_megabyte_reads_as_mb_test() ->
    ?assertEqual(<<"5.6MB">>, ?PAGE:format_size(5_618_695)).

accepted_message_with_no_scan_data_falls_back_to_the_bare_message_test() ->
    ?assertEqual(<<"Clip uploaded, private until you publish it.">>,
                 ?PAGE:accepted_message(undefined)).

accepted_message_with_scan_data_includes_duration_and_size_test() ->
    ?assertEqual(
       <<"Clip uploaded (01:23, 5.6MB), private until you publish it.">>,
       ?PAGE:accepted_message({83_000, 5_618_695})).

%% The success flash must mean the clip's card exists: the read model is
%% filled asynchronously, so the page waits for the row (#20).
store_test_() ->
    {foreach,
     fun() -> {ok, Pid} = project_tube_store:start_link(), unlink(Pid), Pid end,
     fun(Pid) -> exit(Pid, shutdown), wait_down(Pid) end,
     [fun await_clip_returns_once_the_row_lands/1,
      fun await_clip_times_out_without_a_row/1]}.

await_clip_returns_once_the_row_lands(_Pid) ->
    fun() ->
        ClipId = <<"clip-0000000000000000000000000000aaaa">>,
        spawn(fun() ->
                  timer:sleep(150),
                  project_tube_store:put_clip(ClipId, #{clip_id => ClipId})
              end),
        ?assertEqual(ok, ?PAGE:await_clip(ClipId, 2_000))
    end.

await_clip_times_out_without_a_row(_Pid) ->
    fun() ->
        ?assertEqual(timeout,
                     ?PAGE:await_clip(<<"clip-0000000000000000000000000000bbbb">>, 100))
    end.

card_message_claims_success_only_when_the_card_exists_test() ->
    ?assertEqual(<<"Clip uploaded, private until you publish it.">>,
                 ?PAGE:card_message(ok, undefined)),
    Pending = ?PAGE:card_message(timeout, {83_000, 5_618_695}),
    ?assertEqual(nomatch, binary:match(Pending, <<"uploaded">>)),
    ?assertNotEqual(nomatch, binary:match(Pending, <<"still being processed">>)).

dashboard_lists_the_newest_clip_first_test() ->
    Old = #{clip_id => <<"clip-01a0f67a86b6796ba9d53632fd4074a4">>},
    Mid = #{clip_id => <<"clip-01a106962ead7152b7d21012d4ab220c">>},
    New = #{clip_id => <<"clip-01a1383dad1671acacbda1211bef3bb0">>},
    ?assertEqual([New, Mid, Old], tube_dashboard_page:newest_first([Mid, Old, New])).

wait_down(Pid) ->
    Ref = monitor(process, Pid),
    receive {'DOWN', Ref, process, Pid, _} -> ok end.
