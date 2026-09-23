%%% @doc The provider-grant check behind health: which procedures macula can
%%% resolve a D25 grant for, and what a dark mesh does to the answer.
-module(check_provider_grant_tests).

-include_lib("eunit/include/eunit.hrl").

every_procedure_is_checked_under_the_configured_org_test() ->
    with_mocks(fun() ->
        meck:expect(macula, provider_authorization,
                    fun(pool, <<0:256>>, <<"mcl-tube/watch_video_clip">>) -> {error, no_delegation};
                       (pool, <<0:256>>, _Proc) -> {ok, #{}}
                    end),
        ?assertEqual(#{<<"mcl-tube/lookup_channel">> => granted,
                       <<"mcl-tube/lookup_video_clip">> => granted,
                       <<"mcl-tube/lookup_content">> => granted,
                       <<"mcl-tube/watch_video_clip">> => missing},
                     checked(#{}))
    end).

%% A dark mesh proves nothing about the grant: the last answer stands.
a_dark_mesh_keeps_the_last_answer_test() ->
    with_mocks(fun() ->
        meck:expect(mcl_om, mesh_handles, fun() -> {error, mesh_unavailable} end),
        Last = #{<<"mcl-tube/lookup_channel">> => missing},
        ?assertEqual(Last, checked(Last))
    end).

%% --- helpers ---

with_mocks(Test) ->
    ok = meck:new(mcl_om, [non_strict]),
    ok = meck:expect(mcl_om, mesh_handles, fun() -> {ok, pool, <<0:256>>} end),
    ok = meck:new(mcl_om_identity, [non_strict]),
    ok = meck:expect(mcl_om_identity, org, fun() -> <<"mcl-tube">> end),
    ok = meck:new(macula, [non_strict]),
    try Test()
    after meck:unload()
    end.

%% One check, driven through the gen_server callback it runs on.
checked(Previous) ->
    {noreply, Status} = check_provider_grant:handle_info(check, Previous),
    Status.
