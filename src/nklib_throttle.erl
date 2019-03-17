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
%%

%% @doc Simple throttling management
-module(nklib_throttle).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([new/0, get_time_slots/1, get_time_slots/2, incr/2, incr/3]).
-export([get_last_counter/2, get_last_counter/3]).
-export([get_last_counters/2, get_last_counters/3]).
-export([wait_slot/1, test1/0, test2/0]).
-export_type([time_key/0, counters/0]).

-compile(inline).

%% ===================================================================
%% Types
%% ===================================================================

-type time_key() ::
    {msecs, integer()}  |
    {secs, integer()}  |
    {mins, integer()} |
    {hours, integer()} |
    {days, integer()} |
    {months, integer()} |
    {years, integer()}.

-type time() :: nklib_util:m_timestamp().

-type time_slot() :: integer().

-type counters() :: #{time_key() => [{time_slot(), Counter::integer()}]}.


%% ===================================================================
%% Public
%% ===================================================================

%% @doc Create a new counter
-spec new() ->
    counters().

new() ->
    #{}.


%% @doc Get a time series (number of units of the time_key() from unixtime 0)
-spec get_time_slots([time_key()]) ->
    [{time_key(), time_slot()}].

get_time_slots(TimeKeys) ->
    get_time_slots(TimeKeys, timestamp()).


%% @doc Get a time series (number of units of the time_key() from unixtime 0)
-spec get_time_slots([time_key()], time()) ->
    [{time_key(), time_slot()}].

get_time_slots(TimeKeys, Now) ->
    get_time(TimeKeys, Now, []).


%% @doc Increment counters for a series of time slots
-spec incr([time_key()], counters()) ->
    counters().

incr(TimeKeys, Counters) ->
    incr(TimeKeys, Counters, timestamp()).


%% @doc
-spec incr([time_key()], counters(), time()) ->
    counters().

incr(TimeKeys, Counters, Now) ->
    TimeList = get_time_slots(TimeKeys, Now),
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


%% @doc Get the current counter for a series of time slots
-spec get_last_counter([time_key()], counters()) ->
    #{time_key() => integer()}.

get_last_counter(TimeKeys, Counters) ->
    get_last_counter(TimeKeys, Counters, timestamp()).


%% @doc Get the current counter for a series of time slots
-spec get_last_counter([time_key()], counters(), time()) ->
    #{time_key() => integer()}.

