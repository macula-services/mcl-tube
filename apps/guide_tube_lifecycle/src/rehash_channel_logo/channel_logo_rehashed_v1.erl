%% @doc Event: channel_logo_rehashed_v1 -- the channel's logo is named by its
%% SHA-384 MCID from here on; `legacy_mcid' is the BLAKE3 MCID it replaces.
-module(channel_logo_rehashed_v1).

-behaviour(evoq_event).

-export([event_type/0, new/1, from_command/1, to_map/1]).
-export([channel_id/1]).

-record(channel_logo_rehashed_v1, {
    channel_id  :: binary(),
    legacy_mcid :: binary(),
    logo_mcid   :: binary(),
    rehashed_at :: integer()
}).

-opaque t() :: #channel_logo_rehashed_v1{}.
-export_type([t/0]).

event_type() -> <<"channel_logo_rehashed_v1">>.

-spec new(map()) -> t().
new(#{channel_id := Id, legacy_mcid := Legacy, logo_mcid := Logo}) ->
    #channel_logo_rehashed_v1{
        channel_id  = Id,
        legacy_mcid = Legacy,
        logo_mcid   = Logo,
        rehashed_at = erlang:system_time(millisecond)
    }.

-spec from_command(rehash_channel_logo_v1:t()) -> t().
from_command(Cmd) ->
    new(#{
        channel_id  => rehash_channel_logo_v1:channel_id(Cmd),
        legacy_mcid => rehash_channel_logo_v1:legacy_mcid(Cmd),
        logo_mcid   => rehash_channel_logo_v1:logo_mcid(Cmd)
    }).

-spec to_map(t()) -> map().
to_map(#channel_logo_rehashed_v1{} = E) ->
    #{
        event_type  => event_type(),
        channel_id  => E#channel_logo_rehashed_v1.channel_id,
        legacy_mcid => E#channel_logo_rehashed_v1.legacy_mcid,
        logo_mcid   => E#channel_logo_rehashed_v1.logo_mcid,
        rehashed_at => E#channel_logo_rehashed_v1.rehashed_at
    }.

-spec channel_id(t()) -> binary().
channel_id(#channel_logo_rehashed_v1{channel_id = V}) -> V.
