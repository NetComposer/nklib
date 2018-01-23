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

%% @doc Lager backend for GELF
%% Use the following config:
%%  {lager_nklog_backend, [
%%       {server, "c1.netc.io"},     % Only mandatory field (for gelf backend)
%%       {port, 12201},
%%       {name, my_source_name},     % Field 'source' in Graylog
%%       {level, info},                 
%%       {inet_family, inet},
%%       {backend, gelf}
%%  ]}


-module(lager_nklog_backend).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_event).

-export([init/1, handle_call/2, handle_event/2, handle_info/2, terminate/2,
         code_change/3]).

-include_lib("lager/include/lager.hrl").


%% ===================================================================
%% Behaviour
%% ===================================================================

-record(state, {
    level_mask :: {mask, integer()},
    backend :: gelf,
    name :: binary(),
    data :: term()
}).


%% @private
init(Config) ->
    Name = nklib_util:get_binary(name, Config, <<"nklib_log">>),
    Level = nklib_util:get_value(level, Config, info),
    try
        Mask = case get_level_mask(Level) of
            {ok, Mask0} -> Mask0;
            error -> throw({fatal, bad_log_level})
        end,
        case nklib_util:get_value(backend, Config, gelf) of
            gelf ->
                {ok, GelfState} = config_gelf(Name, Config),
                State = #state{
                    level_mask = Mask, 
                    backend = gelf, 
                    name = Name,
                    data = GelfState
                },
                {ok, State};
            Backend ->
                throw({unknown_backend, Backend})
        end
    catch
        throw:Throw -> 
            {error, {fatal, Throw}}
    end.



%% @private
handle_call(get_loglevel, #state{level_mask=Mask} = State) ->
    {ok, Mask, State};

handle_call({set_loglevel, Level}, State) ->
    case get_level_mask(Level) of
        {ok, Mask} ->
            {ok, ok, State#state{level_mask=Mask}};
        error ->
            {ok, {error, bad_log_level}, State}
    end;

handle_call(_Request, State) ->
    {ok, ok, State}.


%% @private
handle_event({log, Message}, #state{level_mask=Mask, backend=gelf}=State) ->
    case lager_util:is_loggable(Message, Mask, ?MODULE) of
        true ->
            #state{name=Name, data=GelfState} = State,
            Long = iolist_to_binary(lager_msg:message(Message)),
            Short = get_short_message(Long, 80),
            MetaData = lager_msg:metadata(Message),
            %% TODO: Check name in Dests
            _Dests = lager_msg:destinations(Message),
            Msg = #{
                host => Name,
                message => Short,
                level => severity(lager_msg:severity(Message)),
                full_message => Long,
                meta => get_fields(MetaData, [])
            },
            nklib_log_gelf:message(Name, Msg, GelfState),
            {ok, State};
        false ->
            {ok, State}
    end;

handle_event(_Event, State) ->
    {ok, State}.


%% @private
handle_info(_Info, State) ->
    {ok, State}.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% @private
terminate(_Reason, _State) ->
    ok.



%% ===================================================================
%% Internal
%% ===================================================================

%% @private
get_level_mask(Level) ->
    try
        {ok, lager_util:config_to_mask(Level)}
    catch
        _:_ -> error
    end.


%% @private
config_gelf(Name, Config) ->
    Server = case nklib_util:get_value(server, Config) of
        unknown -> 
            throw(missing_gelf_host);
        Server0 ->
            nklib_util:to_binary(Server0)
    end,
    Port = case nklib_util:get_value(port, Config, 12201) of
        Port0 when is_integer(Port0), Port0 > 0, Port0 < 65536 ->
            Port0;
        _ ->
            throw(invalid_gelf_port)
    end,
    Inet = case nklib_util:get_value(inet_family, Config, inet) of
        inet -> inet;
        inet6 -> inet6;
        _ -> throw(invalid_inet_family)
    end,
    Opts = #{server=>Server, port=>Port, inet_family=>Inet},
    case nklib_log_gelf:init(Name, Opts) of
        {ok, State} ->
            {ok, State};
        {error, Error} ->
            throw(Error)
    end.


%% @private
get_short_message(Msg, MaxSize) ->
    case size(Msg) =< MaxSize of 
        true -> 
            Msg;
        _ -> 
            <<SM:MaxSize/binary,_/binary>> = Msg,
            SM
    end.


%% @private
get_fields([{Key, Val}|Rest], Acc) when is_binary(Val); is_integer(Val) ->
    get_fields(Rest, [{Key, Val}|Acc]);
get_fields([{Key, Val}|Rest], Acc) ->
    get_fields(Rest, [{Key, nklib_util:to_binary(Val)}|Acc]);
get_fields([], Acc) ->
    Acc.


% @private
severity(debug) -> 7;
severity(info) -> 6;
severity(notice) -> 5;
severity(warning) -> 4;
severity(error) -> 3;
severity(critical) -> 2;
severity(alert) -> 1;
severity(emergency) -> 0;
severity(_) -> 7.

