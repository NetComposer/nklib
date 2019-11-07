%% -------------------------------------------------------------------
%%
%% Copyright (c) 2019 Carlos Gonzalez Florido.  All Rights Reserved.
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

%% @private Fast CSV Parser
-module(nklib_parse_csv).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([csv/1, test1/0]).


%% ===================================================================
%% Public
%% ===================================================================

%% @private
csv(String) ->
    String2 = strip(nklib_util:to_list(String)),
    csv(String2, 1, false, [], [], [], []).


%% ===================================================================
%% Private
%% ===================================================================



csv([$\r, $\n | Rest], Line, false, Letters, Words, Records, Fields) ->
    csv([$\n|Rest], Line, false, Letters, Words,  Records, Fields);

% Header, end of line, not quoted
csv([$\n | Rest], 1, false, Letters, [], [], Fields) ->
    Field = list_to_binary(lists:reverse(Letters)),
    Fields2 = [Field|Fields],
    Fields3 = lists:reverse(Fields2),
    csv(strip(Rest), 2, false, [], [], [], Fields3);

% Header, separator, not quoted
csv([$,|Rest], 1, false, Letters, [], [], Fields) ->
    Field = list_to_binary(lists:reverse(Letters)),
    Fields2 = [Field|Fields],
    csv(strip(Rest), 1, false, [], [], [], Fields2);

% Record, end of line, not quoted
csv([$\n | Rest], Line, false, [], [], Records, Fields) ->
    csv(strip(Rest), Line+1, false, [], [], Records, Fields);

csv([$\n | Rest], Line, false, Letters, Words, Records, Fields) ->
    Word = list_to_binary(lists:reverse(Letters)),
    Words2 = lists:reverse([Word|Words]),
    case catch lists:zip(Fields, Words2) of
        {'EXIT', _} ->
            lager:error("NKLOG F1: ~p W: ~p", [Fields, Words2]),
            {error, {csv_parser_error, {invalid_fields, Line}}};
        Zipped ->
            Record = maps:from_list(Zipped),
            csv(strip(Rest), Line+1, false, [], [], [Record|Records], Fields)
    end;

% Record, end of file, not quoted
csv([], _Line, false, [], [], Records, _Fields) ->
    {ok, lists:reverse(Records)};

csv([], Line, false, Letters, Words, Records, Fields) ->
    Word = list_to_binary(lists:reverse(Letters)),
    Words2 = lists:reverse([Word|Words]),
    %lager:error("NKLOG F2 ~p W2 ~p", [Letters, Words]),
    case catch lists:zip(Fields, Words2) of
        {'EXIT', _} ->
            lager:error("NKLOG F2: ~p W: ~p", [Fields, Words2]),
            {error, {csv_parser_error, {invalid_fields, Line}}};
        Zipped ->
            Record = maps:from_list(Zipped),
            {ok, lists:reverse([Record|Records])}
    end;

csv([], _Line, {true, _, QuoteLine}, _Letters, _Words, _Records, _Fields) ->
    {error, {csv_parser_error, {unfinished_quote, QuoteLine}}};

% Separator, record, not quoted
csv([$,|Rest], Line, false, Letters, Words, Records, Fields) ->
    Word = list_to_binary(lists:reverse(Letters)),
    Words2 = [Word|Words],
    csv(strip(Rest), Line, false, [], Words2, Records, Fields);

% Escaped "
csv([$", $"|Rest], Line, false, Letters, Words, Records, Fields) ->
    csv(Rest, Line, false, [$"|Letters], Words, Records, Fields);


% Found " in not quoted -> quoted
csv([$"|Rest], Line, false, Letters, Words, Records, Fields) ->
    csv(Rest, Line, {true, $", Line}, Letters, Words, Records, Fields);

% Found " in quoted -> not quoted
csv([$"|Rest], Line, {true, $", _}, Letters, Words, Records, Fields) ->
    csv(strip(Rest), Line, false, Letters, Words, Records, Fields);

% Other thing -> to letter
csv([Ch|Rest], Line, IsQuoted, Letters, Words, Records, Fields) ->
    csv(Rest, Line, IsQuoted, [Ch|Letters], Words, Records, Fields).


%% @private Strip white space
strip([32|Rest]) -> strip(Rest);
strip([9|Rest]) -> strip(Rest);
strip(Rest) -> Rest.




%% ===================================================================
%% EUnit tests
%% ===================================================================


test1() ->
    Data1 = <<"h1, \"header 2,2\", h 3\r\nd1,d2,d3
        data\"\"A, \"data B,\nB\", data C
        ,,">>,
    {ok, Res1} = csv(Data1),
    [
        #{<<"h1">>:=<<"d1">>, <<"header 2,2">>:=<<"d2">>, <<"h 3">>:=<<"d3">>},
        #{<<"h1">>:=<<"data\"A">>, <<"header 2,2">>:=<<"data B,\nB">>, <<"h 3">>:=<<"data C">>},
        #{<<"h1">>:=<<"">>, <<"header 2,2">>:=<<"">>, <<"h 3">>:=<<"">>}
    ] = Res1,

    % Blank lines
    Data2 = <<"h1, h2, h3\nd1,d2,d3\n\r\n\n">>,
    {ok, Res2} = csv(Data2),
    [#{<<"h1">>:=<<"d1">>, <<"h2">>:=<<"d2">>, <<"h3">>:=<<"d3">>}] = Res2,

    % Invalid fields
    Data3 = <<"h1, h2, h3\nd1,d2,d3\nd1,d2">>,
    {error,{csv_parser_error,{invalid_fields,3}}} = csv(Data3),

    % Non finished quote
    Data4 = <<"h1, h2, h3\nd1,\"d2,d3">>,
    {error,{csv_parser_error,{unfinished_quote,2}}} = csv(Data4),

    % No data
    Data5 = <<"h1, h2, h3\n\n">>,
    {ok, []} = csv(Data5),
    ok.


-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

csv_test() ->
    test1().

-endif.

