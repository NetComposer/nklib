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


%% @doc Very simple tracing utilities
-module(nklib_trace).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([create/0, on/0, off/0, insert/2, dump/0, dump/1]).
-compile(inline).

%% ===================================================================
%% Public
%% ===================================================================


%% @doc Called from the main app supervisor to create the ets table
create() ->
    ets:new(?MODULE, [ordered_set, public, named_table]).


%% @doc Starts tracing for the current process
on() ->
    put(?MODULE, true).


%% @doc Stops tracing for the current process
off() ->
    put(?MODULE, false).


%% @doc Inserts a new trace in ETS table, sorted by date
insert(Id, Meta) ->
    case get(?MODULE) of
        true ->
            Time = nklib_date:epoch(usecs),
            Pos = erlang:unique_integer([positive, monotonic]),
            % Pos used to allow several traces on the same exact time
            ets:insert(?MODULE, {{Time, Pos}, Id, Meta});
        _ ->
            ok
    end.


%% @doc Dumps all entries into an easy-to-read format and deletes all entries
dump() ->
    {_, Lines} = lists:foldl(
        fun({{Time, _Pos}, Log, Meta}, {LastTime, Acc}) ->
            Diff = Time-LastTime,
            M = Diff div 1000,
            U = Diff rem 1000,
            Text = case map_size(Meta)==0 of
                true ->
                    io_lib:format("~p ~6..0B.~3..0B ~s\n", [Time, M, U, Log]);
                false ->
                    io_lib:format("~p ~6..0B.~3..0B ~s ~p\n", [Time, M, U, Log, Meta])
            end,
            {Time, [Text|Acc]}
        end,
        {0, []},
        ets:tab2list(?MODULE)),
    ets:delete_all_objects(?MODULE),
    lists:reverse(Lines).


%% @doc Dumps to a file
dump(File) ->
    {ok, FileId} = file:open(File, [write, raw, binary]),
    ok = file:write(FileId, dump()),
    file:close(FileId).


