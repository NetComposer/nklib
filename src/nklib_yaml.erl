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

%% @doc JSON Processing
-module(nklib_yaml).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([decode/1]).


%% ===================================================================
%% Types
%% ===================================================================




%% ===================================================================
%% Public
%% ===================================================================


%% @doc Decodes a YAML as a map
-spec decode(binary()|iolist()) ->
    [map()] | {error, {Txt::binary(), Line::integer(), Col::integer()}|undefined}.

decode(Term) ->
    try yamerl_constr:string(Term) of
        Body ->
            parse_decoded(Body, [])
    catch
        error:Error -> 
            lager:debug("Error decoding YAML: ~p", [Error]),
            {error, undefined};
        throw:
            {yamerl_exception, [
                {yamerl_parsing_error, error, Txt, Line, Col, _Code, _, _}
                |_]} ->
            {error, {list_to_binary(Txt), Line, Col}};
        throw:Error ->
            lager:debug("Error decoding YAML: ~p", [Error]),
            {error, undefined}
    end.


%% @private
parse_decoded([], Acc) ->
    lists:reverse(Acc);

parse_decoded([Term|Rest], Acc) ->
    Term2 = parse_decoded2(Term, []),
    parse_decoded(Rest, [Term2|Acc]).


%% @private
parse_decoded2([], Acc) ->
    maps:from_list(Acc);

parse_decoded2([{Key, [List1|_]=List2}|Rest], Acc) when is_list(List1) ->
    Values = lists:foldl(
        fun(Term, Acc2) -> [parse_decoded2(Term, [])|Acc2] end,
        [],
        List2
    ),
    parse_decoded2(Rest, [{list_to_binary(Key), Values}|Acc]);

parse_decoded2([{Key, [{_, _}|_]=List}|Rest], Acc) ->
    Values = parse_decoded2(List, []),
    parse_decoded2(Rest, [{list_to_binary(Key), Values}|Acc]);

parse_decoded2([{Key, Val}|Rest], Acc) ->
    Val2 = case is_list(Val) of
        true ->
            list_to_binary(Val);
        false ->
            Val
    end,
    parse_decoded2(Rest, [{list_to_binary(Key), Val2}|Acc]).



