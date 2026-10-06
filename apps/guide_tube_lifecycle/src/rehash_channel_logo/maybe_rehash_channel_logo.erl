%% @doc Handler for rehash_channel_logo_v1: the channel's current logo must
%% still be the legacy MCID the command names (a logo the owner replaced
%% since is not rehashed over), and the new MCID must be a SHA-384 raw block
%% id. Builds the resulting event (called from the aggregate's execute/2)
%% and dispatches the command.
-module(maybe_rehash_channel_logo).

-export([handle/2, handle_from_map/2, dispatch/1]).

-spec handle_from_map(binary() | undefined, map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(CurrentLogo, Payload) ->
    with_command(CurrentLogo, rehash_channel_logo_v1:from_map(Payload)).

with_command(CurrentLogo, {ok, Cmd}) -> handle(CurrentLogo, Cmd);
with_command(_CurrentLogo, {error, _} = Error) -> Error.

-spec handle(binary() | undefined, rehash_channel_logo_v1:t()) ->
          {ok, [map()]} | {error, term()}.
handle(CurrentLogo, Cmd) ->
    checked(CurrentLogo =:= rehash_channel_logo_v1:legacy_mcid(Cmd),
            tube_content_store:is_mcid(rehash_channel_logo_v1:logo_mcid(Cmd)), Cmd).

checked(true, true, Cmd) ->
    {ok, [channel_logo_rehashed_v1:to_map(channel_logo_rehashed_v1:from_command(Cmd))]};
checked(false, _Sha384, _Cmd) ->
    {error, logo_is_not_the_legacy_mcid};
checked(true, false, _Cmd) ->
    {error, logo_mcid_is_not_sha384}.

-spec dispatch(map()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Params) ->
    with_command_for_dispatch(rehash_channel_logo_v1:new(Params)).

with_command_for_dispatch({ok, Cmd}) ->
    ChannelId = rehash_channel_logo_v1:channel_id(Cmd),
    EvoqCmd = evoq_command:new(rehash_channel_logo, channel_aggregate,
                               channel_aggregate:stream_id(ChannelId),
                               rehash_channel_logo_v1:to_map(Cmd)),
    evoq_router:dispatch(EvoqCmd);
with_command_for_dispatch({error, _} = Error) ->
    Error.
