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

-export([init/4, init/5]).
-export([handle_call/5, handle_call/6, handle_call/7]).
-export([handle_cast/4, handle_cast/5, handle_cast/6]).
-export([handle_info/4, handle_info/5, handle_info/6]).
-export([terminate/4, terminate/5, code_change/5, code_change/6]).
-export([handle_any/5, handle_any/6]).
-include("nklib.hrl").


%% ===================================================================
%% Types
%% ===================================================================

-type reply() ::
    {reply, term(), tuple()} |
    {reply, term(), tuple(), timeout() | hibernate} |
    {noreply, tuple()} |
    {noreply, tuple(), timeout() | hibernate} |
    {stop, term(), term(), tuple()} |
    {stop, term(), tuple()}.


-type noreply() ::
    {noreply, tuple()} |
    {noreply, tuple(), timeout() | hibernate} |
    {stop, term(), tuple()}.




%% ===================================================================
%% Public
%% =================================================================


%% @private
-spec init(term(), tuple(), pos_integer(), pos_integer()) ->
    {ok, tuple()} | {ok, tuple(), timeout()|hibernate} |
    {stop, term()} | ignore.

init(Arg, State, PosMod, PosUser) ->
    init(init, Arg, State, PosMod, PosUser).


%% @private
-spec init(atom(), term(), tuple(), pos_integer(), pos_integer()) ->
    {ok, tuple()} | {ok, tuple(), timeout()|hibernate} |
    {stop, term()} | ignore.

init(Fun, Arg, State, PosMod, PosUser) ->
    SubMod = element(PosMod, State),
    case SubMod:Fun(Arg) of
        {ok, User1} ->
            {ok, setelement(PosUser, State, User1)};
        {ok, User1, Timeout} ->
            {ok, setelement(PosUser, State, User1), Timeout};
        {stop, Reason} ->
            {stop, Reason};
        ignore ->
            ignore
    end.


%% @private Default Fun and Timeout
-spec handle_call(term(), {pid(), term()}, tuple(), pos_integer(), pos_integer()) ->
    reply().

handle_call(Msg, From, State, PosMod, PosUser) ->
    handle_call(handle_call, Msg, From, State, PosMod, PosUser, undefined).


%% @private Default Timeout
-spec handle_call(atom(), term(), {pid(), term()}, tuple(), 
                  pos_integer(), pos_integer()) ->
    reply().

handle_call(Fun, Msg, From, State, PosMod, PosUser) ->
    handle_call(Fun, Msg, From, State, PosMod, PosUser, undefined).


%% @private
-spec handle_call(atom(), term(), {pid(), term()}, tuple(), 
                  pos_integer(), pos_integer(), pos_integer()) ->
    reply().

handle_call(Fun, Msg, From, State, PosMod, PosUser, PosTimeout) ->
    SubMod = element(PosMod, State),
    User = element(PosUser, State),
    case erlang:function_exported(SubMod, Fun, 3) of
        true ->
            proc_reply(SubMod:Fun(Msg, From, User), PosUser, PosTimeout, State);
        false ->
            {noreply, State}
    end.


%% @private
-spec handle_cast(term(), tuple(), pos_integer(), pos_integer()) ->
    noreply().

handle_cast(Msg, State, PosMod, PosUser) ->
    handle_cast(handle_cast, Msg, State, PosMod, PosUser, undefined).


%% @private
-spec handle_cast(atom(), term(), tuple(), pos_integer(), pos_integer()) ->
    noreply().

handle_cast(Fun, Msg, State, PosMod, PosUser) ->
    handle_cast(Fun, Msg, State, PosMod, PosUser, undefined).


%% @private
-spec handle_cast(atom(), term(), tuple(), pos_integer(), pos_integer(), pos_integer()) ->
    noreply().

handle_cast(Fun, Msg, State, PosMod, PosUser, PosTimeout) ->
    SubMod = element(PosMod, State),
    User = element(PosUser, State),
    case erlang:function_exported(SubMod, Fun, 2) of
        true ->
            proc_reply(SubMod:Fun(Msg, User), PosUser, PosTimeout, State);
        false ->
            {noreply, State}
    end.


%% @private
-spec handle_info(term(), tuple(), pos_integer(), pos_integer()) ->
    noreply().

handle_info(Msg, State, PosMod, PosUser) ->
    handle_info(handle_info, Msg, State, PosMod, PosUser, undefined).


%% @private
-spec handle_info(atom(), term(), tuple(), pos_integer(), pos_integer()) ->
    noreply().

handle_info(Fun, Msg, State, PosMod, PosUser) ->
    handle_info(Fun, Msg, State, PosMod, PosUser, undefined).


%% @private
-spec handle_info(atom(), term(), tuple(), pos_integer(), pos_integer(), pos_integer()) ->
    noreply().

