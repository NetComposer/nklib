%% -------------------------------------------------------------------
%%
%% Copyright (c) 2017 Carlos Gonzalez Florido.  All Rights Reserved.
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

-export([get_module/2, get_all_modules/1]).
-export([get_type/2, get_all_types/1]).
-export([register/3]).
-export([start_link/0]).
-export([init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).


%% ===================================================================
%% Types
%% ===================================================================

-type class() :: term().
-type type() :: binary().


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Finds a type's module
-spec get_module(class(), type()) ->
    module() | undefined.

get_module(Class, Type) ->
    Type2 = to_bin(Type),
    lookup({type, Class, Type2}).


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


%% @doc Gets the obj module for a type
-spec register(class(), type(), module()) ->
    ok.

register(Class, Type, Module) when is_atom(Module) ->
    code:ensure_loaded(Module),
    Type2 = to_bin(Type),
    gen_server:call(?MODULE, {register_type, Class, Type2, Module}).




% ===================================================================
%% gen_server behaviour
%% ===================================================================

%% @private
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).


-record(state, {}).


%% @private
-spec init(term()) ->
    {ok, #state{}} | {error, term()}.

init([]) ->
    ets:new(?MODULE, [named_table, public, {read_concurrency, true}]),
    {ok, #state{}}.


%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {noreply, #state{}} | {reply, term(), #state{}} |
    {stop, Reason::term(), #state{}} | {stop, Reason::term(), Reply::term(), #state{}}.

handle_call({register_type, Class, Type, Module}, _From, State) ->
    State2 = register_type(Class, Type, Module, State),
    {reply, ok, State2};

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
register_type(Class, Type, Module, _State) ->
    AllModules1 = get_all_modules(Class),
    AllModules2 = lists:usort([Module|AllModules1]),
    AllTypes1 = get_all_types(Class),
    AllTypes2 = lists:usort([Type|AllTypes1]),
    ets:insert(?MODULE, [
        {{all_modules, Class}, AllModules2},
        {{all_types, Class}, AllTypes2},
        {{type, Class, Type}, Module},
        {{module, Class, Module}, Type}
    ]).


%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).