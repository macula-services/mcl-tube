%% @doc One-shot boot migration to SHA-384 content ids (macula-io/macula#46,
%% security register R10): every channel logo and clip thumbnail still named by
%% a legacy BLAKE3 MCID, `<<1, 16#55, Hash:32>>', is re-hashed ONCE. Its bytes
%% go under their SHA-384 MCID in tube_content_store, the channel or clip is
%% told its new MCID (rehash_channel_logo / rehash_video_clip_thumbnail), and
%% the legacy file goes. No dual scheme: nothing reads or serves a legacy id.
%%
%% The references come from the event store, not the read model: the in-memory
%% read model replays at boot with no signal that it is done, and a reference
%% it had not replayed yet would read as an orphan file. The aggregate refuses
%% a rehash whose legacy MCID it no longer names, so every legacy MCID ever
%% recorded is offered and only the current ones take.
%%
%% ⚠ ONLY FILES A REFERENCE NAMED ARE DELETED, and only once every rehash that
%% needs the file took or was refused as stale; one that failed keeps its file
%% for the next boot. An unreferenced legacy file means the read was
%% incomplete (a store that opened empty, or a read cut off at ?MAX_EVENTS),
%% so it is left alone and counted as `leftover'. A read that returns
%% ?MAX_EVENTS events counts as unreadable, and nothing is touched then.
%%
%% ⚠ DELETE THIS MODULE in the release after the one that ships it, once the
%% fleet shows no legacy file left (macula-io/macula#46). Kept, it is a code
%% path that still knows the BLAKE3 shape.
-module(rehash_legacy_content).

-export([start_link/0, run/0, migrate/2]).

-define(TYPES, [<<"channel_initiated_v1">>, <<"channel_reconfigured_v1">>,
                <<"video_clip_uploaded_v1">>, <<"video_clip_scanned_v1">>]).
-define(MAX_EVENTS, 100_000).

-type rehash() :: {logo | thumbnail, binary(), binary(), binary()}.
-type outcome() :: rehashed | stale | missing | {failed, term()}.
-type report() :: #{rehashed | stale | missing | failed | removed | leftover =>
                        non_neg_integer()}.

%% @doc Runs the migration once, in a process of its own, and ends.
-spec start_link() -> {ok, pid()}.
start_link() ->
    {ok, proc_lib:spawn_link(fun() -> reported(run()) end)}.

%% @doc The migration against this service's store, dispatching through evoq.
-spec run() -> report() | {error, term()}.
run() ->
    migrate(read_events(), fun dispatch/1).

%% @doc The migration over `Events', telling each channel or clip its new MCID
%% through `Dispatch'.
-spec migrate({ok, [map()]} | {error, term()}, fun((rehash()) -> term())) ->
          report() | {error, term()}.
migrate({ok, Events}, _Dispatch) when length(Events) >= ?MAX_EVENTS ->
    {error, {truncated_at, ?MAX_EVENTS}};
migrate({ok, Events}, Dispatch) ->
    Outcomes = [{Legacy, rehash(Ref, Dispatch)} || {_, _, Legacy} = Ref <- references(Events)],
    Removed = remove_legacy_files(Outcomes),
    (counted([Outcome || {_, Outcome} <- Outcomes]))#{
        removed => Removed, leftover => length(legacy_files())};
migrate({error, _} = Error, _Dispatch) ->
    Error.

read_events() ->
    evoq_event_store:read_events_by_types(
      maps:get(id, mcl_tube_service:event_store()), ?TYPES, ?MAX_EVENTS).

%% Every (channel, logo) and (clip, thumbnail) pair any event recorded with a
%% legacy MCID.
references(Events) ->
    lists:usort(lists:flatmap(fun reference/1, Events)).

