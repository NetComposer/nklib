%% -------------------------------------------------------------------
%%
%% Copyright (c) 2018 Carlos Gonzalez Florido.  All Rights Reserved.
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
%%

%% @doc Very simple register of types and modules
-module(nklib_types).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([get_module/2, get_all_modules/1, get_meta/2]).
-export([get_type/2, get_all_types/1]).
-export([register_type/3, register_type/4, update_meta/3]).
-export([start_link/0]).
-export([init/1, terminate/2, code_change/3, handle_call/3,
    handle_cast/2, handle_info/2]).


%% ===================================================================
%% Types
%% ===================================================================

-type class() :: term().
-type type() :: binary().
-type meta() :: map().


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Finds a type's module
-spec get_module(class(), type()) ->
    module() | undefined.

get_module(Class, Type) ->
    lookup({type, Class, to_bin(Type)}).


%% @doc Gets all registered modules
-spec get_all_modules(class()) ->
    [module()].

get_all_modules(Class) ->
    lookup({all_modules, Class}, []).


%% @doc Finds a module's type
-spec get_type(class(), module()) ->
    nkdomain:type() | undefined.

get_type(Class, Module) ->
    lookup({module, Class, Module}).


%% @doc Gets all registered types
-spec get_all_types(class()) ->
    [nkdomain:type()].

get_all_types(Class) ->
    lookup({all_types, Class}, []).


%% @doc Finds a type's metadata
-spec get_meta(class(), type()) ->
    meta() | undefined.

get_meta(Class, Type) ->
    lookup({meta, Class, to_bin(Type)}).


%% @doc Registers a type with a module
-spec register_type(class(), type(), module()) ->
    ok.

register_type(Class, Type, Module) ->
    register_type(Class, Type, Module, #{}).


%% @doc Registers a type with a module and some metadata
-spec register_type(class(), type(), module(), meta()) ->
    ok.

register_type(Class, Type, Module, Meta) when is_atom(Module), is_map(Meta) ->
    code:ensure_loaded(Module),
    gen_server:call(?MODULE, {register_type, Class, to_bin(Type), Module, Meta}).


%% @doc Updates meta for a type
-spec update_meta(class(), type(), fun((meta()) -> meta())) ->
    ok | {error, term()}.

update_meta(Class, Type, Fun) when is_function(Fun, 1)->
    gen_server:call(?MODULE, {update_meta, Class, to_bin(Type), Fun}).



% ===================================================================
%% gen_server behaviour
%% ===================================================================

%% @private
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).


-record(state, {}).


%% @private
-spec init(term()) ->
    {ok, #state{}}.

init([]) ->
    ets:new(?MODULE, [named_table, public, {read_concurrency, true}]),
    {ok, #state{}}.


%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {noreply, #state{}} | {reply, term(), #state{}} |
    {stop, Reason::term(), #state{}} | {stop, Reason::term(), Reply::term(), #state{}}.

handle_call({register_type, Class, Type, Module, Meta}, _From, State) ->
    AllModules1 = get_all_modules(Class),
    AllModules2 = lists:usort([Module|AllModules1]),
    AllTypes1 = get_all_types(Class),
    AllTypes2 = lists:usort([Type|AllTypes1]),
    ets:insert(?MODULE, [
        {{type, Class, Type}, Module},
        {{module, Class, Module}, Type},
        {{meta, Class, Type}, Meta},
        {{all_modules, Class}, AllModules2},
        {{all_types, Class}, AllTypes2}
    ]),
    {reply, ok, State};

handle_call({update_meta, Class, Type, Fun}, _From, State) ->
    Meta1 = lookup({meta, Class, Type}, #{}),
    try Fun(Meta1) of
        Meta2 when is_map(Meta2) ->
            ets:insert(?MODULE, {{meta, Class, Type}, Meta2}),
            {reply, ok, State};
        Other ->
            lager:warning("NkLIB Types: invalid meta respose (~p ~p): ~p", [Class, Type, Other]),
            {reply, {error, function_error, State}}
    catch
        error:Error ->
            lager:warning("NkLIB Types: invalid meta respose (~p ~p): ~p", [Class, Type, Error]),
            {reply, {error, function_error, State}}
    end;

handle_call(Msg, _From, State) ->
    lager:error("Module ~p received unexpected call ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_cast(term(), #state{}) ->
    {noreply, #state{}} | {stop, term(), #state{}}.

handle_cast(Msg, State) ->
    lager:error("Module ~p received unexpected cast ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_info(term(), #state{}) ->
    {noreply, #state{}} | {stop, term(), #state{}}.

handle_info(Info, State) ->
    lager:warning("Module ~p received unexpected info: ~p (~p)", [?MODULE, Info, State]),
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
%% Internal
%% ===================================================================

%% @private
lookup(Term) ->
    lookup(Term, undefined).


%% @private
lookup(Term, Default) ->
    case ets:lookup(?MODULE, Term) of
        [] -> Default;
        [{_, Val}] -> Val
    end.



%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).