%% @doc The boot migration re-hashes every logo and thumbnail still named by a
%% legacy BLAKE3 MCID once: the bytes go under their SHA-384 MCID, the channel
%% or clip is told its new MCID, and the legacy file goes. Nothing is removed
%% that a failed rehash still needs, and nothing at all when the events cannot
%% be read (macula-io/macula#46).
-module(rehash_legacy_content_tests).

-include_lib("eunit/include/eunit.hrl").

migration_test_() ->
    {foreach, fun setup/0, fun teardown/1,
     [fun a_logo_and_a_thumbnail_are_rehashed_and_the_legacy_files_go/1,
      fun a_logo_replaced_since_is_stale_and_its_file_still_goes/1,
      fun a_failed_rehash_keeps_its_legacy_file/1,
      fun a_reference_without_a_file_is_missing/1,
      fun unreadable_events_touch_nothing/1,
      fun an_unreferenced_legacy_file_is_left_alone/1,
      fun a_read_cut_off_at_the_cap_touches_nothing/1,
      fun a_second_run_finds_nothing_to_do/1]}.

setup() ->
    Dir = filename:join("/tmp", "rehash_legacy_content_tests_" ++
                        integer_to_list(erlang:unique_integer([positive]))),
    os:putenv("MCL_DATA_DIR", Dir),
    Dir.

teardown(Dir) ->
    os:unsetenv("MCL_DATA_DIR"),
    _ = file:del_dir_r(Dir),
    ok.

a_logo_and_a_thumbnail_are_rehashed_and_the_legacy_files_go(_Dir) ->
    Logo = legacy(<<"logo bytes">>),
    Thumb = legacy(<<"thumb bytes">>),
    Events = [event(<<"channel_initiated_v1">>, #{channel_id => <<"ch-1">>, logo_mcid => Logo}),
              event(<<"video_clip_uploaded_v1">>, #{clip_id => <<"clip-1">>,
                                                   thumbnail_mcid => undefined}),
              event(<<"video_clip_scanned_v1">>, #{<<"clip_id">> => <<"clip-1">>,
                                                  <<"thumbnail_mcid">> => Thumb})],
    Report = rehash_legacy_content:migrate({ok, Events}, recorder(ok)),
    Dispatched = lists:sort(dispatched()),
    [?_assertEqual([{logo, <<"ch-1">>, Logo, sha384(<<"logo bytes">>)},
                    {thumbnail, <<"clip-1">>, Thumb, sha384(<<"thumb bytes">>)}],
                   Dispatched),
     ?_assertEqual({ok, <<"logo bytes">>}, read(sha384(<<"logo bytes">>))),
     ?_assertEqual({ok, <<"thumb bytes">>}, read(sha384(<<"thumb bytes">>))),
     ?_assertEqual([], legacy_files()),
     ?_assertMatch(#{rehashed := 2, stale := 0, missing := 0, failed := 0, removed := 2,
                     leftover := 0}, Report)].

