%% -------------------------------------------------------------------
%%
%% Copyright (c) 2016 Carlos Gonzalez Florido.  All Rights Reserved.
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

%% @doc Link utilities
-module(nklib_links).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([get_pid/1]).
-export([new/0, add/4, get/2, update/3, remove/2, down/2, iter/2, fold/3]).
-export_type([links/0, links/1, id/0, data/0]).





%% ===================================================================
%% Types
%% ===================================================================

-type id() :: term().
-type data() :: term().
-type links() :: [{id(), data(), pid(), reference()}].
-type links(Type) :: [{Type, data(), pid(), reference()}].

%% ===================================================================
%% Public
%% ===================================================================

%% @doc Extracts Id, Data and Pid from different tuple combinations
-spec get_pid(nklib:proc_id()) ->
    pid()|undefined.

get_pid(Pid) when is_pid(Pid) -> Pid;
get_pid(Tuple) when is_tuple(Tuple) -> element(size(Tuple), Tuple);
get_pid(_Other) -> undefined.


%% @doc Add a link
-spec new() ->
    links().

new() ->
    [].



%% @doc Add a link
-spec add(id(), data(), pid(), links()) ->
    links().

add(Id, Data, Pid, Links) ->
    case lists:keymember(Id, 1, Links) of
        true -> 
            add(Id, Data, Pid, remove(Id, Links));
        false ->
            Mon = case is_pid(Pid) of
                true -> monitor(process, Pid);
                false -> undefined
            end,
            [{Id, Data, Pid, Mon}|Links]
    end.


%% @doc Gets a link
-spec get(id(), links()) ->
    {ok, data()} | not_found.

get(Id, Links) ->
    case lists:keyfind(Id, 1, Links) of
        {Id, Data, _Pid, _Mon} -> {ok, Data};
        false -> not_found
    end.


%% @doc Add a link
-spec update(id(), data(), links()) ->
    {ok, links()} | not_found.

update(Id, Data, Links) ->
    case lists:keytake(Id, 1, Links) of
        {value, {Id, _OldData, Pid, Mon}, Links2} -> 
            {ok, [{Id, Data, Pid, Mon}|Links2]};
        false ->
            not_found
    end.


%% @doc Removes a link
-spec remove(id(), links()) ->
    links().

remove(Id, Links) ->
    case lists:keyfind(Id, 1, Links) of
        {Id, _Data, _Pid, Mon} ->
            nklib_util:demonitor(Mon),
            lists:keydelete(Id, 1, Links);
        false ->
            Links
    end.


%% @doc Extracts a link with this pid
-spec down(pid(), links()) ->
    {ok, id(), data(), links()} | not_found.

down(Pid, Links) ->
    case lists:keytake(Pid, 3, Links) of
        {value, {Id, Data, Pid, Mon}, Links2} ->
            nklib_util:demonitor(Mon),
            {ok, Id, Data, Links2};
        false ->
            not_found
    end.


%% @doc Iterates over links
-spec iter(fun((id(), data()) -> ok), links()) ->
    ok.

iter(Fun, Links) ->
    lists:foreach(
        fun({Id, Data, _Pid, _Mon}) -> Fun(Id, Data) end, Links).


%% @doc Folds over links
-spec fold(fun((id(), data(), term()) -> term()), term(), links()) ->
    term().

fold(Fun, Acc0, Links) ->
    lists:foldl(
        fun({Id, Data, _Pid, _Mon}, Acc) -> Fun(Id, Data, Acc) end, 
        Acc0,
        Links).



%% ===================================================================
%% Useful templates
%% ===================================================================


% %% @private
% links_add(Id, Data, Pid, #state{links=Links}=State) ->
%     State#state{links=nklib_links:add(Id, Data, Pid, Links)}.


% %% @private
% links_get(Id, #state{links=Links}) ->
%     nklib_links:get(Id, Links).


% %% @private
% links_remove(Id, #state{links=Links}=State) ->
%     State#state{links=nklib_links:remove(Id, Links)}.


% %% @private
% links_down(Pid, #state{links=Links}=State) ->
%     case nklib_links:down(Pid, Links) of
%         {ok, Id, Data, Links2} -> {ok, Id, Data, State#state{links=Links2}};
%         not_found -> not_found
%     end.


% %% @private
% links_iter(Fun, #state{links=Links}) ->
%     nklib_links:iter(Fun, Links).


% %% @private
% links_fold(Fun, Acc, #state{links=Links}) ->
%     nklib_links:fold(Fun, Acc, Links).
