%% @doc Event: video_clip_thumbnail_rehashed_v1 -- the clip's thumbnail is named by its
%% SHA-384 MCID from here on; `legacy_mcid' is the BLAKE3 MCID it replaces.
-module(video_clip_thumbnail_rehashed_v1).

-behaviour(evoq_event).

-export([event_type/0, new/1, from_command/1, to_map/1]).
-export([clip_id/1]).

-record(video_clip_thumbnail_rehashed_v1, {
    clip_id  :: binary(),
    legacy_mcid :: binary(),
    thumbnail_mcid   :: binary(),
    rehashed_at :: integer()
}).

-opaque t() :: #video_clip_thumbnail_rehashed_v1{}.
-export_type([t/0]).

event_type() -> <<"video_clip_thumbnail_rehashed_v1">>.

-spec new(map()) -> t().
new(#{clip_id := Id, legacy_mcid := Legacy, thumbnail_mcid := Thumbnail}) ->
    #video_clip_thumbnail_rehashed_v1{
        clip_id  = Id,
        legacy_mcid = Legacy,
        thumbnail_mcid   = Thumbnail,
        rehashed_at = erlang:system_time(millisecond)
    }.

-spec from_command(rehash_video_clip_thumbnail_v1:t()) -> t().
from_command(Cmd) ->
    new(#{
        clip_id  => rehash_video_clip_thumbnail_v1:clip_id(Cmd),
        legacy_mcid => rehash_video_clip_thumbnail_v1:legacy_mcid(Cmd),
        thumbnail_mcid   => rehash_video_clip_thumbnail_v1:thumbnail_mcid(Cmd)
    }).

-spec to_map(t()) -> map().
to_map(#video_clip_thumbnail_rehashed_v1{} = E) ->
    #{
        event_type  => event_type(),
        clip_id  => E#video_clip_thumbnail_rehashed_v1.clip_id,
        legacy_mcid => E#video_clip_thumbnail_rehashed_v1.legacy_mcid,
        thumbnail_mcid   => E#video_clip_thumbnail_rehashed_v1.thumbnail_mcid,
        rehashed_at => E#video_clip_thumbnail_rehashed_v1.rehashed_at
    }.

-spec clip_id(t()) -> binary().
clip_id(#video_clip_thumbnail_rehashed_v1{clip_id = V}) -> V.
