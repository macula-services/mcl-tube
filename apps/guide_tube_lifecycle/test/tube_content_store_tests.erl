%% @doc The content store turns an MCID into a filename, so it accepts only a
%% SHA-384 raw-block MCID in hex, on write as on read, and nothing a caller
%% could steer outside the content directory. It holds bytes only under the
%% id they hash to, and serves them only while they still do.
-module(tube_content_store_tests).

-include_lib("eunit/include/eunit.hrl").

-define(BYTES, <<"bytes">>).

store_test_() ->
    {foreach, fun setup/0, fun teardown/1,
     [fun a_sha384_mcid_round_trips/1,
      fun upper_case_is_the_same_mcid/1,
      fun nothing_is_written_outside_the_content_directory/1,
      fun a_non_hex_mcid_is_refused_on_read/1,
      fun bytes_that_do_not_hash_to_the_mcid_are_not_stored/1,
      fun a_file_whose_bytes_do_not_hash_to_its_name_is_not_served/1,
      fun a_blake3_mcid_is_refused/1]}.

setup() ->
    Dir = filename:join("/tmp", "tube_content_store_tests_" ++
                        integer_to_list(erlang:unique_integer([positive]))),
    os:putenv("MCL_DATA_DIR", Dir),
    Dir.

teardown(Dir) ->
    os:unsetenv("MCL_DATA_DIR"),
    _ = file:del_dir_r(Dir),
    ok.

a_sha384_mcid_round_trips(_Dir) ->
    ok = tube_content_store:persist(hex(?BYTES), ?BYTES),
    ?_assertEqual({ok, ?BYTES}, tube_content_store:read(hex(?BYTES))).

upper_case_is_the_same_mcid(_Dir) ->
    ok = tube_content_store:persist(string:uppercase(hex(?BYTES)), ?BYTES),
    ?_assertEqual({ok, ?BYTES}, tube_content_store:read(hex(?BYTES))).

nothing_is_written_outside_the_content_directory(Dir) ->
    ok = tube_content_store:persist(hex(?BYTES), ?BYTES),
    Refused = [tube_content_store:persist(Bad, <<"x">>)
               || Bad <- [<<"../escape">>, <<"../../escape">>, <<"a/b">>, <<"zz">>, <<>>]],
    [?_assertEqual(lists:duplicate(5, {error, invalid_mcid}), Refused),
     ?_assertEqual(false, filelib:is_regular(filename:join(Dir, "escape.bin")))].

a_non_hex_mcid_is_refused_on_read(_Dir) ->
    [?_assertEqual({error, invalid_mcid}, tube_content_store:read(Bad))
     || Bad <- [<<"../secret">>, <<"not hex!">>, {text, hex(?BYTES)}, undefined, <<"abc">>]].

%% The id is the SHA-384 of the bytes, so bytes under any other id are refused.
bytes_that_do_not_hash_to_the_mcid_are_not_stored(Dir) ->
    Refused = tube_content_store:persist(hex(<<"other bytes">>), ?BYTES),
    [?_assertEqual({error, mcid_mismatch}, Refused),
     ?_assertEqual([], files(Dir))].

%% A file changed on disk after it was stored is not served under its name.
a_file_whose_bytes_do_not_hash_to_its_name_is_not_served(Dir) ->
    ok = tube_content_store:persist(hex(?BYTES), ?BYTES),
    [File] = files(Dir),
    ok = file:write_file(File, <<"tampered">>),
    ?_assertEqual({error, not_found}, tube_content_store:read(hex(?BYTES))).

%% The legacy BLAKE3 id, <<1, 16#55, Hash:32>>, and a SHA-384 manifest id are
%% not ids this store holds.
a_blake3_mcid_is_refused(_Dir) ->
    Blake3 = binary:encode_hex(<<1, 16#55, (binary:copy(<<16#ab>>, 32))/binary>>, lowercase),
    Manifest = binary:encode_hex(<<2, 16#56, (crypto:hash(sha384, ?BYTES))/binary>>, lowercase),
    [?_assertEqual({error, invalid_mcid}, tube_content_store:persist(Blake3, ?BYTES)),
     ?_assertEqual({error, invalid_mcid}, tube_content_store:read(Blake3)),
     ?_assertEqual({error, invalid_mcid}, tube_content_store:read(Manifest))].

hex(Bytes) ->
    binary:encode_hex(<<2, 16#55, (crypto:hash(sha384, Bytes))/binary>>, lowercase).

files(Dir) ->
    filelib:wildcard(filename:join([Dir, "thumbnails", "*"])).
