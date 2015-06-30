%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Carlos Gonzalez Florido.  All Rights Reserved.
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

%% @doc NkLIB Config Server.
-module(nklib_config).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([get/2, get/3, put/3, del/2, increment/3]).
-export([get_domain/3, get_domain/4, put_domain/4, del_domain/3, increment_domain/4]).
-export([parse_config/2, load_env/4, load_domain/5]).

-export([start_link/0, init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2, 
         handle_info/2]).
-export_type([parse_opt/0]).


-compile({no_auto_import, [get/1, put/2]}).


-type parse_opt() ::
    any | atom | boolean | {enum, [atom()]} | list | pid | proc |
    integer | pos_integer | nat_integer | {integer, none|integer(), none|integer()} |
    {integer, [integer()]} | {record, atom()} |
    string | binary | lower | upper |
    ip | host | host6 | {function, pos_integer()} |
    unquote | path |
    fun((atom(), term(), [{atom(), term()}]) -> 
            ok | {ok, term()} | {opts, [{atom(), term()}]} | error).

-type parse_spec() :: #{ atom() => parse_opt()}.



%% ===================================================================
%% Public
%% ===================================================================


%% @doc Equivalent to `get(Key, undefined)'.
-spec get(term(), term()) -> 
    Value :: term().

get(Mod, Key) ->
    get(Mod, Key, undefined).


%% @doc Gets an config value.
-spec get(term(), term(), term()) -> 
    Value :: term().

get(Mod, Key, Default) -> 
    case ets:lookup(?MODULE, {Mod, none, Key}) of
        [] -> Default;
        [{_, Value}] -> Value
    end.


%% @doc Sets a config value.
-spec put(term(), term(), term()) -> 
    ok.

put(Mod, Key, Val) -> 
    put_domain(Mod, none, Key, Val).


%% @doc Deletes a config value.
-spec del(term(), term()) -> 
    ok.

del(Mod, Key) -> 
    del_domain(Mod, none, Key).


%% @doc Atomically increments or decrements a counter
-spec increment(term(), term(), integer()) ->
    integer().

increment(Mod, Key, Count) ->
    increment_domain(Mod, none, Key, Count).


%% @private
-spec get_domain(term(), nklib:domain(), term()) -> 
    Value :: term().

get_domain(Mod, Domain, Key) ->
    get_domain(Mod, Domain, Key, undefined).


%% @private
-spec get_domain(term(), nklib:domain(), term(), term()) -> 
    Value :: term().

get_domain(Mod, Domain, Key, Default) ->
    case ets:lookup(?MODULE, {Mod, Domain, Key}) of
        [] -> get(Mod, Key, Default);
        [{_, Value}] -> Value
    end.


%% @doc Sets a config value.
-spec put_domain(term(), nklib:domain(), term(), term()) -> 
    ok.

put_domain(Mod, Domain, Key, Val) -> 
    true = ets:insert(?MODULE, {{Mod, Domain, Key}, Val}),
    ok.


%% @doc Deletes a config value.
-spec del_domain(term(), nklib:domain(), term()) -> 
    ok.

del_domain(Mod, Domain, Key) -> 
    true = ets:delete(?MODULE, {Mod, Domain, Key}),
    ok.


%% @doc Atomically increments or decrements a counter
-spec increment_domain(term(), nklib:domain(), term(), integer()) ->
    integer().

increment_domain(Mod, Domain, Key, Count) ->
    ets:update_counter(?MODULE, {Mod, Domain, Key}, Count).


%% @doc Parses a list of options
-spec parse_config(map()|list(), parse_spec()) ->
    {ok, [{atom(), term()}], [{atom(), term()}]} | {error, term()}.

parse_config([], _Spec) ->
    {ok, [], []};

parse_config(Terms, Spec) when is_list(Terms) ->
    try
        parse_config(Terms, [], [], Spec)
    catch
        throw:Throw -> {error, Throw}
    end;

parse_config(Terms, Spec) when is_map(Terms) ->
    case maps:size(Terms) of
        0 -> {ok, [], []};
        _ -> parse_config(maps:to_list(Terms), Spec)
    end.


%% @doc Loads parsed application environment
-spec load_env(term(), atom(), [{atom(), term()}], parse_spec()) ->
    ok | {error, term()}.

load_env(Mod, App, Defaults, Spec) ->
    AppEnv = application:get_all_env(App),
    Env1 = nklib_util:defaults(AppEnv, Defaults),
    case parse_config(Env1, Spec) of
        {ok, Opts, _} ->
            lists:foreach(fun({K,V}) -> put(Mod, K, V) end, Opts),
            ok;
        {error, Error} ->
            {error, Error}
    end.


%% @doc Loads a domain configuration
-spec load_domain(term(), nklib:domain(), map()|list(), [{atom(), term()}], 
                  parse_spec()) ->
    ok | {error, term()}.

load_domain(Mod, Domain, Opts, Defaults, Spec) when is_map(Opts) ->
    load_domain(Mod, Domain, maps:to_list(Opts), Defaults, Spec);

load_domain(Mod, Domain, Opts, Defaults, Spec) when is_list(Opts) ->
    ValidDomainKeys = proplists:get_keys(Defaults),
    DomainKeys = proplists:get_keys(Opts),
    case DomainKeys -- ValidDomainKeys of
        [] ->
            ok;
        Rest ->
            lager:warning("Ignoring config keys ~p starting domain", [Rest])
    end,
    ValidOpts = nklib_util:extract(Opts, ValidDomainKeys),
    DefaultDomainOpts = [{K, get(Mod, K)} || K <- ValidDomainKeys],
    Opts2 = nklib_util:defaults(ValidOpts, DefaultDomainOpts),
    case parse_config(Opts2, Spec) of
        {ok, Opts3, _} ->
            lists:foreach(fun({K,V}) -> put_domain(Mod, Domain, K, V) end, Opts3),
            ok;
        {error, Error} ->
            {error, Error}
    end.


%% ===================================================================
%% gen_server
%% ===================================================================

-record(state, {
}).


%% @private
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
        

%% @private 
-spec init(term()) ->
    {ok, #state{}}.

init([]) ->
    ets:new(?MODULE, [named_table, public, {read_concurrency, true}]),
    {ok, #state{}}.
    

%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {noreply, #state{}}.

handle_call(Msg, _From, State) -> 
    lager:error("Module ~p received unexpected call ~p", [?MODULE, Msg]),
    {noreply, State}.

%% @private
-spec handle_cast(term(), #state{}) ->
    {noreply, #state{}}.

handle_cast(Msg, State) -> 
    lager:error("Module ~p received unexpected cast ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_info(term(), #state{}) ->
    {noreply, #state{}}.

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

terminate(_Reason, _State) ->  
    ok.



%% ===================================================================
%% Private
%% ===================================================================



%% @private
-spec parse_config([{term(), term()}], [{atom(), term()}], [{atom(), term()}],
                   parse_spec()) ->
    {ok, [{atom(), term()}], [{atom(), term()}]}.

parse_config([], Opts1, Opts2, _Spec) ->
    {ok, lists:reverse(Opts1), lists:reverse(Opts2)};

parse_config([{Key, Val}|Rest], Opts1, Opts2, Spec) ->
    case is_atom(Key) of
        true ->
            find_config(Key, Key, Val, Rest, Opts1, Opts2, Spec);
        _ ->
            case catch to_atom(Key) of
                {invalid_atom, _} ->
                    parse_config(Rest, Opts1, [{Key, Val}|Opts2], Spec);
                Index -> 
                    find_config(Index, Key, Val, Rest, Opts1, Opts2, Spec)
            end
    end;

parse_config([Key|Rest], Opts1, Opts2, Spec) ->
    parse_config([{Key, true}|Rest], Opts1, Opts2, Spec).


%% @private
find_config(Index, Key, Val, Rest, Opts1, Opts2, Spec) ->
    case maps:get(Index, Spec, not_found) of
        not_found ->
            parse_config(Rest, Opts1, [{Key, Val}|Opts2], Spec);
        Fun when is_function(Fun, 3) ->
            case catch Fun(Index, Val, Opts1) of
                ok ->
                    parse_config(Rest, [{Index, Val}|Opts1], Opts2, Spec);
                {ok, Val1} ->
                    parse_config(Rest, [{Index, Val1}|Opts1], Opts2, Spec);
                {opts, Opts1B} ->
                    parse_config(Rest, Opts1B, Opts2, Spec);
                error ->
                    throw({invalid_key, Index})
            end;
        KeySpec ->
            case do_parse_config(KeySpec, Val) of
                {ok, Val1} ->
                    parse_config(Rest, [{Index, Val1}|Opts1], Opts2, Spec);
                error ->
                    throw({invalid_key, Index})
            end
    end.


%% @private
to_atom(Term) when is_atom(Term) ->
    Term;

to_atom(Term) ->
    case catch list_to_existing_atom(nklib_util:to_list(Term)) of
        {'EXIT', _} -> throw({invalid_atom, Term});
        Atom -> Atom
    end.



%% @private
-spec do_parse_config(parse_opt(), term()) ->
    {ok, term()} | error.

do_parse_config(any, Val) ->
    {ok, Val};

do_parse_config(atom, Val) ->
    {ok, to_atom(Val)};

do_parse_config(boolean, Val) ->
    case nklib_util:to_boolean(Val) of
        true -> {ok, true};
        false -> {ok, false};
        error -> error
    end;

do_parse_config({enum, List}, Val) ->
    Atom = to_atom(Val),
    case lists:member(Atom, List) of
        true -> {ok, Atom};
        false -> error
    end;

do_parse_config(list, Val) ->
    case is_list(Val) of
        true -> {ok, Val};
        false -> error
    end;

do_parse_config(proc, Val) ->
    case is_atom(Val) orelse is_pid(Val) of
        true -> {ok, Val};
        false -> error
    end;

do_parse_config(pid, Val) ->
    case is_pid(Val) of
        true -> {ok, Val};
        false -> error
    end;

do_parse_config(integer, Val) ->
    do_parse_config({integer, none, none}, Val);

do_parse_config(pos_integer, Val) ->
    do_parse_config({integer, 0, none}, Val);

do_parse_config(nat_integer, Val) ->
    do_parse_config({integer, 1, none}, Val);

do_parse_config({integer, Min, Max}, Val) ->
    case nklib_util:to_integer(Val) of
        error -> 
            error;
        Int when 
            (Min==none orelse Int >= Min) andalso
            (Max==none orelse Int =< Max) ->
            {ok, Int};
        _ ->
            error
    end;

do_parse_config({integer, List}, Val) when is_list(List) ->
    case nklib_util:to_integer(Val) of
        error -> 
            error;
        Int ->
            case lists:member(Int, List) of
                true -> {ok, Int};
                false -> error
        end
    end;
    
do_parse_config({record, Type}, Val) ->
    case is_record(Val, Type) of
        true -> {ok, Val};
        false -> error
    end;

do_parse_config(string, Val) ->
    {ok, nklib_util:to_list(Val)};

do_parse_config(binary, Val) ->
    {ok, nklib_util:to_binary(Val)};

do_parse_config(lower, Val) ->
    {ok, nklib_util:to_lower(Val)};

do_parse_config(upper, Val) ->
    {ok, nklib_util:to_upper(Val)};

do_parse_config(ip, Val) ->
    case nklib_util:to_ip(Val) of
        {ok, Ip} -> {ok, Ip};
        _ -> error
    end;

do_parse_config(host, Val) ->
    {ok, nklib_util:to_host(Val)};

do_parse_config(host6, Val) ->
    case nklib_util:to_ip(Val) of
        {ok, HostIp6} -> 
            % Ensure it is enclosed in `[]'
            {ok, nklib_util:to_host(HostIp6, true)};
        error -> 
            {ok, nklib_util:to_binary(Val)}
    end;

