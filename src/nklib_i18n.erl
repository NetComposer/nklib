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

-export([get/1, get/2, insert/1, insert/2]).
-export([start_link/0, init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2, 
         handle_info/2]).

-compile({no_auto_import,[get/1]}).

%% ===================================================================
%% Types
%% ===================================================================

-type key() ::
    atom() |            
    {atom(), Reason::string()|binary()} |
    {atom(), Reason::string()|binary(), User::string()|binary()}.

-type lang() :: atom().         % en | es ...




%% ===================================================================
%% Public
%% ===================================================================

%% @public
-spec get(key()) ->
    {Code::atom(), Usr::binary(), Reason::binary()}.

get(Key) ->
    get(Key, en).


%% @public
-spec get(key(), lang()) ->
    {Code::atom(), Usr::binary(), Reason::binary()}.

get(Key, Lang) when is_atom(Key) ->
    case find(msg, Key, Lang) of
        not_found ->
            case find(usr, Key, Lang) of
                not_found ->
                    {Key, <<>>, <<>>};
                Usr ->
                    {Key, Usr, <<>>}
            end;
        {Usr, Msg} ->
            {Key, Usr, Msg}
    end;

get({Key, UsrArgs}, Lang) when is_atom(Key), is_list(UsrArgs) ->
    case find(msg, Key, Lang) of
        not_found ->
            case find(usr, Key, Lang) of
                not_found ->
                    {Key, <<>>, <<>>};
                Usr ->
                    {Key, exp(Usr, UsrArgs), <<>>}
            end;
        {Usr, Msg} ->
            {Key, exp(Usr, UsrArgs), Msg}
    end;

get({Key, UsrArg}, Lang) when is_atom(Key) ->
    get({Key, [UsrArg]}, Lang);

get({Key, UsrArgs, MsgArgs}, Lang) when is_atom(Key), 
                                           is_list(UsrArgs), is_list(MsgArgs) ->
    case find(msg, Key, Lang) of
        not_found ->
            case find(usr, Key, Lang) of
                not_found ->
                    {Key, <<>>, <<>>};
                Usr ->
                    {Key, exp(Usr, UsrArgs), <<>>}
            end;
        {Usr, Msg} ->
            {Key, exp(Usr, UsrArgs), exp(Msg, MsgArgs)}
    end;

get({Key, UsrArg, MsgArgs}, Lang) when is_atom(Key), is_list(MsgArgs) ->
    get({Key, [UsrArg], MsgArgs}, Lang);

get({Key, UsrArgs, MsgArg}, Lang) when is_atom(Key), is_list(UsrArgs) ->
    get({Key, UsrArgs, [MsgArg]}, Lang);

get({Key, UsrArg, MsgArg}, Lang) when is_atom(Key) ->
    get({Key, [UsrArg], [MsgArg]}, Lang).


%% @doc
-spec insert(key()|[key()]) ->
    ok.

insert(Keys) ->
    insert(Keys, en).


%% @doc
-spec insert(key()|[key()], lang()) ->
    ok.

insert(Keys, Lang) ->
    gen_server:call(?MODULE, {insert, Keys, Lang}).






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

handle_call({insert, Keys, Lang}, _From, State) -> 
    {reply, do_insert(Keys, Lang), State};


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


%% @private
exp(Fmt, List) ->
    case catch io_lib:format(nklib_util:to_list(Fmt), List) of
        {'EXIT', _} ->
            lager:notice("Invalid format in i18n: ~p, ~p", [Fmt, List]),
            <<>>;
        Val ->
            list_to_binary(Val)
    end.


%% @private
find(Type, Key, Lang) ->
    case ets:lookup(?MODULE, {Type, Key, Lang}) of
        [] when Lang==en ->
            not_found;
        [] ->
            find(Type, Key, en);
        [{_, Body}] -> 
            Body
    end.

%% @doc
-spec do_insert(key(), lang()) ->
    ok.

do_insert([], _Lang) ->
    ok;

do_insert([{Key, Usr}|Rest], Lang) when is_atom(Key) ->
    Body = nklib_util:to_binary(Usr),
    ets:insert(?MODULE, {{usr, Key, Lang}, Body}),
    do_insert(Rest, Lang);

do_insert([{Key, Usr, Msg}|Rest], Lang) when is_atom(Key) ->
    Body = {nklib_util:to_binary(Usr), nklib_util:to_binary(Msg)},
    ets:insert(?MODULE, {{msg, Key, Lang}, Body}),
    do_insert(Rest, Lang);

do_insert([_Other|_], _Lang) ->
    {error, invalid_key};

do_insert(Term, Lang) ->
    do_insert([Term], Lang).





%% ===================================================================
%% EUnit tests
%% ===================================================================

% -define(TEST, 1).
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").



basic_test_() ->
    {setup, 
        fun() -> 
            case whereis(?MODULE) of
                undefined ->
                    start_link();
                _ ->
                    ok
            end
        end,
        fun(_) ->  ok end,
        [
            fun single/0
        ]
    }.



single() ->
    insert([
        {k1, "u_k1_en:~p", "m_k1_en:~p"},
        {k2, "u_k1_en:~p"},
        k3
    ]),

    insert([
        {k4, "u_k4_es:~p", "m_k4_es:~p"}
    ], es),

    insert([
        {k4, "u_k4_en:~p", "m_k4_en:~p"}
    ], en),



    R1 = {k0, <<>>, <<>>} = get(k0),
    R1 = get(k0, en),
    R1 = get(k0, es),
    
    R2 = {k1, <<"u_k1_en:~p">>, <<"m_k1_en:~p">>} = get(k1),
    R2 = get(k1, en),
    R2 = get(k1, es),

    R3 = {k1, <<"u_k1_en:a">>,<<"m_k1_en:~p">>} = get({k1, [a]}),
    R3 = get({k1, [a]}, en),
    R3 = get({k1, [a]}, es),

    {k1, <<"u_k1_en:a">>, <<"m_k1_en:~p">>} = get({k1, a}),
    {k1, <<"u_k1_en:a">>, <<"m_k1_en:b">>} = get({k1, [a], [b]}),
    {k1, <<"u_k1_en:a">>, <<"m_k1_en:b">>} = get({k1, a, [b]}),
    {k1, <<"u_k1_en:a">>, <<"m_k1_en:b">>} = get({k1, [a], b}),
    {k1, <<"u_k1_en:a">>, <<"m_k1_en:b">>} = get({k1, a, b}), 

    R4 = {k2, <<"u_k1_en:~p">>, <<>>} = get(k2),
    R4 = get(k2, en),
    R4 = get(k2, es),

    R5 = {k2, <<"u_k1_en:c">>, <<>>} = get({k2, c}),
    R5 = get({k2, c}, en),
    R5 = get({k2, c}, es),

    R6 = {k3, <<>>, <<>>} = get(k3),
    R6 = get({k3, a}),
    R6 = get({k3, a, b}),

    R7 = {k4, <<"u_k4_en:~p">>, <<"m_k4_en:~p">>} = get(k4),
    R7 = get(k4, en),
    {k4, <<"u_k4_es:~p">>, <<"m_k4_es:~p">>} = get(k4, es),
    {k4, <<"u_k4_en:e">>, <<"m_k4_en:f">>} = get({k4, e, f}),
    {k4, <<"u_k4_es:g">>, <<"m_k4_es:h">>} = get({k4, g, [h]}, es),
    ok.


-endif.