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

%% @doc OS Exec Manager
-module(nklib_exec).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([async/2, send_data/2, close/1, sync/2, get_all/0]).
-export([parser_lines/1]).
-export([start_link/2, init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).

-type refresh_fun() ::
    fun((Cmd::binary()) -> binary() | iolist()).

-type parser_fun() ::
    fun((Buff::binary()) -> more | {ok, Data::binary(), Rest::binary()}).


%% Start options:
%% - timeout:     time to wait without sending or receiving any data before
%%                the OS process is killed.
%% - refresh_fun: if defined, it will called on timeout, and instead of
%%                killing the process, this data will be sent to the OS
%%                process.
%% - parser:      if defined, you can implement an user-defined parser
%%                for the incoming data. See 'parser_lines/1' for an example.
%% - kill_time:   after stopping the process, if it is defined, a
%%                kill -9 will be sent.

-type start_opts() :: 
    #{
        timeout => integer(),
        refresh_fun => refresh_fun(),
        parser => parser_fun(),
        kill_time => integer()
    }.


%% ===================================================================
%% Public
%% ===================================================================

%% @doc Starts an OS process, waits for its termination and returns
%% the stdout/stderr.
-spec sync(binary()|iolist(), start_opts()) ->
    {ok, binary()} | {error, {Reason::term(), Body::binary()}}.

sync(Cmd, Opts) ->
    case async(Cmd, Opts) of
        {ok, Pid} ->
            Timeout = maps:get(timeout, Opts, 60000),
            wait_sync(Pid, Timeout * 11 div 10);
        {error, Error} ->
            {error, Error}
    end.


%% @doc Start an OS process and returns.
%% The current process will receive the following messages with the format
%% {?MODULE, pid(), Msg}.
%%
%% The messages that will be received are:
%% - {start, OsPid}:    When the process starts, returns the OS PID
%% - {data, binary()}:  Data (parsed is defined) returned from stdout/stderr
%% - refresh:           Sent when a refresh is sent to the process        
%% - {stop, Reason}:    When the process stops
%%
-spec async(binary()|iolist(), start_opts()) ->
    {ok, pid()} | {error, term()}.

async(Cmd, Opts) ->
    Cmd1 = nklib_util:to_binary(Cmd),
    Opts1 = Opts#{pid=>self()},
    gen_server:start_link(?MODULE, [Cmd1, Opts1], []).


%% @doc Sends data to the stdin of an started OS process
-spec send_data(pid(), binary()|iolist()) ->
    ok | {error, term()}.

send_data(Pid, Data) ->
    gen_server:cast(Pid, {send_data, Data}).


%% @doc Closes an started OS process. 
%% If kill_time was defined, a "kill -9" will be sent after this time.
-spec close(pid()) ->
    ok | {error, term()}.

close(Pid) ->
    gen_server:cast(Pid, close).


%% @doc Gets all started OS processes
-spec get_all() ->
    [{Cmd::binary(), Id::pid()}].

get_all() ->
    nklib_proc:values(?MODULE).


%% @doc Parser that splits the output into lines
-spec parser_lines(binary()) ->
    more | {ok, Data::binary(), Rest::binary()}.

parser_lines(Data) ->
    case binary:match(Data, [<<"\n">>, <<"\r\n">>]) of
        {Pos, L} ->
            {First, Rest1} = erlang:split_binary(Data, Pos),
            {_, Rest2} = erlang:split_binary(Rest1, L),
            {ok, First, Rest2};
        nomatch ->
            more
    end.



%% ===================================================================
%% gen_server
%% ===================================================================

%% @private
start_link(Cmd, Opts) ->
    gen_server:start_link(?MODULE, [Cmd, Opts], []).


-record(state, {
    cmd :: binary(),
    user_pid :: pid(),
    port :: port(),
    os_pid :: integer(),
    timeout_time :: integer(),
    timeout_ref :: reference(),
    refresh_fun :: function(),
    parser :: function(),
    kill_time :: integer(),
    buffer = <<>> :: binary()
}).


