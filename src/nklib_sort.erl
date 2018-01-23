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

%% @doc Sorting of dependant elements
-module(nklib_sort).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([top_sort/1]).


%% ===================================================================
%% Public
%% =================================================================


%% @doc Sortes a lists of elements with dependencies, so that no element is
%% placed before any of its dependencies
-spec top_sort([{term(), [term()]}]) ->
    {ok, [term()]} | {error, {circular_dependencies, [term()]}}.

top_sort(Library) ->
    Digraph = digraph:new(),
    try
        topsort_insert(Library, Digraph),
        case digraph_utils:topsort(Digraph) of
            false ->
                Vertices = digraph:vertices(Digraph),
                Circular = top_sort_get_circular(Vertices, Digraph),
                {error, {circular_dependencies, Circular}};
            DepList ->
                {ok, DepList}
        end
    after
        true = digraph:delete(Digraph)
    end.



%% ===================================================================
%% Internal
%% =================================================================


%% @private
topsort_insert([], _Digraph) ->
    ok;

topsort_insert([{Name, Deps}|Rest], Digraph) ->
    digraph:add_vertex(Digraph, Name),
    lists:foreach(
        fun(Dep) -> 
            case Dep of
                Name ->
                    ok;
                _ ->
                    digraph:add_vertex(Digraph, Dep),
                    digraph:add_edge(Digraph, Dep, Name)
            end
        end,
        Deps),
    topsort_insert(Rest, Digraph).


%% @private
top_sort_get_circular([], _Digraph) ->
    [];

top_sort_get_circular([Vertice|Rest], Digraph) ->
    case digraph:get_short_cycle(Digraph, Vertice) of
        false ->
            top_sort_get_circular(Rest, Digraph);
        Vs ->
            lists:usort(Vs)
    end.






%% ===================================================================
%% EUnit tests
%% ===================================================================

% -define(TEST, 1).
% -compile([export_all]).
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").


ok_test() ->
    {ok, 
        [std,synopsys,ieee,dware,dw02,dw05,gtech,dw01,dw03,dw04,ramlib,
         std_cell_lib,des_system_lib,dw06,dw07]} = 
        top_sort(lib1()).

fail_test() ->
    {error, {circular_dependencies,[dw01,dw04]}} = top_sort(lib2()).


lib1() -> 
        [{des_system_lib,   [std, synopsys, std_cell_lib, des_system_lib, dw02, dw01, ramlib, ieee]},
         {dw01,             [ieee, dw01, dware, gtech]},
         {dw02,             [ieee, dw02, dware]},
         {dw03,             [std, synopsys, dware, dw03, dw02, dw01, ieee, gtech]},
         {dw04,             [dw04, ieee, dw01, dware, gtech]},
         {dw05,             [dw05, ieee, dware]},
         {dw06,             [dw06, ieee, dware]},
         {dw07,             [ieee, dware]},
         {dware,            [ieee, dware]},
         {gtech,            [ieee, gtech]},
         {ramlib,           [std, ieee]},
         {std_cell_lib,     [ieee, std_cell_lib]},
         {synopsys,         []}].
 
lib2() ->
        [{des_system_lib,   [std, synopsys, std_cell_lib, des_system_lib, dw02, dw01, ramlib, ieee]},
         {dw01,             [ieee, dw01, dw04, dware, gtech]},
         {dw02,             [ieee, dw02, dware]},
         {dw03,             [std, synopsys, dware, dw03, dw02, dw01, ieee, gtech]},
         {dw04,             [dw04, ieee, dw01, dware, gtech]},
         {dw05,             [dw05, ieee, dware]},
         {dw06,             [dw06, ieee, dware]},
         {dw07,             [ieee, dware]},
         {dware,            [ieee, dware]},
         {gtech,            [ieee, gtech]},
         {ramlib,           [std, ieee]},
         {std_cell_lib,     [ieee, std_cell_lib]},
         {synopsys,         []}].
 
 -endif.