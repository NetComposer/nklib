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

%% @doc GELF backend for nklib_log
-module(nklib_log_gelf).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(nklib_log).

-export([init/2, message/3, terminate/2]).
-export_type([gelf/0, opts/0]).

-define(MAX_UDP, 1024).


%% ===================================================================
%% Types
%% ===================================================================

-type gelf() ::
    #{
        host => binary(),
        message => binary() | integer(),
        level => 1..7,
        full_message => binary() | integer(),
        meta => #{ binary() => binary() | integer} | [{binary(), binary() | integer}]
    }.


-type opts() ::
    nklib_log:opts() |
    #{
        server => binary(),     % Mandatory
        port => integer(),
        inet_family => inet | inet6
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
            Fields = case maps:get(meta, Msg, #{}) of
                Map when is_map(Map) -> maps:to_list(Map);
                List when is_list(List) -> List;
                _ -> []
            end,
            Gelf1 = [
                {version, <<"1.1">>},
                {host, to_bin(Host)},
                {short_message, to_bin(Short)},
                {level, to_level(Level)},
                case maps:get(full_message, Msg, <<>>) of
                    <<>> -> [];
                    Full -> [{full_message, to_bin(Full)}]
                end
                |
                lists:map(
                    fun({Key, Val}) ->
                        {
                            <<$_, (to_bin(Key))/binary>>,
                            case is_integer(Val) of
                                true -> Val;
                                false -> to_bin(Val)
                            end
                        }
                    end,
                    Fields)
            ],
            Gelf2 = nklib_json:encode(maps:from_list(lists:flatten(Gelf1))),
            case byte_size(Gelf2) of
                Size when Size =< ?MAX_UDP ->
                    % io:format("SENDING ~p ~p (~p) ~s\n",
                    %           [Ip, Port, byte_size(Gelf2), Gelf2]),
                    ok = gen_udp:send(Socket, Ip, Port, Gelf2);
                Size ->
                    Chunks = get_num_chunks(Size),
                    Id = crypto:strong_rand_bytes(8),
                    Head = <<30, 15, Id/binary>>,
                    send_chunks(Gelf2, Head, 0, Chunks, Socket, Ip, Port)
            end,
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
    case inet:getaddr(nklib_util:to_list(Server), Inet) of
        {ok, Ip} ->
            Port = maps:get(port, Opts, 12201),
            {ok, Socket} = gen_udp:open(0, [binary,{active,false}]),
            {ok, #state{ip=Ip, port=Port, socket=Socket}};
        _ ->
            {error, invalid_gelf_server}
    end;

get_config(_Opts) ->
    {error, missing_gelf_server}.


%% @private
get_num_chunks(Size) ->
    Size div ?MAX_UDP +
    case Size rem ?MAX_UDP of 0 -> 0; _ -> 1 end.


%% @private
send_chunks(Bin, Head, Pos, Chunks, Socket, Ip, Port) ->
    case byte_size(Bin) > ?MAX_UDP of
        true ->
            {Bin2, Rest} = split_binary(Bin, ?MAX_UDP),
            _Msg = send_chunk2(Bin2, Head, Pos, Chunks, Socket, Ip, Port),
            % io:format("Sending chunk ~p: ~p\n", [Pos, Msg]),
            send_chunks(Rest, Head, Pos+1, Chunks, Socket, Ip, Port);
        false ->
            _Msg = send_chunk2(Bin, Head, Pos, Chunks, Socket, Ip, Port),
            % io:format("Sending final chunk ~p: ~p\n", [Pos, Msg]),
            ok
    end.


%% @private
send_chunk2(Bin, Head, Pos, Chunks, Socket, Ip, Port) ->
    Bin2 = zlib:gzip(Bin),
    Msg = <<Head/binary, Pos, Chunks, Bin2/binary>>,
    ok  = gen_udp:send(Socket, Ip, Port, Msg),
    Msg.



to_bin(Term) -> nklib_util:to_binary(Term).

to_level(Level) when is_integer(Level), Level > 0, Level < 8 -> Level;
to_level(_Level) -> 1.
