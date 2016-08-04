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

%% @doc GELF backend for nklib_log
-module(nklib_log_gelf).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(nklib_log).

-export([init/2, message/3, terminate/2]).
-export_type([gelf/0, opts/0]).


%% ===================================================================
%% Types
%% ===================================================================

-type gelf() ::
    #{
        host => binary(),
        message => binary() | integer(),
        level => 1..7,
        full_message => binary() | integer(),
        meta => #{ binary() => binary() | integer}
    }.


-type opts() ::
    nklib_log:opts() |
    #{
        server => binary(),     % Mandatory
        port => integer()
    }.


-record(state, {
    ip :: inet:ip_address(),
    port :: inet:port_number(),
    socket :: port()
}).



%% ===================================================================
%% Behaviour
%% ===================================================================


%% @private
-spec init(nklib_log:id(), opts()) ->
    {ok, #state{}} | {error, term()}.

init(_Id, Opts) ->
    get_config(Opts).


%% @private
-spec message(nklib_log:id(), gelf(), #state{}) ->
    {ok, #state{}} | {error, term()}.

message(_Id, Msg, #state{ip=Ip, port=Port, socket=Socket}=State) ->
    case Msg of
        #{host:=Host, message:=Short} ->
            Level = maps:get(level, Msg, 1),
            Gelf1 = [
                {version, <<"1.1">>},
                {host, Host},
                {short_message, Short},
                {level, Level},
                case maps:get(full_message, Msg, <<>>) of
                    <<>> -> [];
                    Full -> [{full_message, Full}]
                end
                |
                case maps:get(meta, Msg, #{}) of
                    Meta when is_map(Meta) ->
                        lists:map(
                            fun({Key, Val}) ->
                                {
                                    <<$_, (nklib_util:to_binary(Key))/binary>>,
                                    case is_integer(Val) of
                                        true -> Val;
                                        false -> nklib_util:to_binary(Val)
                                    end
                                }
                            end,
                            maps:to_list(Meta));
                    _ ->
                        []
                end
            ],
            Gelf2 = nklib_json:encode(maps:from_list(lists:flatten(Gelf1))),
            Gelf3 = zlib:gzip(Gelf2),
            gen_udp:send(Socket, Ip, Port, Gelf3),
            {ok, State};
        _ ->
            {error, invalid_message}
    end.


%% @private
-spec terminate(term(), #state{}) ->
    ok.

terminate(_Reason, #state{socket=Socket}) ->
    gen_udp:close(Socket),
    ok.



%% ===================================================================
%% Internal
%% ===================================================================



%% @private
get_config(#{server:=Server}=Opts) ->
    Inet = maps:get(inet_family, Opts, inet),
    case inet:getaddr(Server, Inet) of
        {ok, Ip} ->
            Port = maps:get(port, Opts, 12201),
            {ok, Socket} = gen_udp:open(0, [binary,{active,false}]),
            {ok, #state{ip=Ip, port=Port, socket=Socket}};
        _ ->
            {error, invalid_server}
    end;

get_config(_Opts) ->
    {error, missing_server}.