get_last_counter(TimeKeys, Counters, Now) ->
    KeySlots = get_time_slots(TimeKeys, Now),
    %lager:error("NKLOG SLOTS ~p", [KeySlots]),
    do_get_counter(KeySlots, Counters, #{}).


%% @private
do_get_counter([], _Counters, Acc) ->
    Acc;

do_get_counter([{Key, Slot}|Rest], Counters, Acc) ->
    KeyCount = case maps:get(Key, Counters, []) of
        [{Slot, Count}|_] ->
            Count;
        _ ->
            0
    end,
    do_get_counter(Rest, Counters, Acc#{Key => KeyCount}).


%% @doc Get the current counter for a series of time slots
-spec get_last_counters([time_key()], counters()) ->
    #{time_key() => [integer()]}.

get_last_counters(TimeKeys, Counters) ->
    get_last_counters(TimeKeys, Counters, timestamp()).


%% @doc Get the current counter for a series of time slots
-spec get_last_counters([time_key()], counters(), time()) ->
    #{time_key() => [integer()]}.

get_last_counters(TimeKeys, Counters, Now) ->
    KeySlots = get_time_slots(TimeKeys, Now),
    %lager:error("NKLOG SLOTS2 ~p", [KeySlots]),
    do_get_counters(KeySlots, Counters, #{}).


%% @private
do_get_counters([], _Counters, Acc) ->
    Acc;

do_get_counters([{Key, Slot}|Rest], Counters, Acc) ->
    List = maps:get(Key, Counters, []),
    KeyCount = do_get_counters2(Slot, List, 5, []),
    do_get_counters(Rest, Counters, Acc#{Key => KeyCount}).


do_get_counters2(_Slot, _List, 0, Acc) ->
    lists:reverse(Acc);

do_get_counters2(Slot, List, Len, Acc) ->
   Count = case lists:keyfind(Slot, 1, List) of
       {Slot, Counter} ->
           Counter;
       false ->
           0
    end,
    do_get_counters2(Slot-1, List, Len-1, [Count|Acc]).



%% ===================================================================
%% Private
%% ===================================================================

%% @private
get_time([], _Now, Acc) ->
    Acc;

get_time([Key|Rest], Now, Acc) ->
    get_time(Rest, Now, [{Key, time_slot(Key, Now)}|Acc]).


%% @private
time_slot(Key, Now) ->
    Now div time(Key).


%% @private
time({msecs, MSecs}) -> MSecs;
time({secs, Secs}) -> Secs * 1000;
time({mins, Mins}) -> Mins * 60 * 1000;
time({hours, Hours}) -> Hours * 60 * 60 * 1000;
time({days, Days}) -> Days * 24 * 60 * 60 * 1000;
time({months, Months}) -> Months * 30 * 24 * 60 * 60 * 1000;
time({years, Years}) -> Years * 365 * 24 * 60 * 60 * 1000.


%% @private
wait_slot(Time) ->
    Now = timestamp(),
    Wait = Time - (Now rem Time),
    io:format("\n\nWaiting for a 5-secs slot (~p msecs)\n\n", [Wait]),
    timer:sleep(Wait+1).



%% @private
timestamp() ->
    nklib_util:m_timestamp().



%% @private
test1() ->
    wait_slot(5000),
    Counters1 = new(),
    TimeKeys = [{secs, 1}, {secs, 5}],

    % We are starting at the beginning of a 5-secs slot

    Counters2 = incr(TimeKeys, Counters1),
    io:format("Sending now...\ncounters: ~p\n\n", [Counters2]),
    #{{secs, 1} := [{TS1, 1}], {secs, 5} := [{T51, 1}]} = Counters2,
    io:format("Waiting 500 msecs\n"),
    timer:sleep(500),
    Counters3 = incr(TimeKeys, Counters2),
    io:format("Sending now...\ncounters: ~p\n\n", [Counters3]),
    #{{secs, 1} := [{TS1, 2}], {secs, 5} := [{T51, 2}]} = Counters3,

    io:format("Waiting 600 msecs (total 1.1secs)\n"),   % 1100 from start
    timer:sleep(600),
    Counters4 = incr(TimeKeys, Counters3),
    io:format("Sending now...\ncounters: ~p\n\n", [Counters4]),
    #{{secs, 1} := [{TS2, 1}, {TS1, 2}], {secs, 5} := [{T51, 3}]} = Counters4,
    TS2 = TS1+1,

    io:format("Waiting 2000 msecs (total 4.2secs)\n"),  % 4200 from start
    timer:sleep(2000),
    Counters5 = incr(TimeKeys, Counters4),
    #{{secs, 1} := [{TS3, 1}, {TS2, 1}, {TS1, 2}], {secs, 5} := [{T51, 4}]} = Counters5,
    io:format("Sending now...\ncounters: ~p\n\n", [Counters5]),
    TS3 = TS2+2,

    io:format("Waiting 1910 msecs (total 5.1secs)\n"),  % 5010 from start
    timer:sleep(1910),
    Counters6 = incr(TimeKeys, Counters5),
    #{{secs, 1} := [{TS4, 1}, {TS3, 1}, {TS2, 1}, {TS1, 2}], {secs, 5} := [{T52, 1}, {T51, 4}]} = Counters6,
    io:format("Sending now...\ncounters: ~p\n\n", [Counters6]),
    TS4 = TS3+2,
    T52 = T51+1,

    io:format("Waiting 1000 msecs (total 6.1secs)\n"),  % 6010 from start
    timer:sleep(1000),
    Counters7 = incr(TimeKeys, Counters6),
    #{{secs, 1} := [{TS5, 1}, {TS4, 1}, {TS3, 1}, {TS2, 1}, {TS1, 2}], {secs, 5} := [{T52, 2}, {T51, 4}]} = Counters7,
    io:format("Sending now...\ncounters: ~p\n\n", [Counters7]),
    TS5 = TS4+1,

    io:format("Waiting 1000 msecs (total 7.1secs)\n"),  % 7010 from start
    timer:sleep(1000),
    Counters8 = incr(TimeKeys, Counters7),
    #{{secs, 1} := [{TS6, 1}, {TS5, 1}, {TS4, 1}, {TS3, 1}, {TS2, 1}], {secs, 5} := [{T52, 3}, {T51, 4}]} = Counters8,
    io:format("Sending now...\ncounters: ~p\n\n", [Counters8]),
    TS6 = TS5+1,
    ok.


test2() ->
    Counters1 = new(),
    TimeKeys = [{secs, 1}, {msecs, 5000}],

    % Lets start with the beginning of both slots
    Now1 = 10000,
    Counters2 = incr(TimeKeys, Counters1, Now1),
    Counters3 = incr(TimeKeys, Counters2, Now1),
    Counters4 = incr(TimeKeys, Counters3, Now1),
    #{{secs,1}:=3, {msecs,5000}:=3} = get_last_counter(TimeKeys, Counters4, Now1),

    % About to cross the {secs, 1} slot, but not yet
    Now2 = 10999,
    Counters5 = incr(TimeKeys, Counters4, Now2),
    #{{secs,1}:=4, {msecs,5000}:=4} = get_last_counter(TimeKeys, Counters5, Now2),

    % We crossed the {secs, 1} slot
    Now3 = 11000,
    Counters6 = incr(TimeKeys, Counters5, Now3),
    #{{secs,1}:=1, {msecs,5000}:=5} = get_last_counter(TimeKeys, Counters6, Now3),

    % About to cross the {msecs, 5000} slot
    Now4 = 14999,
    Counters7 = incr(TimeKeys, Counters6, Now4),
    #{{secs,1}:=1, {msecs,5000}:=6} = get_last_counter(TimeKeys, Counters7, Now4),

    % Just closed the {msecs, 5000} slot
    Now5 = 15000,
    Counters8 = incr(TimeKeys, Counters7, Now5),
    #{{secs,1}:=1, {msecs,5000}:=1} = get_last_counter(TimeKeys, Counters8, Now5),
    ok.


