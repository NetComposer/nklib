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

%% @doc NkLIB i18n Server.
-module(nklib_i18n).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([get/2, get/3, get/4, insert/2, insert/3, load/2]).
-export([start_link/0, init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2, 
         handle_info/2]).

-compile({no_auto_import,[get/1]}).

%% ===================================================================
%% Types
%% ===================================================================

-type srv_id() :: term().
-type key() :: binary().
-type text() :: string() | binary().

-type lang() :: nklib:lang().

-callback i18n() ->
    #{ lang() => #{ key() => text() }}.


%% ===================================================================
%% Public
%% ===================================================================

%% @doc Gets a string for english
-spec get(srv_id(), key()) ->
    binary().

get(SrvId, Key) ->
    get(SrvId, Key, <<"en">>).


%% @doc Gets a string for any language, or use english default
-spec get(srv_id(), key(), lang()) ->
    binary().

get(SrvId, Key, Lang) ->
    Lang2 = to_bin(Lang),
    case ets:lookup(?MODULE, {SrvId, to_bin(Key), Lang2}) of
        [] when Lang2 == <<"en">> ->
            <<>>;
        [] ->
            get(SrvId, Key, <<"en">>);
        [{_, Msg}] ->
            Msg
    end.


%% @doc Gets a string an expands parameters
-spec get(srv_id(), key(), list(), lang()) ->
    binary().

get(SrvId, Key, List, Lang) when is_list(List) ->
    case get(SrvId, Key, Lang) of
        <<>> ->
            <<>>;
        Msg ->
            case catch io_lib:format(nklib_util:to_list(Msg), List) of
                {'EXIT', _} ->
                    lager:notice("Invalid format in i18n: ~s, ~p", [Msg, List]),
                    <<>>;
                Val ->
                    list_to_binary(Val)
            end
    end.


%% @doc Inserts a key or keys for english
-spec insert(srv_id(), {key(), text()}|[{key(), text()}]) ->
    ok.

insert(SrvId, Keys) ->
    insert(SrvId, Keys, <<"en">>).


%% @doc Inserts a key or keys for any language
-spec insert(srv_id(), {key(), text()}|[{key(), text()}], lang()) ->
    ok.

insert(_SrvId, [], _Lang) ->
    ok;

insert(SrvId, [{_, _}|_]=Keys, Lang) ->
    gen_server:cast(?MODULE, {insert, SrvId, Keys, to_bin(Lang)});

insert(SrvId, {Key, Txt}, Lang) ->
    insert(SrvId, [{Key, Txt}], Lang);

insert(SrvId, Map, Lang) when is_map(Map) ->
    insert(SrvId, maps:to_list(Map), Lang).


%% @doc Bulk loading for modules implementing this behaviour
-spec load(srv_id(), module()) ->
    ok.

load(SrvId, Module) ->
    Data = Module:i18n(),
    lists:foreach(
        fun({Lang, Keys}) -> insert(SrvId, Keys, Lang) end,
        maps:to_list(Data)).



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
    ets:new(?MODULE, [named_table, protected, {read_concurrency, true}]),
    {ok, #state{}}.
    

%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {noreply, #state{}}.

handle_call(Msg, _From, State) ->
    lager:error("Module ~p received unexpected call ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_cast(term(), #state{}) ->
    {noreply, #state{}}.

handle_cast({insert, SrvId, Keys, Lang}, State) ->
    Values = [{{SrvId, to_bin(Key), Lang}, to_bin(Txt)} || {Key, Txt} <- Keys],
    ets:insert(?MODULE, Values),
    {noreply, State};

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


%% @private
to_bin(K) when is_binary(K) -> K;
to_bin(K) -> nklib_util:to_binary(K).


