%% @doc Command: rehash_video_clip_thumbnail_v1 -- the clip's thumbnail, named until now
%% by a legacy BLAKE3 MCID, is named by the SHA-384 MCID of the same bytes
%% from here on (macula-io/macula#46). Issued once, by mcl-tube's boot
%% migration (rehash_legacy_content), never by an owner.
-module(rehash_video_clip_thumbnail_v1).

-behaviour(evoq_command).

-export([command_type/0, new/1, to_map/1, from_map/1]).
-export([clip_id/1, legacy_mcid/1, thumbnail_mcid/1]).

-record(rehash_video_clip_thumbnail_v1, {
    clip_id  :: binary(),
    legacy_mcid :: binary(),
    thumbnail_mcid   :: binary()
}).

-opaque t() :: #rehash_video_clip_thumbnail_v1{}.
-export_type([t/0]).

command_type() -> rehash_video_clip_thumbnail.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{clip_id := Id, legacy_mcid := Legacy, thumbnail_mcid := Thumbnail})
  when is_binary(Id), Id =/= <<>>, is_binary(Legacy), is_binary(Thumbnail) ->
    {ok, #rehash_video_clip_thumbnail_v1{clip_id = Id, legacy_mcid = Legacy, thumbnail_mcid = Thumbnail}};
new(_) ->
    {error, clip_id_legacy_mcid_and_thumbnail_mcid_required}.

-spec to_map(t()) -> map().
to_map(#rehash_video_clip_thumbnail_v1{} = Cmd) ->
    #{
        command_type => command_type(),
        clip_id   => Cmd#rehash_video_clip_thumbnail_v1.clip_id,
        legacy_mcid  => Cmd#rehash_video_clip_thumbnail_v1.legacy_mcid,
        thumbnail_mcid    => Cmd#rehash_video_clip_thumbnail_v1.thumbnail_mcid
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{clip_id := _, legacy_mcid := _, thumbnail_mcid := _} = Map) ->
    new(Map);
from_map(_) ->
    {error, missing_required_fields}.

-spec clip_id(t()) -> binary().
clip_id(#rehash_video_clip_thumbnail_v1{clip_id = V}) -> V.
-spec legacy_mcid(t()) -> binary().
legacy_mcid(#rehash_video_clip_thumbnail_v1{legacy_mcid = V}) -> V.
-spec thumbnail_mcid(t()) -> binary().
thumbnail_mcid(#rehash_video_clip_thumbnail_v1{thumbnail_mcid = V}) -> V.
