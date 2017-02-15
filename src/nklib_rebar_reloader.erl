%% -------------------------------------------------------------------
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

%% @doc rebar-aware reloader
%%
%% This module monitors:
%% - Directory "src"
%% - Directory "_checkouts"
%%
%% When a Erlang source file is updated it lanches a recompile, 
%% To modify a dep, move it to _checkouts
%%
%% It is loaded automatically if rebar_reloader=true in nklib env


-module(nklib_rebar_reloader).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([start_link/0, start/0, stop/0, get_init/0]).
-export([init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).



%% ===================================================================
%% Types
%% ===================================================================


%% ===================================================================
%% Public
%% ===================================================================


%% @doc
-spec start_link() ->
    {ok, pid()} | {error, term()}.

start_link() ->
    case get_init() of
        {ok, Data} ->
            gen_server:start_link({local, ?MODULE}, ?MODULE, [Data], []);
        {error, Error} ->
            {error, Error}
    end.


%% @doc
-spec start() ->
    {ok, pid()} | {error, term()}.

start() ->
    case get_init() of
        {ok, Data} ->
            gen_server:start({local, ?MODULE}, ?MODULE, [Data], []);
        {error, Error} ->
            {error, Error}
    end.


%% @doc
-spec stop() ->
    ok.

stop() ->
    gen_server:cast(?MODULE, stop).



% ===================================================================
%% gen_server behaviour
%% ===================================================================

-record(state, {
    no_beam_reload
}).

%% @private
-spec init(term()) ->
    {ok, tuple()} | {ok, tuple(), timeout()|hibernate} |
    {stop, term()} | ignore.

init([#{dirs:=Dirs}]) ->
    lager:info("Reloader started (~p)", [self()]),
    lists:foreach(
        fun(Dir) ->
            {ok, Pid} = enotify:start_link(Dir),
            lager:info("Listener for ~s: ~p", [Dir, Pid])
        end,
        Dirs),
    {ok, #state{no_beam_reload=true}}.


%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {noreply, #state{}} | {reply, term(), #state{}} |
    {stop, Reason::term(), #state{}} | {stop, Reason::term(), Reply::term(), #state{}}.

handle_call(Msg, _From, State) ->
    lager:error("Module ~p received unexpected call ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_cast(term(), #state{}) ->
    {noreply, #state{}} | {stop, term(), #state{}}.

handle_cast(stop, State) -> 
    {stop, normal, State};

handle_cast(Msg, State) -> 
    lager:error("Module ~p received unexpected cast ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_info(term(), #state{}) ->
    {noreply, #state{}} | {stop, term(), #state{}}.

handle_info(beam_reload, State) ->
    {noreply, State#state{no_beam_reload=false}};

handle_info({Str, List}, State) when is_list(Str), is_list(List) ->
    State2 = case get_type(Str) of
        {beam, _Module} ->
            % reload(Module, State),
            State;
        erl ->
            recompile(Str, State);
        unknown ->
            lager:debug("Modified but not recognized ~s", [Str]),
            State
    end,
    {noreply, State2};

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

terminate(_Reason, _State) ->
    ok.
    


% ===================================================================
%% Internal
%% ===================================================================

%% @private
get_init() ->
    case sys:get_state(rebar_agent) of
        {_, St, _, _} ->
            % Dir1 = rebar_dir:deps_dir(St),
            Root = rebar_dir:root_dir(St),
            Dir2 = filelib:wildcard(Root++"/src*"),
            Dir3 = filelib:wildcard(Root++"/_checkouts*"),
            {ok, #{dirs=>Dir2++Dir3}};
        _ ->
            {error, no_rebar_agent}
    end.


%% @private
get_type(Str) ->
    case re:run(Str, "/(\\w+)\\.bea", [{capture, all_but_first, list}]) of
        {match, [R]} ->
            {beam, list_to_existing_atom(R)};
        nomatch ->
            case re:run(Str, "\\.erl") of
                {match, _} -> erl;
                nomatch -> unknown
            end
    end.


% %% @private
% reload(Module, #state{no_beam_reload=true}=State) ->
%     lager:debug("Skipping reload for ~s", [Module]),
%     State;

% reload(Module, State) ->
%     timer:sleep(200),
%     code:purge(Module),
%     case code:load_file(Module) of
%         {module, Module} ->
%             lager:info("Module ~s reloaded", [Module]);
%         {error, Error} ->
%             lager:notice("Module ~s NOT reloaded: ~p", [Module, Error])
%     end,
%     State.


%% @private
recompile(Str, State) ->
    lager:info("Recompiling because of ~p", [Str]),
    timer:sleep(200),
    rebar_agent:do(compile),
    erlang:send_after(1000, self(), beam_reload),
    State#state{no_beam_reload=true}.