do_parse_config({function, N}, Val) ->
    case is_function(Val, N) of
        true -> {ok, Val};
        false -> error
    end;

do_parse_config(unquote, Val) ->
    case nklib_parse:unquote(Val) of
        error -> error;
        Bin -> {ok, Bin}
    end;

do_parse_config(path, Val) ->
    case nklib_parse:path(Val) of
        error -> error;
        Bin -> {ok, Bin}
    end;

do_parse_config([Opt|Rest], Val) ->
    case catch do_parse_config(Opt, Val) of
        {ok, Val1} -> {ok, Val1};
        _ -> do_parse_config(Rest, Val)
    end;

do_parse_config([], _Val) ->
    error;

do_parse_config(Type, _Val) ->
    throw({invalid_spec, Type}).


%% ===================================================================
%% EUnit tests
%% ===================================================================

-define(TEST, 1).
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").


basic_test_() ->
    {setup, 
        fun() -> catch init([]) end,
        fun(_) ->  ok end,
        [
            fun config/0,
            fun parse1/0
        ]
    }.


config() ->
    M = ?MODULE,
    K = make_ref(),
    undefined = get(M, K),
    none = get(M, K, none),
    undefined = get_domain(M, dom1, K),
    none = get_domain(M, dom1, K, none),

    ok = put(M, K, val1),
    val1 = get(M, K),
    val1 = get_domain(M, dom1, K),
    ok = put_domain(M, dom1, K, val2),
    val2 = get_domain(M, dom1, K),
    val1 = get(M, K),

    ok = del(M, K),
    undefined = get(M, K),
    val2 = get_domain(M, dom1, K),
    ok = del_domain(M, dom1, K),
    undefined = get_domain(M, dom1, K),
    ok.


