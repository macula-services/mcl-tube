%% @doc Mints an MCID for the owner UI's logo/thumbnail uploads and
%% persists the bytes locally via `tube_content_store' -- no mesh
%% round trip. The MCID is macula's raw-block content id,
%% `<<2, 16#55, SHA-384(Bytes):48>>' (D24: SHA-384, CNSA 2.0), a pure local
%% computation -- macula:put_content/2 was never buying anything here
%% except a network dependency an upload has no reason to have: uploads
%% run over the owner's own LAN to this box, and nothing durable ever
%% depended on the mesh push (macula:put_content/2 is a one-time
%% peer-to-peer transfer, not storage, so no other party could read it
%% back regardless -- see tube_content_store.erl). Removing it means an
%% upload no longer fails, hangs, or silently loses the image if this
%% box's own path to the mesh happens to be down at that moment.
%%
%% A raw-block id names at most one block, macula's 256 KiB chunk; bigger
%% bytes are a manifest to the SDK, so they are refused here instead.
-module(tube_content_put).

-export([put/1]).

-define(TAG_SHA384, 2).
-define(CODEC_RAW, 16#55).
-define(MAX_BLOCK_BYTES, 256 * 1024).

-spec put(binary()) -> {ok, binary()} | {error, too_large | term()}.
put(Bytes) when is_binary(Bytes), byte_size(Bytes) =< ?MAX_BLOCK_BYTES ->
    Mcid = <<?TAG_SHA384, ?CODEC_RAW, (crypto:hash(sha384, Bytes))/binary>>,
    persist_result(tube_content_store:persist(binary:encode_hex(Mcid, lowercase), Bytes), Mcid);
put(Bytes) when is_binary(Bytes) ->
    {error, too_large}.

persist_result(ok, Mcid) -> {ok, Mcid};
persist_result({error, _} = Error, _Mcid) -> Error.
