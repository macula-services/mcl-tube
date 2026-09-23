%% @doc The service contract, asserted locally.
%%
%% mcl_om resolves its six callbacks BY NAME at startup, on a live node, so a
%% service that forgets one dies with `undef' where nobody is watching. The
%% primary defence is the `-behaviour(mcl_om_service)' attribute on the
%% service module, which turns a missing callback into a compile error under
%% warnings_as_errors.
%%
%% What this suite adds is everything the compiler cannot see: that the attribute
%% has not been quietly dropped, that the values inside those callbacks are the
%% shapes mcl_om will destructure, and that the names and version this service
%% reports are the ones it actually has. Nothing local boots mcl_om, so
%% asserting the shape by hand is the closest available thing to a rehearsal.
-module(mcl_tube_service_tests).

-include_lib("eunit/include/eunit.hrl").

-define(APP, mcl_tube).
-define(SERVICE, mcl_tube_service).

%% Belt and braces with the behaviour attribute, and it survives the attribute
%% being removed. If mcl_om ever adds a SEVENTH required callback this test
%% keeps passing and the deploy still breaks, which is the honest limit of a
%% local assertion about a remote contract.
exports_every_required_callback_test() ->
    _ = code:ensure_loaded(?SERVICE),
    Required = [{info, 0}, {start, 1}, {stop, 1},
                {health, 0}, {capabilities, 0}, {identity_spec, 0}],
    Missing = [F || {N, A} = F <- Required,
                    not erlang:function_exported(?SERVICE, N, A)],
    ?assertEqual([], Missing).

info_carries_the_three_keys_test() ->
    #{name := Name, version := Vsn, description := Desc} = ?SERVICE:info(),
    ?assert(is_binary(Name)),
    ?assert(is_binary(Vsn)),
    ?assert(is_binary(Desc)),
    ?assertEqual(<<"mcl-tube">>, Name).

%% THE TWO NAMES MUST AGREE. The OTP application is snake_case because it is an
%% Erlang atom; the repository, the container image and the name this service
%% answers to on the mesh are kebab-case. They describe one service, so a
%% scaffold generated with a mismatched pair is caught here on the first eunit
%% run rather than by a puzzled reader months later.
mesh_name_matches_the_application_test() ->
    #{name := Wire} = ?SERVICE:info(),
    Snake = atom_to_binary(?APP, utf8),
    ?assertEqual(binary:replace(Snake, <<"_">>, <<"-">>, [global]), Wire).

%% The version in info/0 is what a peer reads off /health, so it disagreeing with
%% the application it describes is a lie that nothing else would catch.
info_version_matches_the_application_test() ->
    _ = application:load(?APP),
    {ok, Vsn} = application:get_key(?APP, vsn),
    #{version := Reported} = ?SERVICE:info(),
    ?assertEqual(list_to_binary(Vsn), Reported).

%%==============================================================================
%% The RPC contract: what callers dial
%%==============================================================================

