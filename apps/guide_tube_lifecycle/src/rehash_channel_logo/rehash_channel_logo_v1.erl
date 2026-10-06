%% @doc Command: rehash_channel_logo_v1 -- the channel's logo, named until now
%% by a legacy BLAKE3 MCID, is named by the SHA-384 MCID of the same bytes
%% from here on (macula-io/macula#46). Issued once, by mcl-tube's boot
%% migration (rehash_legacy_content), never by an owner.
-module(rehash_channel_logo_v1).

-behaviour(evoq_command).

-export([command_type/0, new/1, to_map/1, from_map/1]).
-export([channel_id/1, legacy_mcid/1, logo_mcid/1]).

-record(rehash_channel_logo_v1, {
    channel_id  :: binary(),
    legacy_mcid :: binary(),
    logo_mcid   :: binary()
}).

-opaque t() :: #rehash_channel_logo_v1{}.
-export_type([t/0]).

command_type() -> rehash_channel_logo.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{channel_id := Id, legacy_mcid := Legacy, logo_mcid := Logo})
  when is_binary(Id), Id =/= <<>>, is_binary(Legacy), is_binary(Logo) ->
    {ok, #rehash_channel_logo_v1{channel_id = Id, legacy_mcid = Legacy, logo_mcid = Logo}};
new(_) ->
    {error, channel_id_legacy_mcid_and_logo_mcid_required}.

-spec to_map(t()) -> map().
to_map(#rehash_channel_logo_v1{} = Cmd) ->
    #{
        command_type => command_type(),
        channel_id   => Cmd#rehash_channel_logo_v1.channel_id,
        legacy_mcid  => Cmd#rehash_channel_logo_v1.legacy_mcid,
        logo_mcid    => Cmd#rehash_channel_logo_v1.logo_mcid
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{channel_id := _, legacy_mcid := _, logo_mcid := _} = Map) ->
    new(Map);
from_map(_) ->
    {error, missing_required_fields}.

-spec channel_id(t()) -> binary().
channel_id(#rehash_channel_logo_v1{channel_id = V}) -> V.
-spec legacy_mcid(t()) -> binary().
legacy_mcid(#rehash_channel_logo_v1{legacy_mcid = V}) -> V.
-spec logo_mcid(t()) -> binary().
logo_mcid(#rehash_channel_logo_v1{logo_mcid = V}) -> V.
