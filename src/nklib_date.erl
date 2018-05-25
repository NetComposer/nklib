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

%% @doc NetComposer Standard Library
-module(nklib_date).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([to_3339/1]).

-include("nklib.hrl").


%% ===================================================================
%% Public
%% ===================================================================

%% @doc Normalizes any incoming value (see tests)
to_3339(Val) when is_integer(Val) ->
    Precision = case byte_size(integer_to_binary(abs(Val))) of
        Size when Size =< 10 ->
            0;
        Size when Size >= 11, Size =< 13 ->
            3;
        _ ->
            6
    end,
    D = jam:from_epoch(Val, Precision),
    {ok, list_to_binary(jam_iso8601:to_string(D))};

to_3339(Val) when is_binary(Val); is_list(Val) ->
    case catch jam_iso8601:parse(Val) of
        undefined ->
            error;
        {'EXIT, _'} ->
            error;
        List ->
            D = jam:normalize(jam:compile(List)),
            {ok, list_to_binary(jam_iso8601:to_string(D))}
    end.



%% ===================================================================
%% EUnit tests
%% ===================================================================

%-define(TEST, 1).
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").


dates_test() ->
    G1971 = nklib_util:gmt_to_timestamp({{1971, 1, 1}, {0,0,0}}),
    G1980 = nklib_util:gmt_to_timestamp({{1980, 1, 1}, {0,0,0}}),
    G2018 = nklib_util:gmt_to_timestamp({{2018, 1, 1}, {0,0,0}}),
    G2100 = nklib_util:gmt_to_timestamp({{2100, 1, 1}, {0,0,0}}),

    {ok, <<"1971-01-01T00:00:00Z">>} = to_3339(G1971),
    {ok, <<"1971-01-01T00:00:00.001Z">>} = to_3339(G1971 * 1000 + 1),
    {ok, <<"1971-01-01T00:00:00.000001Z">>} = to_3339(G1971 * 1000 * 1000 + 1),

    {ok, <<"1980-01-01T00:00:00Z">>} = to_3339(G1980),
    {ok, <<"1980-01-01T00:00:00.001Z">>} = to_3339(G1980 * 1000 + 1),
    {ok, <<"1980-01-01T00:00:00.000001Z">>} = to_3339(G1980 * 1000 * 1000 + 1),

    {ok, <<"2018-01-01T00:00:00Z">>} = to_3339(G2018),
    {ok, <<"2018-01-01T00:00:00.001Z">>} = to_3339(G2018 * 1000 +  1),
    {ok, <<"2018-01-01T00:00:00.000001Z">>} = to_3339(G2018 * 1000 * 1000 + 1),

    {ok, <<"2100-01-01T00:00:00Z">>} = to_3339(G2100),
    {ok, <<"2100-01-01T00:00:00.001Z">>} = to_3339(G2100 * 1000 + 1),
    {ok, <<"2100-01-01T00:00:00.000001Z">>} = to_3339(G2100 * 1000 * 1000 + 1),

    {ok, <<"1980-01-01T00:00:00Z">>} = to_3339("1980-01-01T00:00:00Z"),
    {ok, <<"1980-01-01T00:00:00.001Z">>} = to_3339("1980-01-01T00:00:00.001Z"),
    {ok, <<"1980-01-01T00:00:00.000001Z">>} = to_3339("1980-01-01T00:00:00.000001Z"),
    ok.


-endif.