parse1() ->
    Spec = #{
        field01 => atom,
        field02 => boolean,
        field03 => {enum, [a, b]},
        field04 => integer,
        field05 => {integer, 1, 5},
        field06 => string,
        field07 => binary,
        field08 => host,
        field09 => host6,
        field10 => fun parse_fun/3,
        field11 => [{enum, [a]}, binary],
        fieldXX => invalid
    },

    {ok, [], []} = parse_config([], Spec),
    {ok, [], []} = parse_config(#{}, Spec),

    {error, {invalid_atom, "12345"}} = parse_config([{field01, "12345"}], Spec),
    
    {ok,[{field01, fieldXX}, {field02, false}],[{"unknown", a}]} = 
        parse_config(
            [{field01, "fieldXX"}, {field02, <<"false">>}, {"unknown", a}],
            Spec),

    {ok,[
        {field03, b},
        {field04, -1},
        {field05, 2},
        {field06, "a"},
        {field07, <<"b">>},
        {field08, <<"host">>},
        {field09, <<"[::1]">>}
    ], []} = 
        parse_config(
            [{field03, <<"b">>}, {"field04", -1}, {field05, 2}, {field06, "a"}, 
            {field07, "b"}, {<<"field08">>, "host"}, {field09, <<"::1">>}],
            Spec),

    {error, {invalid_key, field03}} = parse_config([{field03, c}], Spec),
    {error, {invalid_key, field05}} = parse_config([{field05, 0}], Spec),
    {error, {invalid_key, field05}} = parse_config([{field05, 6}], Spec),
    {error, {invalid_spec, invalid}} = parse_config([{fieldXX, a}], Spec),

    {ok, [{field10, data1}], []} = parse_config([{field10, data}], Spec),
    {ok, [{field01, false}], []} = parse_config([{field01, true}, {field10, opts}], Spec),

    {ok, [{field11, a}], []} = parse_config([{field11, a}], Spec),
    {ok, [{field11, <<"b">>}], []} = parse_config([{field11, b}], Spec),
    ok.



parse_fun(field10, data, _Opts) ->
    {ok, data1};
parse_fun(field10, opts, Opts) ->
    {opts, lists:keystore(field01, 1, Opts, {field01, false})}.


-endif.










