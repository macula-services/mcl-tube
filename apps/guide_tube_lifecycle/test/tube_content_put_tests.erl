-module(tube_content_put_tests).

-include_lib("eunit/include/eunit.hrl").

setup() ->
    Dir = filename:join("/tmp", "tube_content_put_tests_" ++
                         integer_to_list(erlang:unique_integer([positive]))),
    os:putenv("MCL_DATA_DIR", Dir),
    Dir.

teardown(Dir) ->
    os:unsetenv("MCL_DATA_DIR"),
    _ = file:del_dir_r(Dir),
    ok.

%% For any bytes up to one block, the MCID is <<2, 16#55, SHA-384(Bytes)>>
%% (macula's raw-block content id, D24) and the bytes read back under it.
put_mints_the_sha384_raw_block_mcid_and_persists_locally_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Dir) ->
        fun() ->
            [begin
                 {ok, Mcid} = tube_content_put:put(Bytes),
                 ?assertEqual(<<2, 16#55, (crypto:hash(sha384, Bytes))/binary>>, Mcid),
                 ?assertEqual({ok, Bytes},
                              tube_content_store:read(binary:encode_hex(Mcid, lowercase)))
             end || Bytes <- [<<"jpeg bytes">>, <<0>>,
                              crypto:strong_rand_bytes(4_096),
                              crypto:strong_rand_bytes(256 * 1024)]]
        end
     end}.

%% Content-addressed: the same bytes always mint the same MCID.
put_is_deterministic_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Dir) ->
        fun() ->
            {ok, Mcid1} = tube_content_put:put(<<"same bytes">>),
            {ok, Mcid2} = tube_content_put:put(<<"same bytes">>),
            ?assertEqual(Mcid1, Mcid2)
        end
     end}.

%% A raw-block id names at most one block (256 KiB): bigger bytes would be a
%% manifest to the SDK, so they are refused rather than named as a block.
put_refuses_more_than_one_block_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Dir) ->
        fun() ->
            ?assertEqual({error, too_large},
                         tube_content_put:put(binary:copy(<<0>>, 256 * 1024 + 1)))
        end
     end}.
