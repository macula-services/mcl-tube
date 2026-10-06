%% @doc The rehash desks (macula-io/macula#46): a channel's logo and a clip's
%% thumbnail move from a legacy BLAKE3 MCID to the SHA-384 MCID of the same
%% bytes, only while the legacy one is still current, and the aggregate state
%% and the read model carry the new MCID afterwards.
-module(rehash_content_tests).

-include_lib("eunit/include/eunit.hrl").

-define(LEGACY, <<1, 16#55, (binary:copy(<<16#ab>>, 32))/binary>>).
-define(OTHER_LEGACY, <<1, 16#55, (binary:copy(<<16#cd>>, 32))/binary>>).
-define(SHA384, <<2, 16#55, (crypto:hash(sha384, <<"logo bytes">>))/binary>>).

%%% channel logo

a_channel_logo_moves_to_its_sha384_mcid_test() ->
    Channel = initiated_channel(?LEGACY),
    {ok, [Event]} = channel_aggregate:execute(Channel, logo_rehash(Channel, ?LEGACY, ?SHA384)),
    ?assertEqual(<<"channel_logo_rehashed_v1">>, maps:get(event_type, Event)),
    ?assertEqual(?LEGACY, maps:get(legacy_mcid, Event)),
    Rehashed = channel_aggregate:apply(Channel, Event),
    ?assertEqual(?SHA384, channel_state:logo_mcid(Rehashed)),
    ?assertEqual(<<"Rafael">>, channel_state:name(Rehashed)).

a_logo_the_channel_no_longer_names_is_not_rehashed_test() ->
    Channel = initiated_channel(?OTHER_LEGACY),
    ?assertEqual({error, logo_is_not_the_legacy_mcid},
                 channel_aggregate:execute(Channel, logo_rehash(Channel, ?LEGACY, ?SHA384))).

a_logo_is_rehashed_only_to_a_sha384_mcid_test() ->
    Channel = initiated_channel(?LEGACY),
    ?assertEqual({error, logo_mcid_is_not_sha384},
                 channel_aggregate:execute(Channel, logo_rehash(Channel, ?LEGACY, ?OTHER_LEGACY))).

a_channel_without_a_logo_is_not_rehashed_test() ->
    {ok, Fresh} = channel_aggregate:init(reckon_gater_stream_id:new(<<"channel">>)),
    ?assertEqual({error, logo_is_not_the_legacy_mcid},
                 channel_aggregate:execute(Fresh, logo_rehash(Fresh, ?LEGACY, ?SHA384))).

the_channel_row_carries_the_new_logo_test() ->
    ensure_started(project_tube_store:start_link()),
    ChannelId = reckon_gater_stream_id:new(<<"channel">>),
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{name => test_rehash_channels}),
    Initiated = #{event_type => <<"channel_initiated_v1">>,
                  data => #{channel_id => ChannelId, name => <<"Rafael">>,
                            description => <<>>, owner => <<"acme">>, tags => [],
                            logo_mcid => ?LEGACY}},
    {ok, _, RM2} = channel_lifecycle_to_channels:project(Initiated, #{}, #{}, RM),
    Rehashed = #{event_type => <<"channel_logo_rehashed_v1">>,
                 data => #{<<"channel_id">> => ChannelId, <<"legacy_mcid">> => ?LEGACY,
                           <<"logo_mcid">> => ?SHA384}},
    {ok, _, _} = channel_lifecycle_to_channels:project(Rehashed, #{}, #{}, RM2),
    {ok, Row} = project_tube_store:get_channel(ChannelId),
    ?assertEqual(?SHA384, maps:get(logo_mcid, Row)),
    ?assertEqual(<<"acme">>, maps:get(owner, Row)),
    ?assertEqual(?SHA384, maps:get(logo_mcid, channel_announcement:fact(Row, ChannelId, <<"heartbeat">>))).

%%% clip thumbnail

a_clip_thumbnail_moves_to_its_sha384_mcid_test() ->
    Clip = uploaded_clip(?LEGACY),
    {ok, [Event]} = video_clip_aggregate:execute(Clip, thumbnail_rehash(Clip, ?LEGACY, ?SHA384)),
    ?assertEqual(<<"video_clip_thumbnail_rehashed_v1">>, maps:get(event_type, Event)),
    Rehashed = video_clip_aggregate:apply(Clip, Event),
    ?assertEqual(?SHA384, video_clip_state:thumbnail_mcid(Rehashed)),
    ?assertEqual(video_clip_state:status(Clip), video_clip_state:status(Rehashed)).

a_thumbnail_the_clip_no_longer_names_is_not_rehashed_test() ->
    Clip = uploaded_clip(?OTHER_LEGACY),
    ?assertEqual({error, thumbnail_is_not_the_legacy_mcid},
                 video_clip_aggregate:execute(Clip, thumbnail_rehash(Clip, ?LEGACY, ?SHA384))).

the_clip_row_carries_the_new_thumbnail_test() ->
    ensure_started(project_tube_store:start_link()),
    ClipId = reckon_gater_stream_id:new(<<"clip">>),
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{name => test_rehash_clips}),
    Uploaded = #{event_type => <<"video_clip_uploaded_v1">>,
                 data => #{clip_id => ClipId, channel_id => <<"channel-1">>,
                           name => <<"My Clip">>, description => <<>>, tags => [],
                           thumbnail_mcid => ?LEGACY, local_ref => <<"/data/c.mp4">>,
                           source => <<"uploaded">>}},
    {ok, _, RM2} = video_clip_lifecycle_to_video_clips:project(Uploaded, #{}, #{}, RM),
    Rehashed = #{event_type => <<"video_clip_thumbnail_rehashed_v1">>,
                 data => #{clip_id => ClipId, legacy_mcid => ?LEGACY,
                           thumbnail_mcid => ?SHA384}},
    {ok, _, _} = video_clip_lifecycle_to_video_clips:project(Rehashed, #{}, #{}, RM2),
    {ok, Row} = project_tube_store:get_clip(ClipId),
    ?assertEqual(?SHA384, maps:get(thumbnail_mcid, Row)),
    ?assertEqual(<<"My Clip">>, maps:get(name, Row)).

%%--------------------------------------------------------------------

initiated_channel(Logo) ->
    ChannelId = reckon_gater_stream_id:new(<<"channel">>),
    {ok, Fresh} = channel_aggregate:init(ChannelId),
    {ok, [Event]} = channel_aggregate:execute(Fresh,
        #{command_type => initiate_channel, channel_id => ChannelId, name => <<"Rafael">>,
          description => <<>>, owner => <<"acme">>, tags => [], logo_mcid => Logo}),
    channel_aggregate:apply(Fresh, Event).

logo_rehash(Channel, Legacy, Mcid) ->
    #{command_type => rehash_channel_logo, channel_id => channel_state:channel_id(Channel),
      legacy_mcid => Legacy, logo_mcid => Mcid}.

uploaded_clip(Thumbnail) ->
    ClipId = reckon_gater_stream_id:new(<<"clip">>),
    {ok, Fresh} = video_clip_aggregate:init(ClipId),
    Uploaded = #{event_type => <<"video_clip_uploaded_v1">>, clip_id => ClipId,
                 channel_id => <<"channel-1">>, name => <<"My Clip">>, description => <<>>,
                 tags => [], thumbnail_mcid => Thumbnail, local_ref => <<"/data/c.mp4">>,
                 source => <<"uploaded">>},
    video_clip_aggregate:apply(Fresh, Uploaded).

thumbnail_rehash(Clip, Legacy, Mcid) ->
    #{command_type => rehash_video_clip_thumbnail, clip_id => video_clip_state:clip_id(Clip),
      legacy_mcid => Legacy, thumbnail_mcid => Mcid}.

ensure_started({ok, _Pid}) -> ok;
ensure_started({error, {already_started, _Pid}}) -> ok.
