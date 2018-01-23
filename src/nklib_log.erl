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

%% @doc Common library utility funcions
-module(nklib_log).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([console_loglevel/1]).
-export([console_debug/0, console_info/0, console_notice/0, 
         console_warning/0, console_error/0]).
-export([log/3, log/4]).

-export([start_link/3, message/2, stop/1, find/1, get_all/0]).
-export([init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).

-export_type([id/0, backend/0, opts/0, message/0]).

-callback init(id(), opts()) -> {ok, state()} | {error, term()}.
-callback message(id(), message(), state()) -> {ok, state()} | {error, term()}.
-callback terminate(Reason::term(), state()) -> ok.


%% ===================================================================
%% Types
%% ===================================================================

-type id() :: term().
-type backend() :: module().
-type opts() :: map().
-type state() :: term().
-type message() :: term().




%% ===================================================================
%% Public
%% ===================================================================


%% @doc Changes log level for console
console_debug() -> console_loglevel(debug).
console_info() -> console_loglevel(info).
console_notice() -> console_loglevel(notice).
console_warning() -> console_loglevel(warning).
console_error() -> console_loglevel(error).


%% @doc
log(Level, Format, Args) ->
    log(Level, Format, Args, #{}).


%% @doc
log(Level, Format, Args, Meta) ->
    Meta2 = [{pid, self()} | maps:to_list(Meta)],
    Log = lager_msg:new(io_lib:format(Format, Args), Level, Meta2, []),
    gen_event:notify(lager_event, {log, Log}).



%% @doc Changes log level for console
-spec console_loglevel(debug|info|notice|warning|error) ->
    ok.

console_loglevel(Level) -> 
    lager:set_loglevel(lager_console_backend, Level).


%% @doc Starts a log processor
-spec start_link(id(), backend(), opts()) ->
    {ok, pid()} | {error, term()}.

start_link(Id, Backend, Opts) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Id, Backend, Opts], []).


%% @doc Sends a message
-spec message(id(), message()) ->
    ok | {error, not_found}.

message(Id, Msg) ->
    case find(Id) of
        {ok, Pid} -> gen_server:cast(Pid, {message, Msg});
        not_found -> {error, not_found}
    end.


%% @doc Stops the processor
-spec stop(id()) ->
    ok.

stop(Id) ->
    case find(Id) of
        {ok, Pid} -> gen_server:cast(Pid, stop);
        not_found -> ok
    end.


%% @private
find(Pid) when is_pid(Pid) ->
    {ok, Pid};

find(Id) ->
    case nklib_proc:values({?MODULE, Id}) of
        [{_, Pid}|_] -> {ok, Pid};
        [] -> not_found
    end.


%% @private
get_all() ->
    nklib_proc:values(?MODULE).


% ===================================================================
%% gen_server behaviour
%% ===================================================================

-record(state, {
    id :: id(),
	backend :: backend(),
	substate :: state()
}).


%% @private
-spec init(term()) ->
    {ok, tuple()} | {ok, tuple(), timeout()|hibernate} |
    {stop, term()} | ignore.

init([Id, Backend, Opts]) ->
    nklib_proc:put({?MODULE, Id}),
    nklib_proc:put(?MODULE, Id),
	case Backend:init(Id, Opts) of
        {ok, Sub} ->
            {ok, #state{id=Id, backend=Backend, substate=Sub}};
        {error, Error} ->
            {stop, Error}
    end.


%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {noreply, #state{}} | {reply, term(), #state{}} |
    {stop, Reason::term(), #state{}} | {stop, Reason::term(), Reply::term(), #state{}}.

handle_call(get_state, _From, State) ->
    {reply, State, State};

handle_call(Msg, _From, State) ->
    lager:error("Module ~p received unexpected call ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_cast(term(), #state{}) ->
    {noreply, #state{}} | {stop, term(), #state{}}.

handle_cast({message, Msg}, #state{id=Id, backend=Backend, substate=Sub}=State) -> 
    case Backend:message(Id, Msg, Sub) of
        {ok, Sub2} ->
            {noreply, State#state{substate=Sub2}};
        {error, Error} ->
            % Lager could block if we are processing a lager message...
            io:format("nklib_log (~p): could not send msg: ~p\n", [Id, Error]),
            {noreply, State}
    end;

handle_cast(stop, State) -> 
    {stop, normal, State};
    
handle_cast(Msg, State) -> 
    lager:error("Module ~p received unexpected cast ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_info(term(), #state{}) ->
    {noreply, #state{}} | {stop, term(), #state{}}.

handle_info(Info, State) -> 
    lager:warning("Module ~p received unexpected info: ~p (~p)", [?MODULE, Info, State]),
    {noreply, State}.


%% @private
-spec code_change(term(), #state{}, term()) ->
    {ok, #state{}}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% @private
-spec terminate(term(), #state{}) ->
    ok.

terminate(Reason, #state{backend=Backend, substate=Sub}) ->
    Backend:terminate(Reason, Sub).

    


% ===================================================================
%% Internal
%% ===================================================================

