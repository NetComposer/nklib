%% -------------------------------------------------------------------
%%
%% Copyright (c) 2014 Carlos Gonzalez Florido.  All Rights Reserved.
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

%% @doc Common library utility funcions
-module(nklib_gen_server).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([init/4, handle_call/5, handle_cast/4, handle_info/4, terminate/4, 
         code_change/5, handle_any/5]).
-include("nklib.hrl").


%% ===================================================================
%% Types
%% ===================================================================



%% ===================================================================
%% Public
%% =================================================================


%% @private
-spec init(term(), tuple(), pos_integer(), pos_integer()) ->
    {ok, tuple()}.

init(Arg, State, PosMod, PosUser) ->
    SubMod = element(PosMod, State),
    case SubMod:init(Arg) of
        {ok, User1} ->
            {ok, setelement(PosUser, State, User1)};
        {ok, User1, Timeout} ->
            {ok, setelement(PosUser, State, User1), Timeout};
        {stop, Reason} ->
            {stop, Reason};
        ignore ->
            ignore
    end.


%% @private
-spec handle_call(term(), {pid(), term()}, tuple(), pos_integer(), pos_integer()) ->
    {reply, term(), tuple()} |
    {reply, term(), tuple(), timeout() | hibernate} |
    {noreply, tuple()} |
    {noreply, tuple(), timeout() | hibernate} |
    {stop, term(), term(), tuple()} |
    {stop, term(), tuple()}.

handle_call(Msg, From, State, PosMod, PosUser) ->
    SubMod = element(PosMod, State),
    User = element(PosUser, State),
    case SubMod:handle_call(Msg, From, User) of
        {reply, Reply, User1} ->
            {reply, Reply, setelement(PosUser, State, User1)};
        {reply, Reply, User1, Timeout} ->
            {reply, Reply, setelement(PosUser, State, User1), Timeout};
        {noreply, User1} ->
            {noreply, setelement(PosUser, State, User1)};
        {noreply, User1, Timeout} ->
            {noreply, setelement(PosUser, State, User1), Timeout};
        {stop, Reason, User1} ->
            {reply, Reason, setelement(PosUser, State, User1)};
        {stop, Reason, Reply, User1} ->
            {stop, Reason, Reply, setelement(PosUser, State, User1)}
    end.


%% @private
-spec handle_cast(term(), tuple(), pos_integer(), pos_integer()) ->
    {noreply, tuple()} |
    {noreply, tuple(), timeout() | hibernate} |
    {stop, term(), tuple()}.

handle_cast(Msg, State, PosMod, PosUser) ->
    SubMod = element(PosMod, State),
    User = element(PosUser, State),
    case SubMod:handle_cast(Msg, User) of
        {noreply, User1} ->
            {noreply, setelement(PosUser, State, User1)};
        {noreply, User1, Timeout} ->
            {noreply, setelement(PosUser, State, User1), Timeout};
        {stop, Reason, User1} ->
            {reply, Reason, setelement(PosUser, State, User1)}
    end.


%% @private
-spec handle_info(term(), tuple(), pos_integer(), pos_integer()) ->
    {noreply, tuple()} |
    {noreply, tuple(), timeout() | hibernate} |
    {stop, term(), tuple()}.

handle_info(Msg, State, PosMod, PosUser) ->
    SubMod = element(PosMod, State),
    User = element(PosUser, State),
    case SubMod:handle_info(Msg, User) of
        {noreply, User1} ->
            {noreply, setelement(PosUser, State, User1)};
        {noreply, User1, Timeout} ->
            {noreply, setelement(PosUser, State, User1), Timeout};
        {stop, Reason, User1} ->
            {reply, Reason, setelement(PosUser, State, User1)}
    end.


-spec code_change(term()|{down, term()}, tuple(), term(), 
                  pos_integer(), pos_integer()) ->
    {ok, NewState :: term()} | {error, Reason :: term()}.

code_change(OldVsn, State, Extra, PosMod, PosUser) ->
    SubMod = element(PosMod, State),
    User = element(PosUser, State),
    case SubMod:code_change(OldVsn, User, Extra) of
        {ok, User1} ->
            {ok, setelement(PosUser, State, User1)};
        {error, Reason} ->
            {error, Reason}
    end.


%% @private
-spec terminate(term(), tuple(), pos_integer(), pos_integer()) ->
    any().

terminate(Reason, State, PosMod, PosUser) ->
    SubMod = element(PosMod, State),
    User = element(PosUser, State),
    SubMod:terminate(Reason, User).


%% @private
-spec handle_any(atom(), list(), tuple(), pos_integer(), pos_integer()) ->
    {ok, tuple()} |
    {ok, term(), tuple()} |
    {error, term(), tuple()} |
    {error, term(), term(), tuple()}.

handle_any(Fun, Args, State, PosMod, PosUser) ->
    SubMod = element(PosMod, State),
    User = element(PosUser, State),
    case apply(SubMod, Fun, Args++[User]) of
        {ok, User1} ->
            {ok, setelement(PosUser, State, User1)};
        {ok, Reply, User1} ->
            {ok, Reply, setelement(PosUser, State, User1)};
        {error, Error, User1} ->
            {error, Error, setelement(PosUser, State, User1)};
        {error, Error, Reply, User1} ->
            {error, Error, Reply, setelement(PosUser, State, User1)}
    end.



