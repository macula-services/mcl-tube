%% @doc The content store turns an MCID into a filename, so it accepts only a
%% hex MCID, on write as on read, and nothing a caller could steer outside the
%% content directory.
-module(tube_content_store_tests).

-include_lib("eunit/include/eunit.hrl").

-define(MCID, binary:encode_hex(binary:copy(<<16#ab>>, 50), lowercase)).

store_test_() ->
    {foreach, fun setup/0, fun teardown/1,
     [fun a_hex_mcid_round_trips/1,
      fun upper_case_is_the_same_mcid/1,
      fun nothing_is_written_outside_the_content_directory/1,
      fun a_non_hex_mcid_is_refused_on_read/1]}.

setup() ->
    Dir = filename:join("/tmp", "tube_content_store_tests_" ++
                        integer_to_list(erlang:unique_integer([positive]))),
    os:putenv("MCL_DATA_DIR", Dir),
    Dir.

teardown(Dir) ->
    os:unsetenv("MCL_DATA_DIR"),
    _ = file:del_dir_r(Dir),
    ok.

a_hex_mcid_round_trips(_Dir) ->
    ok = tube_content_store:persist(?MCID, <<"bytes">>),
    ?_assertEqual({ok, <<"bytes">>}, tube_content_store:read(?MCID)).

upper_case_is_the_same_mcid(_Dir) ->
    ok = tube_content_store:persist(string:uppercase(?MCID), <<"bytes">>),
    ?_assertEqual({ok, <<"bytes">>}, tube_content_store:read(?MCID)).

nothing_is_written_outside_the_content_directory(Dir) ->
    ok = tube_content_store:persist(?MCID, <<"make the directory exist">>),
    Refused = [tube_content_store:persist(Bad, <<"x">>)
               || Bad <- [<<"../escape">>, <<"../../escape">>, <<"a/b">>, <<"zz">>, <<>>]],
    [?_assertEqual(lists:duplicate(5, {error, invalid_mcid}), Refused),
     ?_assertEqual(false, filelib:is_regular(filename:join(Dir, "escape.bin")))].

a_non_hex_mcid_is_refused_on_read(_Dir) ->
    [?_assertEqual({error, invalid_mcid}, tube_content_store:read(Bad))
     || Bad <- [<<"../secret">>, <<"not hex!">>, {text, ?MCID}, undefined, <<"abc">>]].
