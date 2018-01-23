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

%% @doc Common library utility funcions
-module(nklib_gen_server).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([init/4, init/5]).
-export([handle_call/5, handle_call/6]).
-export([handle_cast/4, handle_cast/5]).
-export([handle_info/4, handle_info/5]).
-export([terminate/4, terminate/5, code_change/5, code_change/6]).
-export([handle_any/5]).
-include("nklib.hrl").


%% ===================================================================
%% Types
%% ===================================================================

-type reply() ::
    {reply, term(), state()} |
    {reply, term(), state(), timeout() | hibernate} |
    {noreply, state()} |
    {noreply, state(), timeout() | hibernate} |
    {stop, Reason::term(), Reply::term(), state()} |
    {stop, Reason::term(), state()}.


-type noreply() ::
    {noreply, tuple()} |
    {noreply, tuple(), timeout() | hibernate} |
    {stop, Reason::term(), tuple()}.


-type continue() ::
    {continue, state()}.


-type state() :: 
    tuple().

-type from() :: {pid(), reference()}.


%% ===================================================================
%% Public
%% =================================================================


%% @private
-spec init(term(), state(), pos_integer(), pos_integer()) ->
    {ok, state()} | {ok, state(), timeout()|hibernate} |
    {stop, term()} | ignore.

init(Arg, State, PosMod, PosUser) ->
    init(init, Arg, State, PosMod, PosUser).


%% @private
-spec init(atom(), term(), state(), pos_integer(), pos_integer()) ->
    {ok, state()} | {ok, state(), timeout()|hibernate} |
    {stop, term()} | ignore.

init(Fun, Arg, State, PosMod, PosUser) ->
    Mod = element(PosMod, State),
    case Mod:Fun(Arg) of
        {ok, User} ->
            {ok, setelement(PosUser, State, User)};
        {ok, User, Timeout} ->
            {ok, setelement(PosUser, State, User), Timeout};
        {stop, Reason} ->
            {stop, Reason};
        ignore ->
            ignore
    end.


%% @private Default Fun and Timeout
-spec handle_call(term(), from(), state(), pos_integer(), pos_integer()) ->
    reply().

handle_call(Msg, From, State, PosMod, PosUser) ->
    handle_call(handle_call, Msg, From, State, PosMod, PosUser).


%% @private Default Timeout
-spec handle_call(atom(), term(), from(), state(), pos_integer(), pos_integer()) ->
    reply().

handle_call(Fun, Msg, From, State, PosMod, PosUser) ->
    Mod = element(PosMod, State),
    User = element(PosUser, State),
    case erlang:function_exported(Mod, Fun, 3) of
        true ->
            proc_reply(Mod:Fun(Msg, From, User), PosUser, State);
        false ->
            {noreply, State}
    end.


%% @private
-spec handle_cast(term(), state(), pos_integer(), pos_integer()) ->
    noreply().

handle_cast(Msg, State, PosMod, PosUser) ->
    handle_cast(handle_cast, Msg, State, PosMod, PosUser).


%% @private
-spec handle_cast(atom(), term(), state(), pos_integer(), pos_integer()) ->
    noreply().

handle_cast(Fun, Msg, State, PosMod, PosUser) ->
    Mod = element(PosMod, State),
    User = element(PosUser, State),
    case erlang:function_exported(Mod, Fun, 2) of
        true ->
            proc_noreply(Mod:Fun(Msg, User), PosUser, State);
        false ->
            {noreply, State}
    end.


%% @private
-spec handle_info(term(), state(), pos_integer(), pos_integer()) ->
    noreply() | continue() | term().

handle_info(Msg, State, PosMod, PosUser) ->
    handle_info(handle_info, Msg, State, PosMod, PosUser).


%% @private
-spec handle_info(atom(), term(), state(), pos_integer(), pos_integer()) ->
    noreply().

handle_info(Fun, Msg, State, PosMod, PosUser) ->
    Mod = element(PosMod, State),
    User = element(PosUser, State),
    case erlang:function_exported(Mod, Fun, 2) of
        true ->
            proc_noreply(Mod:Fun(Msg, User), PosUser, State);
        false ->
            {noreply, State}
    end.