%% evoq_event_store hands an event back with its fields at the top level, beside
%% the envelope; a routed event nests them under `data'. Both are read.
reference(#{event_type := Type, data := Data}) when is_map(Data) ->
    referenced(Type, Data);
reference(#{event_type := Type} = Event) ->
    referenced(Type, Event);
reference(_Other) ->
    [].

referenced(Type, Data) when Type =:= <<"channel_initiated_v1">>;
                            Type =:= <<"channel_reconfigured_v1">> ->
    legacy_ref(logo, field(channel_id, Data), field(logo_mcid, Data));
referenced(_ClipEvent, Data) ->
    legacy_ref(thumbnail, field(clip_id, Data), field(thumbnail_mcid, Data)).

legacy_ref(Kind, Id, <<1, 16#55, _Hash:32/binary>> = Legacy) when is_binary(Id) ->
    [{Kind, Id, Legacy}];
legacy_ref(_Kind, _Id, _NotLegacy) ->
    [].

-spec rehash({logo | thumbnail, binary(), binary()}, fun((rehash()) -> term())) -> outcome().
rehash({Kind, Id, Legacy}, Dispatch) ->
    with_bytes(file:read_file(legacy_path(Legacy)), Kind, Id, Legacy, Dispatch).

with_bytes({ok, Bytes}, Kind, Id, Legacy, Dispatch) ->
    with_mcid(tube_content_put:put(Bytes), Kind, Id, Legacy, Dispatch);
with_bytes({error, enoent}, _Kind, _Id, _Legacy, _Dispatch) ->
    missing;
with_bytes({error, Reason}, _Kind, _Id, _Legacy, _Dispatch) ->
    {failed, Reason}.

with_mcid({ok, Mcid}, Kind, Id, Legacy, Dispatch) ->
    outcome(Dispatch({Kind, Id, Legacy, Mcid}));
with_mcid({error, Reason}, _Kind, _Id, _Legacy, _Dispatch) ->
    {failed, Reason}.

outcome({ok, _Version, _Events}) -> rehashed;
outcome({ok, _Id, _Version, _Events}) -> rehashed;
outcome({error, logo_is_not_the_legacy_mcid}) -> stale;
outcome({error, thumbnail_is_not_the_legacy_mcid}) -> stale;
outcome({error, Reason}) -> {failed, Reason}.

dispatch({logo, ChannelId, Legacy, Mcid}) ->
    maybe_rehash_channel_logo:dispatch(
      #{channel_id => ChannelId, legacy_mcid => Legacy, logo_mcid => Mcid});
dispatch({thumbnail, ClipId, Legacy, Mcid}) ->
    maybe_rehash_video_clip_thumbnail:dispatch(
      #{clip_id => ClipId, legacy_mcid => Legacy, thumbnail_mcid => Mcid}).

counted(Outcomes) ->
    lists:foldl(fun count/2, #{rehashed => 0, stale => 0, missing => 0, failed => 0}, Outcomes).

count({failed, _Reason}, Report) -> maps:update_with(failed, fun(N) -> N + 1 end, Report);
count(Outcome, Report) -> maps:update_with(Outcome, fun(N) -> N + 1 end, Report).

%% The legacy files a reference named, once no rehash that needs one failed.
remove_legacy_files(Outcomes) ->
    Kept = [Legacy || {Legacy, {failed, _}} <- Outcomes],
    Done = lists:usort([Legacy || {Legacy, Outcome} <- Outcomes,
                                  Outcome =:= rehashed orelse Outcome =:= stale]),
    length([ok = file:delete(legacy_path(Legacy))
            || Legacy <- Done, not lists:member(Legacy, Kept),
               filelib:is_regular(legacy_path(Legacy))]).

legacy_files() ->
    [list_to_binary(F) || F <- filelib:wildcard(filename:join(tube_content_store:dir(), "0155*.bin")),
                          byte_size(list_to_binary(filename:basename(F, ".bin"))) =:= 68].

legacy_path(Legacy) ->
    iolist_to_binary(filename:join(tube_content_store:dir(),
                                   <<(binary:encode_hex(Legacy, lowercase))/binary, ".bin">>)).

reported({error, Reason}) ->
    logger:error("[rehash_legacy_content] events unreadable, nothing rehashed: ~p", [Reason]);
reported(#{failed := 0} = Report) ->
    logger:notice("[rehash_legacy_content] ~p", [Report]);
reported(Report) ->
    logger:error("[rehash_legacy_content] some rehashes failed, their files are kept: ~p",
                 [Report]).

field(Key, Map) when is_atom(Key) ->
    maps:get(Key, Map, maps:get(atom_to_binary(Key, utf8), Map, undefined)).
