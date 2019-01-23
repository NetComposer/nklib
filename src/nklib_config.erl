%% -------------------------------------------------------------------
%%
%% Copyright (c) 2019 Carlos Gonzalez Florido.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

%% @doc NkLIB Config Server.
-module(nklib_config).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([get/2, get/3, put/3, del/2, increment/3, update/3]).
-export([get_domain/3, get_domain/4, put_domain/4, del_domain/3, increment_domain/4, update_domain/4]).
-export([load_env/2, load_env/3, get_env/1]).
-export([make_cache/5]).
-export([parse_config/2, parse_config/3]).

-export([start_link/0, init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2, 
         handle_info/2]).

-compile({no_auto_import, [get/1, put/2]}).


-type syntax() :: nklib_syntax:syntax().


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Equivalent to `get(Key, undefined)'.
-spec get(term(), term()) -> 
    Value :: term().

get(Mod, Key) ->
    get(Mod, Key, undefined).


%% @doc Gets an config value.
-spec get(term(), term(), term()) -> 
    Value :: term().

get(Mod, Key, Default) -> 
    case ets:lookup(?MODULE, {Mod, none, Key}) of
        [] -> Default;
        [{_, Value}] -> Value
    end.


%% @doc Sets a config value.
-spec put(term(), term(), term()) -> 
    ok.

put(Mod, Key, Val) -> 
    put_domain(Mod, none, Key, Val).


%% @doc Deletes a config value.
-spec del(term(), term()) -> 
    ok.

del(Mod, Key) -> 
    del_domain(Mod, none, Key).


%% @doc Atomically increments or decrements a counter
-spec increment(term(), term(), integer()) ->
    integer().

increment(Mod, Key, Count) ->
    increment_domain(Mod, none, Key, Count).


%% @doc Sets a config value.
-spec update(term(), term(), fun((term()) -> term())) ->
    ok.

update(Mod, Key, Fun) ->
    update_domain(Mod, none, Key, Fun).



%% @private
-spec get_domain(term(), nklib:domain(), term()) -> 
    Value :: term().

get_domain(Mod, Domain, Key) ->
    get_domain(Mod, Domain, Key, undefined).


%% @private
-spec get_domain(term(), nklib:domain(), term(), term()) -> 
    Value :: term().

get_domain(Mod, Domain, Key, Default) ->
    case ets:lookup(?MODULE, {Mod, Domain, Key}) of
        [] -> get(Mod, Key, Default);
        [{_, Value}] -> Value
    end.


%% @doc Sets a config value.
-spec put_domain(term(), nklib:domain(), term(), term()) -> 
    ok.

put_domain(Mod, Domain, Key, Val) -> 
    true = ets:insert(?MODULE, {{Mod, Domain, Key}, Val}),
    ok.


%% @doc Deletes a config value.
-spec del_domain(term(), nklib:domain(), term()) -> 
    ok.

del_domain(Mod, Domain, Key) -> 
    true = ets:delete(?MODULE, {Mod, Domain, Key}),
    ok.


%% @doc Atomically increments or decrements a counter
-spec increment_domain(term(), nklib:domain(), term(), integer()) ->
    integer().

increment_domain(Mod, Domain, Key, Count) ->
    ets:update_counter(?MODULE, {Mod, Domain, Key}, Count).



%% @doc Sets a config value.
-spec update_domain(term(), nklib:domain(), term(), fun((term()) -> term())) ->
    ok.

update_domain(Mod, Domain, Key, Fun) ->
    gen_server:call(?MODULE, {update, Mod, Domain, Key, Fun}).


%% @doc Loads parsed application environment
-spec load_env(atom(), syntax()) ->
    {ok, map()} | {error, term()}.

load_env(App, Syntax) ->
    AppEnv = application:get_all_env(App),
    case nklib_syntax:parse(AppEnv, Syntax) of
        {ok, Opts, _} ->
            lists:foreach(fun({K,V}) -> put(App, K, V) end, maps:to_list(Opts)),
            put(App, '__nklib_all_env', Opts),
            {ok, Opts};
        {error, Error} ->
            {error, Error}
    end.


%% @doc Loads parsed application environment
-spec load_env(atom(), syntax(), map()) ->
    {ok, map()} | {error, term()}.

load_env(App, Syntax, Defaults) ->
    Defaults1 = maps:get('__defaults', Syntax, #{}),
    Defaults2 = maps:merge(Defaults1, Defaults),
    load_env(App, Syntax#{'__defaults' => Defaults2}).


%% @doc Gets all loaded keys
-spec get_env(atom()) ->
    {ok, map()} | {error, term()}.

get_env(App) ->
    get(App, '__nklib_all_env').



%% Generates on the fly a 'cache' module for the indicated keys
-spec make_cache([atom()], module(), nklib:domain(), module(), string()|binary()|none) ->
    ok.

make_cache(KeyList, Mod, Domain, Module, Path) ->
    Syntax1 = lists:foldl(
        fun(Key, Acc) ->
            Val = get_domain(Mod, Domain, Key),
            [nklib_code:getter(Key, Val)|Acc]
        end,
        [],
        KeyList),
    Syntax2 = [nklib_code:getter(hot_compiled, true) | Syntax1],
    {ok, Tree} = nklib_code:compile(Module, Syntax2),
    case Path of
        none -> ok;
        _ -> ok = nklib_code:write(Module, Tree, Path)
    end.


%% @doc Temporary old version
parse_config(Terms, Spec) ->
    parse_config(Terms, Spec, #{}).


%% @doc
parse_config(Terms, Syntax, Opts) ->
    nklib_config_parse_old:parse_config(Terms, Syntax, Opts).




%% ===================================================================
%% gen_server
%% ===================================================================

-record(state, {
}).


%% @private
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
        

%% @private 
-spec init(term()) ->
    {ok, #state{}}.

init([]) ->
    ets:new(?MODULE, [named_table, public, {read_concurrency, true}]),
    {ok, #state{}}.
    

%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {noreply, #state{}}.

handle_call({update, Mod, Domain, Key, Fun}, _From, State) ->
    Old = get_domain(Mod, Domain, Key),
    case catch Fun(Old) of
        {'EXIT', Error} ->
            {reply, {error, Error}, State};
        New ->
            put_domain(Mod, Domain, Key, New),
            {reply, ok, State}
    end;

handle_call(Msg, _From, State) ->
    lager:error("Module ~p received unexpected call ~p", [?MODULE, Msg]),
    {noreply, State}.

%% @private
-spec handle_cast(term(), #state{}) ->
    {noreply, #state{}}.

handle_cast(Msg, State) -> 
    lager:error("Module ~p received unexpected cast ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_info(term(), #state{}) ->
    {noreply, #state{}}.

handle_info(Info, State) -> 
    lager:warning("Module ~p received unexpected info: ~p", [?MODULE, Info]),
    {noreply, State}.


%% @private
-spec code_change(term(), #state{}, term()) ->
    {ok, #state{}}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% @private
-spec terminate(term(), #state{}) ->
    ok.

terminate(_Reason, _State) ->  
    ok.



%% ===================================================================
%% Private
%% ===================================================================


     

%% ===================================================================
%% EUnit tests
%% ===================================================================


% -compile([export_all]).
% -define(TEST, 1).
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").


basic_test_() ->
    {setup, 
        fun() -> catch init([]) end,
        fun(_) ->  ok end,
        [
            fun config/0
        ]
    }.


config() ->
    M = ?MODULE,
    K = make_ref(),
    undefined = get(M, K),
    none = get(M, K, none),
    undefined = get_domain(M, dom1, K),
    none = get_domain(M, dom1, K, none),

    ok = put(M, K, val1),
    val1 = get(M, K),
    val1 = get_domain(M, dom1, K),
    ok = put_domain(M, dom1, K, val2),
    val2 = get_domain(M, dom1, K),
    val1 = get(M, K),

    ok = del(M, K),
    undefined = get(M, K),
    val2 = get_domain(M, dom1, K),
    ok = del_domain(M, dom1, K),
    undefined = get_domain(M, dom1, K),
    ok.



-endif.










