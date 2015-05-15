
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

%% @doc Generic registration data type
%%
%% This module implements a datatype to manage pids registering to terms.
%% You can register and unregister a pid() to any regterm().
%% Later on, you can find the regterm()'s registered by a process, or the
%% processes that have registered a regterm().
%%
%% For each new pid(), a monitor is started. On receiving any 
%% {'DOWN', _Ref, process, Pid, _Reason} you must call down/2 to see if this
%% pid belongs to a registered process.

-module(nklib_reglist).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([new/0, reg/3, unreg/3, unreg_all/2, down/2]).
-export([find_pids/2, find_regs/2, get_all/1]).
-export_type([regterm/0, reglist/1]).

-type regterm() :: term().

-type reglist(RegTerm) ::
    {reglist, dict:map(RegTerm, [pid()]), dict:map(pid(), {reference(), [RegTerm]})}.



%% ===================================================================
%% Public
%% ===================================================================

%% @doc Initializes the data type
-spec new() ->
    reglist(regterm()).

new() ->
    {reglist, dict:new(), dict:new()}.


%% @doc Register a RegTerm for the process having Pid
-spec reg(regterm(), pid(), reglist(regterm())) ->
    reglist(regterm()).

reg(RegTerm, Pid, {reglist, Regs, Pids}) when is_pid(Pid) ->
    RegValue = case dict:find(RegTerm, Regs) of
        error ->
            [Pid];
        {ok, PidList} ->
            case lists:member(Pid, PidList) of
                true -> PidList;
                false -> [Pid|PidList]
            end
    end,
    Regs1 = dict:store(RegTerm, RegValue, Regs),
    PidValue = case dict:find(Pid, Pids) of
        error ->
            Mon = monitor(process, Pid),
            {Mon, [RegTerm]};
        {ok, {Mon, RegsList}} ->
            case lists:member(RegTerm, RegsList) of
                true -> {Mon, RegsList};
                false -> {Mon, [RegTerm|RegsList]}
            end
    end,
    Pids1 = dict:store(Pid, PidValue, Pids),
    {reglist, Regs1, Pids1}.


%% @doc Unregisters a RegTerm for the process having Pid
-spec unreg(regterm(), pid(), reglist(regterm())) ->
    reglist(regterm()).

unreg(RegTerm, Pid, {reglist, Regs, Pids}) when is_pid(Pid) ->
    case dict:find(RegTerm, Regs) of
        error ->
            {reglist, Regs, Pids};
        {ok, PidList} ->
            case lists:member(Pid, PidList) of
                false ->
                    {reglist, Regs, Pids};
                true ->
                    Regs1 = case PidList -- [Pid] of
                        [] ->
                            dict:erase(RegTerm, Regs);
                        PidList1 ->
                            dict:store(RegTerm, PidList1, Regs)
                    end,
                    {Mon, RegsList} = dict:fetch(Pid, Pids),
                    Pids1 = case RegsList -- [RegTerm] of
                        [] ->
                            demonitor(Mon, [flush]),
                            dict:erase(Pid, Pids);
                        RegsList1 ->
                            dict:store(Pid, {Mon, RegsList1}, Pids)
                    end,
                    {reglist, Regs1, Pids1}
            end
    end.


%% @doc Unregisters all processes registered for this RegTerm
-spec unreg_all(regterm(), reglist(regterm())) ->
    reglist(regterm()).

unreg_all(RegTerm, {reglist, _, _}=RegList) ->
    lists:foldl(
        fun(Pid, Acc) -> unreg(RegTerm, Pid, Acc) end,
        RegList,
        find_pids(RegTerm, RegList)
     ).


%% Marks this Pid as down, unregistering all previous registrations
-spec down(pid(), reglist(regterm())) ->
    {true, reglist(regterm())} | false.

down(Pid, {reglist, Regs, Pids}) when is_pid(Pid) ->
    case dict:find(Pid, Pids) of
        {ok, {_, RegsList}} ->
            RegsList1 = lists:foldl(
                fun(RegTerm, Acc) -> unreg(RegTerm, Pid, Acc) end,
                {reglist, Regs, Pids},
                RegsList),
            {true, RegsList1};
        error ->
            false
    end.


%% @doc Finds all processes that have registered this RegTerm
-spec find_pids(regterm(), reglist(regterm())) ->
    [pid()].

find_pids(RegTerm, {reglist, Regs, _Pids}) ->
    case dict:find(RegTerm, Regs) of
        {ok, PidList}  -> PidList;
        error -> []
    end.