%% @private
init([Cmd, #{pid:=UserPid}=Opts]) ->
    process_flag(trap_exit, true),
    nklib_proc:put(?MODULE, {Cmd, UserPid}),
    lager:debug("nklib_exec cmd: ~s", [Cmd]),
    Helper = case code:priv_dir(nklib) of
        {error, _} -> error(no_priv_dir);
        Base -> Base ++ "/nklib_launcher "
    end,
    Port = open_port({spawn, Helper++binary_to_list(Cmd)}, 
                     [exit_status, binary, stderr_to_stdout]),
    monitor(process, UserPid),
    State = #state{
        cmd = Cmd, 
        port = Port,
        user_pid = UserPid,
        timeout_time = maps:get(timeout, Opts, undefined),
        refresh_fun = maps:get(refresh_fun, Opts, undefined),
        parser = maps:get(parser, Opts, undefined),
        kill_time = maps:get(kill_time, Opts, undefined),
        buffer = <<>>
    },
    {ok, restart_timer(State)}.


-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {reply, term(), #state{}} | {noreply, #state{}}.

handle_call(get_state, _From, State) ->
    {reply, State, State};

handle_call(Msg, _From, State) -> 
    lager:error("Module ~p received unexpected call ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_cast(term(), #state{}) ->
    {noreply, #state{}} | {stop, term(), #state{}}.

handle_cast({send_data, Data}, #state{port=Port}=State) ->
    Port ! {self(), {command, Data}},
    {noreply, restart_timer(State)};

handle_cast(close, State) ->
    do_stop(user_close, State);
    
handle_cast(error, _State) ->
    error(a);

handle_cast(Msg, State) -> 
    lager:error("Module ~p received unexpected cast ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_info(term(), #state{}) ->
    {noreply, #state{}} | {stop, term(), #state{}}.

handle_info({Port, {data, Data}}, #state{port=Port}=State) ->
    do_parse(Data, restart_timer(State));

handle_info({Port, {exit_status, 0}}, #state{port=Port}=State) ->
    do_stop(ok, State);

handle_info({Port, {exit_status, Status}}, #state{port=Port}=State) ->
    do_stop({exit_status, Status}, State);

handle_info({Port, closed}, #state{port=Port}=State) ->
    do_stop(port_closed, State);

handle_info({'EXIT', Port, _Reason}, #state{port=Port}=State) ->
    do_stop(port_failed, State);

handle_info({'DOWN', _, process, Pid, _Reason}, #state{user_pid=Pid}=State) ->
    do_stop(caller_stop, State);

handle_info(timeout, #state{refresh_fun=Fun}=State) when is_function(Fun, 1) ->
    #state{cmd=Cmd, port=Port} = State,
    Msg = nklib_util:to_binary(Fun(Cmd)),
    Port ! {self(), {command, Msg}},
    send_user_msg(refresh, State),
    {noreply, restart_timer(State)};

handle_info(timeout, State) ->
    do_stop(timeout, State);

handle_info(Info, State) -> 
    lager:warning("Module ~p received unexpected info: ~p", [?MODULE, Info]),
    {noreply, State}.


%% @private
-spec code_change(term(), #state{}, term()) ->
    {ok, #state{}}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% @private
-spec terminate(term(), #state{}) ->
    ok.

terminate(_Reason, #state{user_pid=UserPid, os_pid=OsPid}=State) ->  
    case is_pid(UserPid) of
        true -> send_user_msg({stop, process_stop}, State);
        false -> ok
    end,
    case is_integer(OsPid) of
        true -> stop_os_cmd(State);
        false -> ok
    end.
    


%% ===================================================================
%% Internal
%% ===================================================================

%% @private
-spec wait_sync(pid(), integer()) ->
    {ok, binary()} | {error, {Reason::term(), binary()}}.

wait_sync(Pid, Timeout) ->
    wait_sync(Pid, Timeout, <<>>).
    

%% @private
-spec wait_sync(pid(), integer(), binary()) ->
    {ok, integer(), binary()} | {error, term()}.

wait_sync(Pid, Timeout, Buff) ->
    receive 
        {?MODULE, Pid, Msg} ->
            case Msg of
                {start, _} ->
                    wait_sync(Pid, Timeout, Buff);
                {data, Data} ->
                    Data1 = <<Buff/binary, Data/binary>>,
                    wait_sync(Pid, Timeout, Data1);
                refresh ->
                    wait_sync(Pid, Timeout, Buff);
                {stop, ok} ->
                    {ok, Buff};
                {stop, Reason} ->
                    {error, {Reason, Buff}}
            end
    after 
        Timeout -> {error, timeout}
    end.


%% @private
restart_timer(#state{timeout_time=undefined}=State) ->
    State;

restart_timer(#state{timeout_time=Time, timeout_ref=Ref}=State) ->
    nklib_util:cancel_timer(Ref),
    State#state{timeout_ref=erlang:send_after(Time, self(), timeout)}.


%% @private
send_user_msg(Msg, #state{cmd=Cmd, user_pid=Pid}) ->
    lager:debug("nklib_exec ~s sending msg: ~p", [Cmd, Msg]),
    Pid ! {?MODULE, self(), Msg}.


%% @private
do_stop(Status,State) ->
    send_user_msg({stop, Status}, State),
    stop_os_cmd(State),
    {stop, normal, State#state{user_pid=undefined, os_pid=undefined}}.


%% @private
stop_os_cmd(#state{cmd=Cmd, port=Port, os_pid=OsPid, kill_time=KillTime}) ->
    Port ! {self(), close},
    case is_integer(KillTime) of
        true ->
            timer:sleep(KillTime),
            lager:debug("nklib_exec ~s sending kill", [Cmd]),
            os:cmd("kill -9 " ++ integer_to_list(OsPid));
        false ->
            ok
    end.


%% @private
do_parse(<<"nklib_pid:", Rest/binary>>, #state{cmd=Cmd}=State) ->
    {ok, OsPid, <<"\n", Rest2/binary>>} = extract_number(Rest, []),
    State1 = State#state{os_pid=OsPid},
    lager:debug("nklib_exec OS PID for ~s is ~p", [Cmd, OsPid]),
    send_user_msg({start, OsPid}, State),
    case Rest2 of
        <<>> -> {noreply, State1};
        _ -> do_parse(Rest2, State1)
    end;

do_parse(Data, #state{parser=undefined}=State) ->
    send_user_msg({data, Data}, State),
    {noreply, State};

do_parse(Data, #state{buffer=Buffer, parser=Parser}=State) ->
    Data1 = <<Buffer/binary, Data/binary>>,
    case catch Parser(Data1) of
        more ->
            {noreply, State#state{buffer=Data1}};
        {ok, Data2, Rest} ->
            send_user_msg({data, Data2}, State),
            do_parse(Rest, State#state{buffer = <<>>});
        {'EXIT', _Error} ->
            do_stop(parse_error, State)
    end.


%% @private
extract_number(<<Char, Bin/binary>>, Acc) when Char >= $0, Char =< $9 ->
    extract_number(Bin, [Char|Acc]);

extract_number(<<>>, _) ->
    error;

extract_number(Rest, [_|_]=Acc) ->
    {ok, list_to_integer(lists:reverse(Acc)), Rest};

extract_number(_, _) ->
    error.