-spec code_change(term()|{down, term()}, state(), term(), 
                  pos_integer(), pos_integer()) ->
    {ok, NewState :: term()} | {error, Reason :: term()}.

code_change(OldVsn, State, Extra, PosMod, PosUser) ->
    code_change(code_change, OldVsn, State, Extra, PosMod, PosUser).


-spec code_change(atom(), term()|{down, term()}, state(), term(), 
                  pos_integer(), pos_integer()) ->
    {ok, NewState :: term()} | {error, Reason :: term()}.

code_change(Fun, OldVsn, State, Extra, PosMod, PosUser) ->
    Mod = element(PosMod, State),
    User = element(PosUser, State),
    case erlang:function_exported(Mod, Fun, 3) of
        true ->
            case Mod:Fun(OldVsn, User, Extra) of
                {ok, User} ->
                    {ok, setelement(PosUser, State, User)};
                {continue, State2} ->
                    {ok, State2};
                {error, Reason} ->
                    {error, Reason}
            end;
        false ->
            {ok, State}
    end.


%% @private
-spec terminate(term(), state(), pos_integer(), pos_integer()) ->
    any().

terminate(Reason, State, PosMod, PosUser) ->
    terminate(terminate, Reason, State, PosMod, PosUser).


%% @private
-spec terminate(atom(), term(), state(), pos_integer(), pos_integer()) ->
    any().

terminate(Fun, Reason, State, PosMod, PosUser) ->
    Mod = element(PosMod, State),
    User = element(PosUser, State),
    case erlang:function_exported(Mod, Fun, 2) of
        true -> 
            Mod:Fun(Reason, User);
        false ->
            ok
    end.


%% @private
-spec handle_any(atom(), list(), state(), pos_integer(), pos_integer()) ->
    nklib_not_exported | continue() | tuple() | term().

handle_any(Fun, Args, State, PosMod, PosUser) ->
    Mod = element(PosMod, State),
    User = element(PosUser, State),
    Args2 = Args ++ [User],
    case erlang:function_exported(Mod, Fun, length(Args2)) of
        true ->
            Reply = apply(Mod, Fun, Args2),
            % lager:error("Handle: ~p, ~p, ~p: ~p", [Mod, Fun, Args2, Reply]),
            proc_any(Reply, PosUser, State);
        false ->
            nklib_not_exported
    end.


%% @private
-spec proc_reply(term(), pos_integer(), state()) ->
    reply().

proc_reply({reply, Reply, User}, Pos, State) ->
    {reply, Reply, setelement(Pos, State, User), infinity};

proc_reply({reply, Reply, User, Timeout}, Pos, State) ->
    {reply, Reply, setelement(Pos, State, User), Timeout};

proc_reply({stop, Reason, Reply, User}, Pos, State) ->
    {stop, Reason, Reply, setelement(Pos, State, User)};

proc_reply(Term, Pos, State) ->
    proc_noreply(Term, Pos, State).


%% @private
-spec proc_noreply(term(), pos_integer(), state()) ->
    noreply().

proc_noreply({noreply, User}, Pos, State) ->
    {noreply, setelement(Pos, State, User), infinity};

proc_noreply({noreply, User, Timeout}, Pos, State) ->
    {noreply, setelement(Pos, State, User), Timeout};

proc_noreply({stop, Reason, User}, Pos, State) ->
    {stop, Reason, setelement(Pos, State, User)};

proc_noreply(continue, _Pos, State) ->
    {noreply, State};

proc_noreply({continue, List}, Pos, State) when is_list(List) ->
    User = lists:last(List),
    {noreply, setelement(Pos, State, User)}.


%% @private
-spec proc_any(term(), integer(), state()) ->
    continue() | tuple() | term().

proc_any(continue, _Pos, State) ->
    {continue, State};

proc_any({continue, List}, Pos, State) when is_list(List) ->
    User = lists:last(List),
    {continue, setelement(Pos, State, User)};

proc_any(Term, Pos, State) when is_tuple(Term) ->
    % Return the same tuple, but last element is updated with the full state
    User = element(size(Term), Term),              
    State2 = setelement(Pos, State, User),
    setelement(size(Term), Term, State2);

proc_any(Term, _Pos, _State) ->
    Term.


