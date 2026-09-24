-module(advertise_content_lookup_tests).

-include_lib("eunit/include/eunit.hrl").

%% A 50-byte MCID as tube mints it: lowercase hex.
-define(MCID, binary:encode_hex(binary:copy(<<16#ab>>, 50), lowercase)).

setup() ->
    Dir = filename:join("/tmp", "advertise_content_lookup_tests_" ++
                         integer_to_list(erlang:unique_integer([positive]))),
    os:putenv("MCL_DATA_DIR", Dir),
    Dir.

teardown(Dir) ->
    os:unsetenv("MCL_DATA_DIR"),
    _ = file:del_dir_r(Dir),
    ok.

content_found_returns_bytes_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Dir) ->
        fun() ->
            ok = tube_content_store:persist(?MCID, <<"jpeg bytes">>),
            Result = advertise_content_lookup:handle_request(
                       #{mcid => ?MCID}, undefined),
            ?assertEqual({reply, #{bytes => <<"jpeg bytes">>}, undefined}, Result)
        end
     end}.

%% The actual case this exists for: `macula:put_content/2' is a
%% one-time transfer, not storage -- a caller asking for content that
%% was never persisted locally (or predates this fix entirely) must
%% get a clean not_found, not a crash.
content_missing_returns_not_found_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Dir) ->
        fun() ->
            Result = advertise_content_lookup:handle_request(
                       #{mcid => binary:encode_hex(binary:copy(<<16#cd>>, 50), lowercase)}, undefined),
            ?assertEqual({error, not_found, undefined}, Result)
        end
     end}.

%% A key the frame decoder left as sent (binary, or `{text, _}') is still the
%% `mcid': mcl_om_wire:field/2 reads every form.
binary_keyed_args_are_looked_up_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Dir) ->
        fun() ->
            ok = tube_content_store:persist(?MCID, <<"jpeg bytes">>),
            ?assertEqual({reply, #{bytes => <<"jpeg bytes">>}, undefined},
                         advertise_content_lookup:handle_request(
                           #{<<"mcid">> => {text, ?MCID}}, undefined))
        end
     end}.

%% THE REAL PATH. A caller's `mcid' is CBOR text, and macula 12's decoder
%% delivers it as `{text, Hex}', never a bare binary. Matched raw, it never
%% found anything (macula-portal asks for thumbnails and logos exactly so).
%% Sent here through macula_frame call, encode, decode and verify_request.
through_the_codec_a_text_mcid_finds_the_content_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Dir) ->
        fun() ->
            ok = tube_content_store:persist(?MCID, <<"logo bytes">>),
            Delivered = through_the_codec(#{mcid => {text, ?MCID}}),
            ?assertEqual({reply, #{bytes => <<"logo bytes">>}, undefined},
                         advertise_content_lookup:handle_request(Delivered, undefined))
        end
     end}.

%% Elixir's Base.encode16 writes upper case by default; it is the same MCID.
an_upper_case_mcid_is_the_same_content_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(_Dir) ->
        fun() ->
            ok = tube_content_store:persist(?MCID, <<"jpeg bytes">>),
            Upper = string:uppercase(?MCID),
            ?assertEqual({reply, #{bytes => <<"jpeg bytes">>}, undefined},
                         advertise_content_lookup:handle_request(
                           through_the_codec(#{mcid => {text, Upper}}), undefined))
        end
     end}.

%% ⚠ THE MCID BECOMES A FILENAME in tube_content_store. Anything but hex is
%% refused before a path is built, so no caller can reach a file outside the
%% content directory.
a_path_or_non_hex_mcid_is_a_bad_request_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(Dir) ->
        Outside = filename:join(Dir, "secret.bin"),
        ok = filelib:ensure_dir(Outside),
        ok = file:write_file(Outside, <<"must not be served">>),
        [?_assertEqual({error, bad_request, undefined},
                       advertise_content_lookup:handle_request(
                         through_the_codec(#{mcid => {text, Bad}}), undefined))
         || Bad <- [<<"../secret">>, <<"../../etc/passwd">>, <<"dead/beef">>,
                    <<"not hex">>, <<"abc">>, <<>>, binary:copy(<<"ab">>, 65)]]
     end}.

%% The same refusal for a bare binary, the form an in-VM caller or a byte
%% string delivers. Before the fix this read `<content dir>/../secret.bin'.
a_path_mcid_cannot_reach_outside_the_content_directory_test_() ->
    {setup, fun setup/0, fun teardown/1,
     fun(Dir) ->
        %% The content directory exists, as it does on any node that has
        %% stored a thumbnail, so `thumbnails/../secret.bin' resolves.
        ok = tube_content_store:persist(?MCID, <<"jpeg bytes">>),
        Outside = filename:join(Dir, "secret.bin"),
        ok = file:write_file(Outside, <<"must not be served">>),
        ?_assertEqual({error, bad_request, undefined},
                      advertise_content_lookup:handle_request(#{mcid => <<"../secret">>}, undefined))
     end}.

missing_mcid_is_a_bad_request_test() ->
    ?assertEqual({error, bad_request, undefined},
                 advertise_content_lookup:handle_request(#{}, undefined)).

through_the_codec(Payload) ->
    {ok, Key} = macula_node_keys:generate(identity, pq_hybrid, #{puzzle_difficulty => 0}),
    Spec = #{request_id => crypto:strong_rand_bytes(16),
             realm => crypto:hash(sha256, <<"io.macula">>),
             procedure => <<"mcl-tube/lookup_content">>,
             target => macula_node_keys:key_id(Key),
             deadline => erlang:system_time(millisecond) + 60_000,
             payload => Payload},
    {ok, Decoded, <<>>} = macula_frame:decode(macula_frame:encode(macula_frame:call(Spec, Key))),
    {ok, #{payload := Delivered}} = macula_frame:verify_request(Decoded, pq_hybrid),
    Delivered.