%% The channel moved on to another legacy logo: the first is refused as stale
%% by the aggregate, the second is rehashed, and both legacy files go.
a_logo_replaced_since_is_stale_and_its_file_still_goes(_Dir) ->
    Old = legacy(<<"old logo">>),
    New = legacy(<<"new logo">>),
    Events = [event(<<"channel_initiated_v1">>, #{channel_id => <<"ch-1">>, logo_mcid => Old}),
              event(<<"channel_reconfigured_v1">>, #{channel_id => <<"ch-1">>, logo_mcid => New})],
    Refuse = fun({logo, _, L, _}) when L =:= Old -> {error, logo_is_not_the_legacy_mcid};
                (_) -> {ok, 1, []}
             end,
    Report = rehash_legacy_content:migrate({ok, Events}, Refuse),
    [?_assertMatch(#{rehashed := 1, stale := 1, failed := 0, removed := 2}, Report),
     ?_assertEqual([], legacy_files())].

a_failed_rehash_keeps_its_legacy_file(_Dir) ->
    Logo = legacy(<<"logo bytes">>),
    Events = [event(<<"channel_initiated_v1">>, #{channel_id => <<"ch-1">>, logo_mcid => Logo})],
    Report = rehash_legacy_content:migrate({ok, Events}, fun(_) -> {error, timeout} end),
    [?_assertMatch(#{failed := 1, removed := 0}, Report),
     ?_assertEqual([hex(Logo)], legacy_files())].

a_reference_without_a_file_is_missing(_Dir) ->
    Gone = <<1, 16#55, (binary:copy(<<16#ab>>, 32))/binary>>,
    Events = [event(<<"channel_initiated_v1">>, #{channel_id => <<"ch-1">>, logo_mcid => Gone})],
    Report = rehash_legacy_content:migrate({ok, Events}, recorder(ok)),
    Dispatched = dispatched(),
    [?_assertMatch(#{missing := 1, rehashed := 0}, Report),
     ?_assertEqual([], Dispatched)].

unreadable_events_touch_nothing(_Dir) ->
    Logo = legacy(<<"logo bytes">>),
    Result = rehash_legacy_content:migrate({error, store_down}, recorder(ok)),
    [?_assertEqual({error, store_down}, Result),
     ?_assertEqual([hex(Logo)], legacy_files())].

%% A store that opened empty reads no events: the files are not orphans then,
%% the read was incomplete, so none is deleted.
an_unreferenced_legacy_file_is_left_alone(_Dir) ->
    Logo = legacy(<<"logo bytes">>),
    Report = rehash_legacy_content:migrate({ok, []}, recorder(ok)),
    [?_assertMatch(#{removed := 0, leftover := 1}, Report),
     ?_assertEqual([hex(Logo)], legacy_files())].

a_read_cut_off_at_the_cap_touches_nothing(_Dir) ->
    Logo = legacy(<<"logo bytes">>),
    Events = lists:duplicate(100_000, event(<<"channel_initiated_v1">>,
                                            #{channel_id => <<"ch-1">>, logo_mcid => Logo})),
    Result = rehash_legacy_content:migrate({ok, Events}, recorder(ok)),
    Dispatched = dispatched(),
    [?_assertEqual({error, {truncated_at, 100_000}}, Result),
     ?_assertEqual([], Dispatched),
     ?_assertEqual([hex(Logo)], legacy_files())].

%% Old events keep their legacy MCIDs forever; with the files gone, a later
%% boot dispatches nothing.
a_second_run_finds_nothing_to_do(_Dir) ->
    Logo = legacy(<<"logo bytes">>),
    Events = [event(<<"channel_initiated_v1">>, #{channel_id => <<"ch-1">>, logo_mcid => Logo})],
    _ = rehash_legacy_content:migrate({ok, Events}, recorder(ok)),
    _ = dispatched(),
    Report = rehash_legacy_content:migrate({ok, Events}, recorder(ok)),
    Dispatched = dispatched(),
    [?_assertMatch(#{rehashed := 0, missing := 1, removed := 0}, Report),
     ?_assertEqual([], Dispatched)].

%%--------------------------------------------------------------------

%% The recorder sends to the process that sets the test up, so dispatched/0 is
%% read there, before the returned assertions run in a process of their own.

%% A legacy file as tube stored it before: named by hex of <<1, 16#55, Hash:32>>.
%% The hash is not BLAKE3 here; the migration never checks it, it re-hashes.
legacy(Bytes) ->
    Mcid = <<1, 16#55, (crypto:hash(sha256, Bytes))/binary>>,
    Path = filename:join(tube_content_store:dir(), <<(hex(Mcid))/binary, ".bin">>),
    ok = filelib:ensure_dir(Path),
    ok = file:write_file(Path, Bytes),
    Mcid.

event(Type, Data) ->
    #{event_type => Type, data => Data}.

sha384(Bytes) -> <<2, 16#55, (crypto:hash(sha384, Bytes))/binary>>.

hex(Mcid) -> binary:encode_hex(Mcid, lowercase).

read(Mcid) -> tube_content_store:read(hex(Mcid)).

legacy_files() ->
    [list_to_binary(filename:basename(F, ".bin"))
     || F <- filelib:wildcard(filename:join(tube_content_store:dir(), "0155*.bin"))].

recorder(ok) ->
    Test = self(),
    fun(Rehash) -> Test ! {dispatched, Rehash}, {ok, 1, []} end.

dispatched() ->
    receive {dispatched, R} -> [R | dispatched()] after 0 -> [] end.
