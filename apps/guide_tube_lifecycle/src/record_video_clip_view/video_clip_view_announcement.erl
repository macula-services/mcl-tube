%% @doc Announces one recorded view as `video_clip_viewed_v1', on its own
%% catalog topic so a view, far more frequent than a channel change, never
%% floods the channel announcements.
%%
%% Called live, only for a view the aggregate actually recorded
%% (maybe_record_video_clip_view:dispatch/1). A consumer counts views by
%% fact, so the announcement must happen exactly once per view: an evoq
%% event handler cannot promise that, because evoq replays the whole store
%% to every handler on each boot.
-module(video_clip_view_announcement).

-export([announce/1, fact/1]).

-spec announce(map()) -> ok.
announce(Event) ->
    publish_via(mcl_om:mesh_handles(), fact(Event)).

%% @doc The fact for one recorded video_clip_viewed_v1 event.
-spec fact(map()) -> map().
fact(Event) ->
    #{clip_id    => maps:get(clip_id, Event, undefined),
      channel_id => maps:get(channel_id, Event, undefined),
      viewed_at  => maps:get(viewed_at, Event, undefined)}.

publish_via({ok, Pool, Realm}, Fact) ->
    {ok, _Pid} = macula_publisher:start_link(tube_mesh_publisher, Pool, Realm,
                                             tube_catalog_topic:topic(video_clip_viewed),
                                             Fact, []),
    ok;
publish_via({error, _}, _Fact) ->
    ok.