handle_info(Fun, Msg, State, PosMod, PosUser, PosTimeout) ->
    SubMod = element(PosMod, State),
    User = element(PosUser, State),
    case erlang:function_exported(SubMod, Fun, 2) of
        true ->
            proc_reply(SubMod:Fun(Msg, User), PosUser, PosTimeout, State);
        false ->
            {noreply, State}
    end.


-spec code_change(term()|{down, term()}, tuple(), term(), 
                  pos_integer(), pos_integer()) ->
    {ok, NewState :: term()} | {error, Reason :: term()}.

code_change(OldVsn, State, Extra, PosMod, PosUser) ->
    code_change(code_change, OldVsn, State, Extra, PosMod, PosUser).


-spec code_change(atom(), term()|{down, term()}, tuple(), term(), 
                  pos_integer(), pos_integer()) ->
    {ok, NewState :: term()} | {error, Reason :: term()}.

code_change(Fun, OldVsn, State, Extra, PosMod, PosUser) ->
    SubMod = element(PosMod, State),
    User = element(PosUser, State),
    case erlang:function_exported(SubMod, Fun, 3) of
        true ->
            case SubMod:Fun(OldVsn, User, Extra) of
                {ok, User1} ->
                    {ok, setelement(PosUser, State, User1)};
                {error, Reason} ->
                    {error, Reason}
            end;
        false ->
            {ok, State}
    end.


%% @private
-spec terminate(term(), tuple(), pos_integer(), pos_integer()) ->
    any().

terminate(Reason, State, PosMod, PosUser) ->
    terminate(terminate, Reason, State, PosMod, PosUser).


%% @private
-spec terminate(atom(), term(), tuple(), pos_integer(), pos_integer()) ->
    any().

terminate(Fun, Reason, State, PosMod, PosUser) ->
    SubMod = element(PosMod, State),
    User = element(PosUser, State),
    case erlang:function_exported(SubMod, Fun, 2) of
        true -> 
            SubMod:Fun(Reason, User);
        false ->
            ok
    end.


%% @private
-spec handle_any(atom(), list(), tuple(), pos_integer(), pos_integer()) ->
    {ok, tuple()} |
    {ok, term(), tuple()} |
    {error, term(), tuple()} |
    {error, term(), term(), tuple()} |
    term().

handle_any(Fun, Args, State, PosMod, PosUser) ->
    handle_any(Fun, Args, State, PosMod, PosUser, undefined).


%% @private
-spec handle_any(atom(), list(), tuple(), pos_integer(), pos_integer(), pos_integer()) ->
    nklib_not_exported |
    {ok, tuple()} |
    {ok, term(), tuple()} |
    {error, term(), tuple()} |
    {error, term(), term(), tuple()} |
    term().

handle_any(Fun, Args, State, PosMod, PosUser, PosTimeout) ->
    SubMod = element(PosMod, State),
    User = element(PosUser, State),
    Args1 = Args++[User],
    case erlang:function_exported(SubMod, Fun, length(Args1)) of
        true ->
            proc_reply(apply(SubMod, Fun, Args1), PosUser, PosTimeout, State);
        false ->
            nklib_not_exported
    end.


%% @private
proc_reply(Term, PosUser, PosTimeout, State) ->
    case Term of
        {reply, Reply, User1} ->
            Timeout = case PosTimeout of
                undefined -> infinity;
                _ -> element(PosTimeout, State)
            end,
            {reply, Reply, setelement(PosUser, State, User1), Timeout};
        {reply, Reply, User1, Timeout1} ->
            {reply, Reply, setelement(PosUser, State, User1), Timeout1};
        {noreply, User1} ->
            Timeout = case PosTimeout of
                undefined -> infinity;
                _ -> element(PosTimeout, State)
            end,
            {noreply, setelement(PosUser, State, User1), Timeout};
        {noreply, User1, Timeout1} ->
            {noreply, setelement(PosUser, State, User1), Timeout1};
        {stop, Reason, User1} ->
            {stop, Reason, setelement(PosUser, State, User1)};
        {stop, Reason, Reply, User1} ->
            {stop, Reason, Reply, setelement(PosUser, State, User1)};
        {ok, User1} ->
            {ok, setelement(PosUser, State, User1)};
        {ok, Reply, User1} ->
            {ok, Reply, setelement(PosUser, State, User1)};
        {error, Error, User1} ->
            {error, Error, setelement(PosUser, State, User1)};
        {error, Error, Reply, User1} ->
            {error, Error, Reply, setelement(PosUser, State, User1)};
        {Class, User1} ->
            {Class, setelement(PosUser, State, User1)};
        {Class, Msg, User1} ->
            {Class, Msg, setelement(PosUser, State, User1)};
        Other ->
            Other
    end.





