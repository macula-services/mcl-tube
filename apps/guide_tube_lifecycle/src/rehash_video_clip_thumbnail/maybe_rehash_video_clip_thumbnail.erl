%% @doc Handler for rehash_video_clip_thumbnail_v1: the clip's current thumbnail must
%% still be the legacy MCID the command names (a thumbnail replaced
%% since is not rehashed over), and the new MCID must be a SHA-384 raw block
%% id. Builds the resulting event (called from the aggregate's execute/2)
%% and dispatches the command.
-module(maybe_rehash_video_clip_thumbnail).

-export([handle/2, handle_from_map/2, dispatch/1]).

-spec handle_from_map(binary() | undefined, map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(CurrentThumbnail, Payload) ->
    with_command(CurrentThumbnail, rehash_video_clip_thumbnail_v1:from_map(Payload)).

with_command(CurrentThumbnail, {ok, Cmd}) -> handle(CurrentThumbnail, Cmd);
with_command(_CurrentThumbnail, {error, _} = Error) -> Error.

-spec handle(binary() | undefined, rehash_video_clip_thumbnail_v1:t()) ->
          {ok, [map()]} | {error, term()}.
handle(CurrentThumbnail, Cmd) ->
    checked(CurrentThumbnail =:= rehash_video_clip_thumbnail_v1:legacy_mcid(Cmd),
            tube_content_store:is_mcid(rehash_video_clip_thumbnail_v1:thumbnail_mcid(Cmd)), Cmd).

checked(true, true, Cmd) ->
    {ok, [video_clip_thumbnail_rehashed_v1:to_map(video_clip_thumbnail_rehashed_v1:from_command(Cmd))]};
checked(false, _Sha384, _Cmd) ->
    {error, thumbnail_is_not_the_legacy_mcid};
checked(true, false, _Cmd) ->
    {error, thumbnail_mcid_is_not_sha384}.

-spec dispatch(map()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Params) ->
    with_command_for_dispatch(rehash_video_clip_thumbnail_v1:new(Params)).

with_command_for_dispatch({ok, Cmd}) ->
    ClipId = rehash_video_clip_thumbnail_v1:clip_id(Cmd),
    EvoqCmd = evoq_command:new(rehash_video_clip_thumbnail, video_clip_aggregate,
                               video_clip_aggregate:stream_id(ClipId),
                               rehash_video_clip_thumbnail_v1:to_map(Cmd)),
    evoq_router:dispatch(EvoqCmd);
with_command_for_dispatch({error, _} = Error) ->
    Error.
