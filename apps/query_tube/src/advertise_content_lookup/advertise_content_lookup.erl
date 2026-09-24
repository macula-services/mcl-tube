%% @doc RPC provider: tube.lookup_content. Serves a durably-persisted
%% clip thumbnail or channel logo by its hex-encoded MCID, straight from
%% `tube_content_store' -- see that module for why this exists instead
%% of relying on `macula:get_content/2' (a one-time transfer, not a
%% store, per macula_content_transfer's own docs).
-module(advertise_content_lookup).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, undefined}.

%% `mcid' is read through mcl_om_wire:field/2, like every other lookup in this
%% app. macula's frame decoder leaves a key as sent (`{text, <<"mcid">>}') and
%% delivers a text value as `{text, Hex}'; matching `#{mcid := _}' raw refused
%% every real caller as a bad request. tube_content_store refuses anything that
%% is not a hex MCID before it builds a path from it, and that refusal is a bad
%% request too.
handle_request(Payload, State) ->
    reply_from(tube_content_store:read(mcl_om_wire:field(mcid, Payload)), State).

reply_from({ok, Bytes}, State) -> {reply, #{bytes => Bytes}, State};
reply_from({error, not_found}, State) -> {error, not_found, State};
reply_from({error, invalid_mcid}, State) -> {error, bad_request, State}.
