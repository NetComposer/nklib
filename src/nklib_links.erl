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

%% @doc Link utilities
-module(nklib_links).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([get_pid/1]).
-export([new/0, add/2, add/3, add/4, get_value/2, update_value/3]).
-export([remove/2, is_empty/1, down/2, iter/2, iter_values/2, fold/3, fold_values/3]).
-export_type([links/0, data/0]).

-include("nklib.hrl").

%% ===================================================================
%% Types
%% ===================================================================

-type link() :: nklib:link().
-type data() :: term().
-type links() :: [{link(), data()|'$none', reference()|undefined}].


%% ===================================================================
%% Public
%% ===================================================================



%% @private
-spec get_pid(nklib:link()) ->
    pid() | undefined.

get_pid(Tuple) when is_tuple(Tuple) -> get_pid(element(size(Tuple), Tuple));
get_pid(Pid) when is_pid(Pid) -> Pid;
get_pid(_Term) -> undefined.


%% @doc Add a link
-spec new() ->
    links().

new() ->
    [].


%% @doc Add a link
-spec add(link(), links()) ->
    links().

add(Link, Links) ->
    add(Link, '$none', get_pid(Link), Links).


%% @doc Add a link
-spec add(link(), data(), links()) ->
    links().

add(Link, Data, Links) ->
    add(Link, Data, get_pid(Link), Links).


%% @doc Add a link
-spec add(link(), data(), pid(), links()) ->
    links().

add(Link, Data, Pid, Links) ->
    case lists:keymember(Link, 1, Links) of
        true -> 
            add(Link, Data, Pid, remove(Link, Links));
        false ->
            Mon = case is_pid(Pid) of
                true -> monitor(process, Pid);
                false -> undefined
            end,
            [{Link, Data, Mon}|Links]
    end.


%% @doc Gets a link
-spec get_value(link(), links()) ->
    {ok, data()} | not_found.

get_value(Link, Links) ->
    case lists:keyfind(Link, 1, Links) of
        {Link, Data, _Mon} -> {ok, Data};
        false -> not_found
    end.


%% @doc Add a link
-spec update_value(link(), data(), links()) ->
    {ok, links()} | not_found.

update_value(Link, Data, Links) ->
    case lists:keytake(Link, 1, Links) of
        {value, {Link, _OldData, Mon}, Links2} -> 
            {ok, [{Link, Data, Mon}|Links2]};
        false ->
            not_found
    end.


%% @doc Removes a link
-spec remove(link(), links()) ->
    links().

remove(Link, Links) ->
    case lists:keytake(Link, 1, Links) of
        {value, {Link, _Data, Mon}, Links2} ->
            nklib_util:demonitor(Mon),
            Links2;
        false ->
            Links
    end.


%% @doc Removes a link
-spec is_empty(links()) ->
    boolean().

is_empty([]) -> true;
is_empty(_) -> false.


%% @doc Extracts a link with this pid
-spec down(reference(), links()) ->
    {ok, link(), data(), links()} | not_found.

down(Mon, Links) ->
    case lists:keytake(Mon, 3, Links) of
        {value, {Link, Data, Mon}, Links2} ->
            {ok, Link, Data, Links2};
        false ->
            not_found
    end.


%% @doc Iterates over links
-spec iter(fun((link()) -> ok), links()) ->
    ok.

iter(Fun, Links) ->
    lists:foreach(
        fun({Link, _Data, _Mon}) -> Fun(Link) end, Links).


%% @doc Iterates over links
-spec iter_values(fun((link(), data()) -> ok), links()) ->
    ok.

iter_values(Fun, Links) ->
    lists:foreach(
        fun({Link, Data, _Mon}) -> Fun(Link, Data) end, Links).



%% @doc Folds over links
-spec fold(fun((link(), term()) -> term()), term(), links()) ->
    term().

fold(Fun, Acc0, Links) ->
    lists:foldl(
        fun({Link, _Data, _Mon}, Acc) -> Fun(Link, Acc) end, 
        Acc0,
        Links).


%% @doc Folds over links
-spec fold_values(fun((link(), data(), term()) -> term()), term(), links()) ->
    term().

fold_values(Fun, Acc0, Links) ->
    lists:foldl(
        fun({Link, Data, _Mon}, Acc) -> Fun(Link, Data, Acc) end, 
        Acc0,
        Links).