%% The four procedures, org-qualified the way mcl_om registers them. This is
%% the contract the portal's watch and thumbnail controllers call. A change
%% here is a new name, not an edit.
the_procedures_are_the_published_contract_test() ->
    ?assertEqual([<<"mcl-tube/lookup_channel">>, <<"mcl-tube/lookup_content">>,
                  <<"mcl-tube/lookup_video_clip">>, <<"mcl-tube/watch_video_clip">>],
                 lists:sort([mcl_om_capabilities:org_procedure(<<"mcl-tube">>, Name)
                             || #{name := Name} <- ?SERVICE:capabilities()])).

every_procedure_has_its_handler_test() ->
    ?assertEqual(#{<<"lookup_channel">> => {advertise_channel_lookup, []},
                   <<"lookup_video_clip">> => {advertise_video_clip_lookup, []},
                   <<"lookup_content">> => {advertise_content_lookup, []},
                   <<"watch_video_clip">> => {stream_video_clip_by_id, []}},
                 maps:from_list([{N, H} || #{name := N, handler := H} <- ?SERVICE:capabilities()])).

%% The watch is a stream, served by macula_streamer; the rest are request and
%% reply.
only_the_watch_is_a_stream_test() ->
    ?assertEqual([<<"watch_video_clip">>],
                 [N || #{name := N, kind := streamer} <- ?SERVICE:capabilities()]).

%% The org the procedures are registered under is deploy config, so the
%% shipped config must name the org the contract promises.
the_shipped_config_names_the_org_test() ->
    {ok, Text} = file:read_file(alongside("config/sys.config.src")),
    ?assertNotEqual(nomatch, binary:match(Text, <<"{org,               <<\"mcl-tube\">>}">>)).

%%==============================================================================
%% Health: whether callers can reach it
%%==============================================================================

%% A missing D25 provider grant is reported by mcl_om itself (>= 0.26.3): its
%% /health combines this service's own verdict with the grant verdict for
%% every procedure. So the service's own health is about nothing else, and
%% is ok.
the_service_itself_is_healthy_test() ->
    ?assertEqual(ok, ?SERVICE:health()).

%% The grant check lives in mcl_om now. A build that resolved an mcl_om older
%% than 0.26.3 would compile and silently lose it, so the function it rests on
%% is asserted to exist in the mcl_om this was built against.
the_resolved_mcl_om_reports_provider_grants_test() ->
    {module, _} = code:ensure_loaded(mcl_om_capabilities),
    ?assert(erlang:function_exported(mcl_om_capabilities, provider_grants, 0)).

%%==============================================================================
%% The owner web UI
%%==============================================================================

%% The owner UI uploads, reconfigures and retracts, and has no authentication
%% of its own. Under host networking an all-interfaces bind hands those to
%% anyone who can reach the port, so it binds loopback unless told otherwise.
the_owner_ui_binds_loopback_by_default_test() ->
    ok = application:unset_env(?APP, http_ip),
    ?assertEqual({127, 0, 0, 1}, proplists:get_value(ip, mcl_tube_sup:socket_opts())).

the_owner_ui_bind_address_is_configurable_test() ->
    ok = application:set_env(?APP, http_ip, "::1"),
    try ?assertEqual({0, 0, 0, 0, 0, 0, 0, 1},
                     proplists:get_value(ip, mcl_tube_sup:socket_opts()))
    after application:unset_env(?APP, http_ip)
    end.

%%==============================================================================
%% The upload scan needs ffmpeg, in the image and in CI
%%==============================================================================

%% video_clip_scan shells out to ffprobe/ffmpeg. An image without them rejects
%% EVERY upload as {executable_not_found, "ffprobe"} while the service looks
%% healthy. The port once shipped exactly that, taking the scaffold's
%% Containerfile over the one that installed ffmpeg; CI caught it only because
%% the scan's own test runs against a real clip.
the_runtime_image_installs_ffmpeg_test() ->
    {ok, Text} = file:read_file(alongside("Containerfile")),
    [_Builder, Runtime] = binary:split(Text, <<"FROM docker.io/alpine">>),
    ?assertNotEqual(nomatch, binary:match(Runtime, <<"ffmpeg">>)).

ci_installs_ffmpeg_for_the_scan_tests_test() ->
    {ok, Text} = file:read_file(alongside(".github/workflows/lint.yml")),
    ?assertNotEqual(nomatch, binary:match(Text, <<"ffmpeg">>)).

%%==============================================================================
%% Start
%%==============================================================================

start_refuses_without_a_realm_name_test() ->
    ok = application:unset_env(guide_tube_lifecycle, realm_name),
    ?assertError({mcl_tube_realm_name_unset, realm_name}, ?SERVICE:start(#{})).

identity_spec_has_the_shape_mcl_om_expects_test() ->
    #{scope := Scope, actions := Actions,
      resources := Resources, ttl_days := Ttl} = ?SERVICE:identity_spec(),
    ?assert(is_binary(Scope)),
    ?assert(is_list(Actions)),
    ?assert(is_list(Resources)),
    ?assert(is_integer(Ttl) andalso Ttl > 0).

%% The authority is the D25 provider grant, issued by the realm per procedure,
%% not a UCAN this service asks for.
identity_spec_asks_for_nothing_test() ->
    #{actions := Actions, resources := Resources} = ?SERVICE:identity_spec(),
    ?assertEqual([], Actions),
    ?assertEqual([], Resources).

%% One child: the owner UI's listener.
supervisor_children_test() ->
    {ok, {_Flags, Children}} = mcl_tube_sup:init([]),
    ?assertEqual([{ranch_embedded_sup, mcl_tube_http}], [Id || #{id := Id} <- Children]).

%%==============================================================================
%% The config the store cannot boot without
%%==============================================================================

%% ⚠ A SIBLING SERVICE'S FLEET CRASH-LOOPED ON TWO OF THREE NODES FOR WANT OF THE
%% `evoq' BLOCK.
%%
%% Exporting `store_id/0' makes `mcl_om:boot/1' start the store AND a per-store
%% evoq subscription. That subscription reads through evoq, which raises
%% `{not_configured, event_store_adapter}' unless sys.config names the adapter,
%% and evoq starts as a release-boot application before any service's `start/2'
%% runs, so nothing can inject it later.
%%
%% This reads the shipped config template, because the failure is a MISSING BLOCK
%% and no amount of exercising the code can notice something that is not there.
%% It compares the Erlang side of a boundary against the config side, which is
%% what neither side's own tests can do.
the_evoq_adapter_is_configured_wherever_a_store_is_opened_test() ->
    {ok, Text} = file:read_file(alongside("config/sys.config.src")),
    ?assert(erlang:function_exported(?SERVICE, store_id, 0)),
    lists:foreach(
      fun(Needed) ->
              ?assertNotEqual(nomatch, binary:match(Text, Needed),
                              {missing_from_sys_config, Needed})
      end,
      [<<"{evoq,">>, <<"event_store_adapter">>, <<"subscription_adapter">>,
       <<"reckon_evoq_adapter">>]).

%% ⚠ AND THE STORE ID IS IN TWO PLACES, WHICH IS ONE MORE THAN IT SHOULD BE.
%% `store_id/0' is what mcl_om opens; the `{store_id, ...}' in the evoq block
%% is what evoq falls back to when it resolves a dispatch before knowing there is
%% none. Nothing makes them agree, and disagreeing opens one store and addresses
%% another. Same boundary guard, other side.
the_store_id_agrees_between_erlang_and_config_test() ->
    {ok, Text} = file:read_file(alongside("config/sys.config.src")),
    Declared = atom_to_binary(?SERVICE:store_id(), utf8),
    ?assertNotEqual(nomatch, binary:match(Text, Declared),
                    {store_id_not_in_sys_config, Declared}).

%% The data directory must be somewhere, and a laptop default is fine. What is
%% not fine is shipping that default to a node, which is why the generated
%% compose file mounts a volume and sets the variable this reads.
the_data_directory_is_answerable_test() ->
    ?assert(erlang:function_exported(?SERVICE, data_dir, 0)),
    ?assert(is_list(?SERVICE:data_dir())),
    ?assertNotEqual("", ?SERVICE:data_dir()).
%%==============================================================================
%% The runtime is pinned in two places, and neither is the one you are running
%%==============================================================================

%% ⚠ THIS GUARD EXISTS BECAUSE A SIBLING SERVICE DID NOT HAVE IT, AND IT COST
%% THREE COMMITS AND AN IMAGE THAT SHIPPED ANYWAY.
%%
%% Its `Containerfile' said 27 while development ran on 28. So `rebar3 eunit'
%% passing locally meant "passing on 28" and nothing more, CI failed on a crash
%% that does not occur on 28 at all, and because the image build is a separate
%% workflow the image went to the fleet regardless.
%%
%% The release is pinned in TWO files, and the version actually running is a
%% third thing that agrees with neither by default. **A comment in each file
%% saying they must match is not a mechanism**, and both files carried one.
%%
%% ⚠⚠ IT FAILS RATHER THAN WARNS WHEN YOUR VM DIFFERS, AND THAT IS DELIBERATE.
%% Developing on a release you do not ship makes a green suite mean less than it
%% appears to. If you want to work on another release, move both pins and find
%% out what breaks, which is the whole point of having them.
the_runtime_agrees_between_the_image_the_ci_and_this_vm_test() ->
    Image = pinned("Containerfile", "FROM docker.io/erlang:([0-9]+)"),
    Ci = pinned(".github/workflows/lint.yml", "image: erlang:([0-9]+)"),
    Running = list_to_binary(erlang:system_info(otp_release)),
    %% Sorted and deduplicated, so a failure prints all three rather than the
    %% first pair that happened to be compared.
    ?assertEqual([Image], lists:usort([Image, Ci, Running])).

pinned(Relative, Pattern) ->
    {ok, Text} = file:read_file(alongside(Relative)),
    {match, [Version]} = re:run(Text, Pattern,
                                [{capture, all_but_first, binary}]),
    Version.

%% Relative to the beam rather than the working directory, because eunit runs
%% from wherever the developer happens to be standing.
alongside(Name) -> climb(filename:dirname(code:which(?MODULE)), Name, 8).

climb(_Dir, Name, 0) -> Name;
climb(Dir, Name, Left) ->
    Candidate = filename:join(Dir, Name),
    found(filelib:is_regular(Candidate), Candidate, Dir, Name, Left).

found(true, Candidate, _Dir, _Name, _Left) -> Candidate;
found(false, _Candidate, Dir, Name, Left) ->
    climb(filename:dirname(Dir), Name, Left - 1).
