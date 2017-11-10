%% -------------------------------------------------------------------
%%
%% Copyright (c) 2017 Carlos Gonzalez Florido.  All Rights Reserved.
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
%%

%% @doc Simple throttling management
-module(nklib_throttle).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([get_time/1, incr/2, get_counters/2]).
-export([test/0]).
-export_type([time_key/0, counters/0]).


%% ===================================================================
%% Types
%% ===================================================================

-type time_key() :: secs | secs5 | mins | mins5 | mins15 | hours | days | months | years.

-type time() :: nklib_util:l_timestamp().

-type counters() :: #{time_key() => [{time(), Counter::integer()}]}.



%% ===================================================================
%% Public
%% ===================================================================

%% @doc Get a time series
-spec get_time([time_key()]) ->
    [{time_key(), integer()}].

get_time(TimeKeys) ->
    Now = timestamp(),
    get_time(TimeKeys, Now, []).


%% @doc
-spec incr([time_key()], counters()) ->
    counters().

incr(TimeKeys, Counters) ->
    TimeList = get_time(TimeKeys),
    add_counters(TimeList, Counters).


%% @private
add_counters([], Counters) ->
    Counters;

add_counters([{Key, Time}|Rest], Counters) ->
    List = case maps:get(Key, Counters, []) of
        [] ->
            [{Time, 1}];
        [{Time, OldCounter}|ListRest] ->
            [{Time, OldCounter+1}|ListRest];
        L2 ->
            L3 = [{Time, 1}|L2],
            case length(L3) > 5 of
                true ->
                    lists:sublist(L3, 5);
                false ->
                    L3
            end
    end,
    add_counters(Rest, Counters#{Key => List}).


%% @private
get_counters(TimeKeys, Counters) ->
    TimeList = get_time(TimeKeys),
    get_counters(TimeList, Counters, []).


%% @private
get_counters([], _Counters, Acc) ->
    Acc;

get_counters([{Key, Time}|Rest], Counters, Acc) ->
    Count = case maps:get(Key, Counters, []) of
        [{Time, KCount}|Rest] ->
            KCount;
        _ ->
            0
    end,
    get_counters(Rest, Counters, Acc#{Key => Count}).




%% ===================================================================
%% Private
%% ===================================================================

%% @private
get_time([], _Now, Acc) ->
    Acc;

get_time([Key|Rest], Now, Acc) ->
    get_time(Rest, Now, [{Key, round(Key, Now)}|Acc]).


%% @private
round(Key, Now) ->
    Time = time(Key),
    (Now div Time).


%% @private
time(secs) -> 1000;
time(secs5) -> 5 * 1000;
time(mins) -> 60 * 1000;
time(mins5) -> 5 * 60 * 1000;
time(hours) -> 60 * 60 * 1000;
time(days) -> 24 * 60 * 60 * 1000;
time(months) -> 30 * 24 * 60 * 60 * 1000;
time(years) -> 365 * 24 * 60 * 60 * 1000.


%% @private
timestamp() ->
    nklib_util:m_timestamp() - 1510326450792.


%% @private
test() ->
    Now = timestamp(),
    Wait = 5000 - (Now rem 5000),
    io:format("\n\nWaiting for a 5-secs slot (~p msecs)\n\n", [Wait]),
    timer:sleep(Wait+1),
    Counters1 = #{},

    % We are starting at the beginning of a 5-secs slot

    Counters2 = incr([secs, secs5], Counters1),
    io:format("Sending now...\ncounters: ~p\n\n", [Counters2]),
    #{secs := [{TS1, 1}], secs5 := [{T51, 1}]} = Counters2,
    io:format("Waiting 500 msecs\n"),
    timer:sleep(500),
    Counters3 = incr([secs, secs5], Counters2),
    io:format("Sending now...\ncounters: ~p\n\n", [Counters3]),
    #{secs := [{TS1, 2}], secs5 := [{T51, 2}]} = Counters3,

    io:format("Waiting 600 msecs (total 1.1secs)\n"),   % 1100 from start
    timer:sleep(600),
    Counters4 = incr([secs, secs5], Counters3),
    io:format("Sending now...\ncounters: ~p\n\n", [Counters4]),
    #{secs := [{TS2, 1}, {TS1, 2}], secs5 := [{T51, 3}]} = Counters4,
    TS2 = TS1+1,

    io:format("Waiting 2000 msecs (total 4.2secs)\n"),  % 4200 from start
    timer:sleep(2000),
    Counters5 = incr([secs, secs5], Counters4),
    #{secs := [{TS3, 1}, {TS2, 1}, {TS1, 2}], secs5 := [{T51, 4}]} = Counters5,
    io:format("Sending now...\ncounters: ~p\n\n", [Counters5]),
    TS3 = TS2+2,

    io:format("Waiting 1910 msecs (total 5.1secs)\n"),  % 5010 from start
    timer:sleep(1910),
    Counters6 = incr([secs, secs5], Counters5),
    #{secs := [{TS4, 1}, {TS3, 1}, {TS2, 1}, {TS1, 2}], secs5 := [{T52, 1}, {T51, 4}]} = Counters6,
    io:format("Sending now...\ncounters: ~p\n\n", [Counters6]),
    TS4 = TS3+2,
    T52 = T51+1,

    io:format("Waiting 1000 msecs (total 6.1secs)\n"),  % 6010 from start
    timer:sleep(1000),
    Counters7 = incr([secs, secs5], Counters6),
    #{secs := [{TS5, 1}, {TS4, 1}, {TS3, 1}, {TS2, 1}, {TS1, 2}], secs5 := [{T52, 2}, {T51, 4}]} = Counters7,
    io:format("Sending now...\ncounters: ~p\n\n", [Counters7]),
    TS5 = TS4+1,

    io:format("Waiting 1000 msecs (total 7.1secs)\n"),  % 7010 from start
    timer:sleep(1000),
    Counters8 = incr([secs, secs5], Counters7),
    #{secs := [{TS6, 1}, {TS5, 1}, {TS4, 1}, {TS3, 1}, {TS2, 1}], secs5 := [{T52, 3}, {T51, 4}]} = Counters8,
    io:format("Sending now...\ncounters: ~p\n\n", [Counters8]),
    TS6 = TS5+1,
    ok.




