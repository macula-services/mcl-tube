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
-module(tube_content_store).

-export([persist/2, read/1, mcid_hex/1]).

-spec persist(binary(), binary()) -> ok | {error, term()}.
persist(McidHex, Bytes) when is_binary(Bytes) ->
    persisted(mcid_hex(McidHex), Bytes).

persisted({ok, Hex}, Bytes) ->
    ok = filelib:ensure_dir(filename:join(dir(), "placeholder")),
    file:write_file(path(Hex), Bytes);
persisted({error, _} = Refused, _Bytes) ->
    Refused.

-spec read(term()) -> {ok, binary()} | {error, not_found | invalid_mcid}.
read(McidHex) ->
    read_valid(mcid_hex(McidHex)).

read_valid({ok, Hex}) -> as_not_found(file:read_file(path(Hex)));
read_valid({error, _} = Refused) -> Refused.

%% @doc ⚠ THE MCID BECOMES A FILENAME, so only hex is let through, and
%% nothing else a caller sends. A value such as `../secret' used to be joined
%% onto the content directory as-is: with the directory present, as it is on
%% any node that has stored a thumbnail, it read a file outside it. An MCID is
%% hex of its bytes, an even number of hex digits (a 50-byte MCID is 100),
%% capped at 128. Upper case is the same MCID: tube mints lower case, and a
%% caller may encode upper (Elixir's Base.encode16 does by default).
-spec mcid_hex(term()) -> {ok, binary()} | {error, invalid_mcid}.
mcid_hex(Hex) when is_binary(Hex), byte_size(Hex) >= 2, byte_size(Hex) =< 128,
                   byte_size(Hex) rem 2 =:= 0 ->
    hex_only(re:run(Hex, <<"\\A[0-9a-fA-F]+\\z">>, [{capture, none}]), Hex);
mcid_hex(_Other) ->
    {error, invalid_mcid}.

hex_only(match, Hex) -> {ok, string:lowercase(Hex)};
hex_only(nomatch, _Hex) -> {error, invalid_mcid}.

as_not_found({ok, Bytes}) -> {ok, Bytes};
as_not_found({error, _Reason}) -> {error, not_found}.

path(McidHex) -> filename:join(dir(), <<McidHex/binary, ".bin">>).

%% Same env var + default as mcl_tube_service:data_dir/0 -- this app
%% doesn't depend on the mcl_tube (top) app, so read directly rather
%% than introduce a dependency for one string.
dir() -> filename:join(os:getenv("MCL_DATA_DIR", "/tmp/mcl_tube"), "thumbnails").