%% @doc Finds all RegTerms that this process have registered
-spec find_regs(pid(), reglist(regterm())) ->
    [regterm()].

find_regs(Pid, {reglist, _Regs, Pids}) when is_pid(Pid) ->
    case dict:find(Pid, Pids) of
        {ok, {_Mon, RegsList}}  -> RegsList;
        error -> []
    end.


%% @doc Gets all registered processes
-spec get_all(reglist(regterm())) ->
    [{regterm(), [pid()]}].

get_all({reglist, Regs, _Pids}) ->
    dict:to_list(Regs).




%% ===================================================================
%% EUnit tests
%% ===================================================================

-define(TEST, a).
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

a_test() ->
    R1 = new(),
    P1 = self(),
    [] = find_pids(any, R1),
    [] = find_regs(P1, R1),

    R2 = reg(t1, P1, R1),
    [t1] = find_regs(P1, R2),
    [] = find_pids(any, R2),
    [P1] = find_pids(t1, R2),
    
    R3 = reg(t1, P1, R2),
    [t1] = find_regs(P1, R3),
    [P1] = find_pids(t1, R3),

    R4 = reg(t2, P1, R3),
    [t1,t2] = lists:sort(find_regs(P1, R4)),
    [P1] = find_pids(t1, R4),    
    [P1] = find_pids(t2, R4),    

    R5 = unreg(t1, P1, R4),
    [t2] = find_regs(P1, R5),
    [] = find_pids(t1, R5),    
    [P1] = find_pids(t2, R5),    
    R5 = unreg(t1, P1, R4),

    R1 = unreg(t2, P1, R5),
    ok.

b_test() ->
    R1 = new(),
    P1 = self(),

    R2 = reg(t3, P1, R1),
    R3 = reg(t4, P1, R2),
    P2 = spawn(fun() -> ok end),
    R4 = reg(t4, P2, R3),
    R5 = reg(t5, P2, R4),
    [P1] = find_pids(t3, R5),
    [P2, P1] = find_pids(t4, R5),
    [P2] = find_pids(t5, R5),
    [t3,t4] = lists:sort(find_regs(P1, R5)),
    [t4,t5] = lists:sort(find_regs(P2, R5)),
    receive {'DOWN', _, process, P2, normal} -> ok end,
    {true, R6} = down(P2, R5),
    [P1] = find_pids(t3, R6),
    [P1] = find_pids(t4, R6),
    [] = find_pids(t5, R6),
    [t3,t4] = lists:sort(find_regs(P1, R6)),
    [] = find_regs(P2, R6),

    {true, R1} = down(P1, R6),
    ok.

c_test() ->
    R1 = new(),
    P1 = self(),

    R2 = reg(t5, P1, R1),
    R3 = reg(t6, P1, R2),

    P2 = spawn(fun() -> ok end),
    R4 = reg(t6, P2, R3),
    R5 = reg(t7, P2, R4),

    P3 = spawn(fun() -> ok end),
    R6 = reg(t7, P3, R5),
    R7 = reg(t8, P3, R6),

    [P1] = find_pids(t5, R7),
    [P2, P1] = find_pids(t6, R7),
    [P3, P2] = find_pids(t7, R7),
    [P3] = find_pids(t8, R7),
    [t5, t6] = lists:sort(find_regs(P1, R7)),
    [t6, t7] = lists:sort(find_regs(P2, R7)),
    [t7, t8] = lists:sort(find_regs(P3, R7)),

    R8 = unreg_all(t6, R7),
    [P1] = find_pids(t5, R8),
    [] = find_pids(t6, R8),
    [P3, P2] = find_pids(t7, R8),
    [P3] = find_pids(t8, R8),
    [t5] = lists:sort(find_regs(P1, R8)),
    [t7] = lists:sort(find_regs(P2, R8)),
    [t7, t8] = lists:sort(find_regs(P3, R8)),

    R9 = unreg_all(t7, R8),
    [P1] = find_pids(t5, R9),
    [] = find_pids(t6, R9),
    [] = find_pids(t7, R9),
    [P3] = find_pids(t8, R9),
    [t5] = lists:sort(find_regs(P1, R9)),
    [] = lists:sort(find_regs(P2, R9)),
    [t8] = lists:sort(find_regs(P3, R9)),

    R10 = unreg_all(t5, R9),
    R1 = unreg_all(t8, R10),
    ok.

-endif.






















