%% @doc Command: upload_video_clip_v1 -- lands bytes on the edge node,
%% private. `source' is `<<"uploaded">>' (an owner-supplied file) or
%% `<<"recorded">>' (minted from a completed live session by a future
%% Policy -- not reachable yet, live broadcast is out of this MVP).
-module(upload_video_clip_v1).

-behaviour(evoq_command).

-export([command_type/0, new/1, to_map/1, from_map/1]).
-export([clip_id/1, channel_id/1, name/1, description/1, tags/1,
         thumbnail_mcid/1, local_ref/1, source/1]).

-record(upload_video_clip_v1, {
    clip_id        :: binary(),
    channel_id     :: binary(),
    name           :: binary(),
    description    :: binary(),
    tags           :: [binary()],
    thumbnail_mcid :: binary() | undefined,
    local_ref      :: binary(),
    source         :: binary()
}).

-opaque t() :: #upload_video_clip_v1{}.
-export_type([t/0]).

command_type() -> upload_video_clip.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{channel_id := ChannelId, name := Name, local_ref := LocalRef} = Params)
  when is_binary(ChannelId), ChannelId =/= <<>>,
       is_binary(Name), Name =/= <<>>,
       is_binary(LocalRef), LocalRef =/= <<>> ->
    {ok, #upload_video_clip_v1{
        clip_id        = reckon_gater_stream_id:new(<<"clip">>),
        channel_id     = ChannelId,
        name           = Name,
        description    = maps:get(description, Params, <<>>),
        tags           = maps:get(tags, Params, []),
        thumbnail_mcid = maps:get(thumbnail_mcid, Params, undefined),
        local_ref      = LocalRef,
        source         = maps:get(source, Params, <<"uploaded">>)
    }};
new(_) ->
    {error, channel_id_name_and_local_ref_required}.

-spec to_map(t()) -> map().
to_map(#upload_video_clip_v1{} = Cmd) ->
    #{
        command_type   => command_type(),
        clip_id        => Cmd#upload_video_clip_v1.clip_id,
        channel_id     => Cmd#upload_video_clip_v1.channel_id,
        name           => Cmd#upload_video_clip_v1.name,
        description    => Cmd#upload_video_clip_v1.description,
        tags           => Cmd#upload_video_clip_v1.tags,
        thumbnail_mcid => Cmd#upload_video_clip_v1.thumbnail_mcid,
        local_ref      => Cmd#upload_video_clip_v1.local_ref,
        source         => Cmd#upload_video_clip_v1.source
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{clip_id := Id, channel_id := ChannelId, name := Name,
          description := Description, tags := Tags,
          thumbnail_mcid := ThumbnailMcid, local_ref := LocalRef,
          source := Source}) ->
    {ok, #upload_video_clip_v1{clip_id = Id, channel_id = ChannelId,
                               name = Name, description = Description,
                               tags = Tags, thumbnail_mcid = ThumbnailMcid,
                               local_ref = LocalRef, source = Source}};
from_map(_) ->
    {error, missing_required_fields}.

-spec clip_id(t()) -> binary().
clip_id(#upload_video_clip_v1{clip_id = V}) -> V.
-spec channel_id(t()) -> binary().
channel_id(#upload_video_clip_v1{channel_id = V}) -> V.
-spec name(t()) -> binary().
name(#upload_video_clip_v1{name = V}) -> V.
-spec description(t()) -> binary().
description(#upload_video_clip_v1{description = V}) -> V.
-spec tags(t()) -> [binary()].
tags(#upload_video_clip_v1{tags = V}) -> V.
-spec thumbnail_mcid(t()) -> binary() | undefined.
thumbnail_mcid(#upload_video_clip_v1{thumbnail_mcid = V}) -> V.
-spec local_ref(t()) -> binary().
local_ref(#upload_video_clip_v1{local_ref = V}) -> V.
-spec source(t()) -> binary().
source(#upload_video_clip_v1{source = V}) -> V.
