%% @doc Durable local content-address cache for mcl-tube's own clip
%% thumbnails / channel logos, keyed by the hex-encoded MCID
%% `tube_content_put' already mints.
%%
%% Exists because `macula:put_content/2' (which `tube_content_put' drives
%% via `macula_feeder') is a one-time peer-to-peer transfer, not storage:
%% "pick a link, open a dedicated content stream, run the transfer, close
%% the stream" (macula_content_transfer's own module doc). Nothing else
%% answers a LATER, unrelated caller's request for the same bytes.
%% Confirmed live 2026-08-28: a direct dial to the exact station that
%% received the original put still returned `not_found'. `tube.lookup_content'
%% (advertise_content_lookup) serves from this local copy instead.
%%
%% ⚠ AN MCID IS THE SHA-384 OF ITS BYTES (macula D24, CNSA 2.0). Only a raw
%% block id, `<<2, 16#55, SHA-384(Bytes):48>>', is accepted, and bytes are
%% stored and served only under the id they hash to: `persist/2' refuses
%% bytes that do not, and `read/1' answers `not_found' for a file that no
%% longer does. A legacy BLAKE3 id (`<<1, 16#55, Hash:32>>') is not an id
%% here (macula-io/macula#46).
-module(tube_content_store).

-export([persist/2, read/1, mcid_hex/1, is_mcid/1, dir/0]).

-define(TAG_SHA384, 2).
-define(CODEC_RAW, 16#55).

-spec persist(binary(), binary()) -> ok | {error, invalid_mcid | mcid_mismatch | term()}.
persist(McidHex, Bytes) when is_binary(Bytes) ->
    persisted(mcid_hex(McidHex), Bytes).

persisted({ok, Hex}, Bytes) ->
    write_matching(names(Hex, Bytes), Hex, Bytes);
persisted({error, _} = Refused, _Bytes) ->
    Refused.

write_matching(true, Hex, Bytes) ->
    ok = filelib:ensure_dir(filename:join(dir(), "placeholder")),
    file:write_file(path(Hex), Bytes);
write_matching(false, _Hex, _Bytes) ->
    {error, mcid_mismatch}.

-spec read(term()) -> {ok, binary()} | {error, not_found | invalid_mcid}.
read(McidHex) ->
    read_valid(mcid_hex(McidHex)).

read_valid({ok, Hex}) -> matching(file:read_file(path(Hex)), Hex);
read_valid({error, _} = Refused) -> Refused.

matching({ok, Bytes}, Hex) -> served(names(Hex, Bytes), Hex, Bytes);
matching({error, _Reason}, _Hex) -> {error, not_found}.

served(true, _Hex, Bytes) ->
    {ok, Bytes};
served(false, Hex, _Bytes) ->
    logger:error("[tube_content_store] ~s.bin does not hash to its name; not served",
                 [Hex]),
    {error, not_found}.

%% @doc True for an MCID this store holds content under: a SHA-384 raw block id.
-spec is_mcid(term()) -> boolean().
is_mcid(<<?TAG_SHA384, ?CODEC_RAW, _Hash:48/binary>>) -> true;
is_mcid(_Other) -> false.

%% True when `Hex' is the MCID of `Bytes'.
names(Hex, Bytes) ->
    binary:decode_hex(Hex) =:= <<?TAG_SHA384, ?CODEC_RAW, (crypto:hash(sha384, Bytes))/binary>>.

%% @doc ⚠ THE MCID BECOMES A FILENAME, so only the hex of a SHA-384 raw block
%% MCID is let through, and nothing else a caller sends: 100 hex digits
%% starting `0255'. A value such as `../secret' used to be joined onto the
%% content directory as-is: with the directory present, as it is on any node
%% that has stored a thumbnail, it read a file outside it. Upper case is the
%% same MCID: tube mints lower case, and a caller may encode upper (Elixir's
%% Base.encode16 does by default).
-spec mcid_hex(term()) -> {ok, binary()} | {error, invalid_mcid}.
mcid_hex(Hex) when is_binary(Hex), byte_size(Hex) =:= 100 ->
    hex_only(re:run(Hex, <<"\\A0255[0-9a-fA-F]{96}\\z">>, [{capture, none}]), Hex);
mcid_hex(_Other) ->
    {error, invalid_mcid}.

hex_only(match, Hex) -> {ok, string:lowercase(Hex)};
hex_only(nomatch, _Hex) -> {error, invalid_mcid}.

path(McidHex) -> filename:join(dir(), <<McidHex/binary, ".bin">>).

%% @doc The content directory. Same env var + default as
%% mcl_tube_service:data_dir/0 -- this app doesn't depend on the mcl_tube
%% (top) app, so read directly rather than introduce a dependency for one
%% string.
-spec dir() -> file:filename().
dir() -> filename:join(os:getenv("MCL_DATA_DIR", "/tmp/mcl_tube"), "thumbnails").
