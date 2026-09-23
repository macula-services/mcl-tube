%%% @doc Where the four catalog facts are published: canonical macula app
%%% facts owned by org `mcl-tube', app `tube', domain `catalog', for example
%%% `io.macula/mcl-tube/tube/catalog/video_clip_published_v1'.
%%%
%%% These topics are the public contract a catalogue (the portal's) subscribes
%%% to. The realm NAME the topics carry is deploy config, checked at start against the
%%% realm tag the pool publishes in: a topic naming one realm published in
%%% another reaches nobody.
-module(tube_catalog_topic).

-export([topic/1, topic/2, realm_name/0, check_realm_name/0, check_realm_name/2]).

-type fact() :: channel_announced | video_clip_published | video_clip_retracted
              | video_clip_viewed.
-export_type([fact/0]).

-spec topic(fact()) -> binary().
topic(Fact) ->
    topic(realm_name(), Fact).

-spec topic(binary(), fact()) -> binary().
topic(RealmName, Fact) ->
    macula_topic:app_fact(RealmName, <<"mcl-tube">>, <<"tube">>, <<"catalog">>,
                          atom_to_binary(Fact, utf8), 1).

-spec realm_name() -> binary().
realm_name() ->
    named(application:get_env(guide_tube_lifecycle, realm_name, undefined)).

named(Name) when is_list(Name), Name =/= "" -> unicode:characters_to_binary(Name);
named(Name) when is_binary(Name), Name =/= <<>> -> Name;
named(_Unset) -> error({mcl_tube_realm_name_unset, realm_name}).

%% @doc Refuse to start unless the configured realm name is the realm the
%% pool is in.
-spec check_realm_name() -> ok.
check_realm_name() ->
    configured(realm_name(), mcl_om:realm()).

configured(Name, {ok, Tag}) -> check_realm_name(Name, Tag);
configured(Name, Other)     -> error({mcl_tube_realm_unset, Name, Other}).

-spec check_realm_name(binary(), binary()) -> ok.
check_realm_name(Name, Tag) ->
    matched(crypto:hash(sha256, Name) =:= Tag, Name, Tag).

matched(true, _Name, _Tag) -> ok;
matched(false, Name, Tag)  -> error({mcl_tube_realm_name_mismatch, Name, Tag}).
