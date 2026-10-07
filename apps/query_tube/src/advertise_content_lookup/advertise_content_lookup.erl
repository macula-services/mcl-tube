%% @doc RPC provider: tube.lookup_content. Serves a durably-persisted
%% clip thumbnail or channel logo by its hex-encoded MCID, straight from
%% `tube_content_store' -- see that module for why this exists instead
%% of relying on `macula:get_content/2' (a one-time transfer, not a
%% store, per macula_content_transfer's own docs).
%%
%% ⚠ ONLY CONTENT SOMETHING PUBLIC NAMES IS SERVED (#9, #17): the thumbnail
%% of a clip that is published now, or a channel's logo. A retracted,
%% archived or never-published clip's thumbnail is `not_found', as the clip
%% itself is to lookup_video_clip, although its bytes stay on the owner's
%% disk. Every catalog subscriber was handed the MCID while the clip was
%% published, so knowing it must not be enough.
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
    reply_from(public_content(tube_content_store:mcid_hex(mcl_om_wire:field(mcid, Payload))), State).

%% The store's own check comes first, so a malformed MCID stays a bad request.
public_content({ok, Hex}) ->
    read_named(lists:member(binary:decode_hex(Hex), public_mcids()), Hex);
public_content({error, _} = Refused) ->
    Refused.

read_named(true, Hex) -> tube_content_store:read(Hex);
read_named(false, _Hex) -> {error, not_found}.

%% Every channel's logo and every published clip's thumbnail.
public_mcids() ->
    [maps:get(logo_mcid, Channel, undefined) || Channel <- project_tube_store:list_channels()] ++
        [maps:get(thumbnail_mcid, Clip, undefined)
         || #{status := <<"published">>} = Clip <- project_tube_store:list_clips()].

reply_from({ok, Bytes}, State) -> {reply, #{bytes => Bytes}, State};
reply_from({error, not_found}, State) -> {error, not_found, State};
reply_from({error, invalid_mcid}, State) -> {error, bad_request, State}.
