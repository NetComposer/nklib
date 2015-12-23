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
-export([parse_config/2, parse_config/3, load_env/3, load_domain/5]).
-export([make_cache/5]).

-export([start_link/0, init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2, 
         handle_info/2]).
-export_type([syntax/0, parse_opts/0]).


-compile({no_auto_import, [get/1, put/2]}).

-type syntax_subopt() ::
    ignore | any | atom | boolean | {enum, [atom()]} | list | pid | proc |
    integer | pos_integer | nat_integer | {integer, none|integer(), none|integer()} |
    {integer, [integer()]} | {record, atom()} |
    string | binary | lower | upper |
    ip | host | host6 | {function, pos_integer()} |
    unquote | path | uri | uris | tokens | words | log_level |
    map() | list() | syntax_fun().

-type syntax_fun() ::
    fun((atom(), term(), fun_ctx()) -> 
        ok | {ok, term()} | {ok, term(), term()} |
        {new_ok, [{atom(), term()}]} | error | {error, term()}).

-type fun_ctx() ::
    parse_opts() | #{ok=>[{atom(), term()}], no_ok=>[{binary(), term()}]}.

-type syntax_opt() ::
    syntax_subopt() | {list|slist|ulist, syntax_subopt()} | 
    {update, map|list, MapOrList::atom(), Key::atom(), syntax_subopt()}.

-type syntax() :: #{ atom() => syntax_opt()}.

-type parse_opts() ::
    #{
        return => map|list,         % Default is list
        path => binary(),           % Returned in errors
        defaults => map() | list(),
        mandatory => [atom()]
    }.



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


%% @doc Equivalent to parse_config(Terms, Spec, #{})
-spec parse_config(map()|list(), syntax()) ->
    {ok, [{atom(), term()}], [{binary(), term()}]} | 
    {ok, #{atom()=>term()}, #{binary()=>term()}} |
    {error, Error}
    when Error :: 
        {syntax_error, binary()} | 
        {invalid_spec, syntax_opt()} |
        term().

parse_config(Terms, Spec) ->
    parse_config(Terms, Spec, #{}).


%% @doc Parses a list of options
%% For lists, if duplicated entries, the last one wins
-spec parse_config(map()|list(), syntax(), parse_opts()) ->
    {ok, [{atom(), term()}], [{atom(), term()}]} | 
    {ok, #{atom()=>term()}, #{binary()=>term()}} | 
    {error, Error}
    when Error :: 
        {syntax_error, binary()} | 
        {invalid_spec, syntax_opt()} |
        term().

parse_config(Terms, Syntax, Opts) when is_list(Terms), is_map(Opts) ->
    try
        parse_config(Terms, [], [], Syntax, Opts)
    catch
        throw:Throw ->
            {error, Throw}
    end;

parse_config(Terms, Syntax, Opts) when is_map(Terms), is_map(Opts) ->
    parse_config(maps:to_list(Terms), Syntax, Opts).


%% @doc Loads parsed application environment
-spec load_env(atom(), syntax(), map()|list()) ->
    ok | {error, term()}.

load_env(App, Syntax, Defaults) ->
    AppEnv = application:get_all_env(App),
    case parse_config(AppEnv, Syntax, #{defaults=>Defaults}) of
        {ok, Opts, _} ->
            lists:foreach(fun({K,V}) -> put(App, K, V) end, Opts),
            {ok, Opts};
        {error, Error} ->
            {error, Error}
    end.


%% @doc Loads a domain configuration
-spec load_domain(term(), nklib:domain(), map()|list(), map()|list(), syntax()) ->
    ok | {error, term()}.

load_domain(Mod, Domain, Opts, Defaults, Syntax) ->
    do_load_domain(Mod, Domain, nklib_util:to_list(Opts), 
                    nklib_util:to_list(Defaults), Syntax).

%% @private
do_load_domain(Mod, Domain, Opts, Defaults, Syntax) ->
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
    case parse_config(Opts2, Syntax) of
        {ok, Opts3, _} ->
            lists:foreach(fun({K,V}) -> put_domain(Mod, Domain, K, V) end, Opts3),
            ok;
        {error, Error} ->
            {error, Error}
    end.


%% Generates on the fly a 'cache' module for the indicated keys
-spec make_cache([atom()], module(), nklib:domain(), module(), string()|binary()|none) ->
    ok.

make_cache(KeyList, Mod, Domain, Module, Path) ->
    Syntax = lists:foldl(
        fun(Key, Acc) ->
            Val = get_domain(Mod, Domain, Key),
            [nklib_code:getter(Key, Val)|Acc] 
        end,
        [],
        KeyList),
    {ok, Tree} = nklib_code:compile(Module, Syntax),
    case Path of
        none -> ok;
        _ -> ok = nklib_code:write(Module, Tree, Path)
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
                   syntax(), parse_opts()) ->
    {ok, [{atom(), term()}], [{binary(), term()}]}.

parse_config([], OK, NoOK, Syntax, #{defaults:=Defaults}=Opts) ->
    case parse_config(Defaults, Syntax) of
        {ok, Defaults2, []} ->
            OK2 = nklib_util:defaults(OK, Defaults2),
            parse_config([], OK2, NoOK, Syntax, maps:remove(defaults, Opts));
        {ok, _, DefNoOK} ->
            lager:warning("Error parsing in defaults: ~p", [Defaults]),
            {error, {no_ok, DefNoOK}};
        {error, Error} ->
            lager:warning("Error parsing in defaults: ~p", [Defaults]),
            {error, Error}
    end;

parse_config([], OK, NoOK, _Syntax, Opts) ->
    OK2 = lists:reverse(OK),
    NoOK2 = lists:reverse(NoOK),
    Mandatory = maps:get(mandatory, Opts, []),
    case check_mandatory(Mandatory, OK) of
        ok ->
            case Opts of
                #{return:=map} ->
                    {ok, maps:from_list(OK2), maps:from_list(NoOK)};
                _ ->
                    {ok, OK2, NoOK2}
            end;
        {missing, Key} ->
            {error, {missing_mandatory_field, Key}}
    end;

parse_config([{Key, Val}|Rest], OK, NoOK, Syntax, Opts) ->
    case to_existing_atom(Key) of
        {ok, AtomKey} ->
            find_config(AtomKey, Val, Rest, OK, NoOK, Syntax, Opts);
        error ->
            parse_config(Rest, OK, [{Key, Val}|NoOK], Syntax, Opts)
    end;

parse_config([Key|Rest], OK, NoOK, Syntax, Opts) ->
    parse_config([{Key, true}|Rest], OK, NoOK, Syntax, Opts).


%% @private
find_config(Key, Val, Rest, OK, NoOK, Syntax, Opts) ->
    case maps:get(Key, Syntax, not_found) of
        not_found ->
            parse_config(Rest, OK, [{Key, Val}|NoOK], Syntax, Opts);
        Fun when is_function(Fun, 3) ->
            FunOpts = Opts#{ok=>OK, no_ok=>NoOK},
            case catch Fun(Key, Val, FunOpts) of
                ok ->
                    parse_config(Rest, [{Key, Val}|OK], NoOK, Syntax, Opts);
                {ok, Val1} ->
                    parse_config(Rest, [{Key, Val1}|OK], NoOK, Syntax, Opts);
                {ok, Key1, Val1} when is_atom(Key1) ->
                    parse_config(Rest, [{Key1, Val1}|OK], NoOK, Syntax, Opts);
                {new_ok, OKB} ->
                    parse_config(Rest, OKB, NoOK, Syntax, Opts);
                error ->
                    throw_syntax_error(Key, Opts);
                {error, Error} ->
                    throw(Error);
                {'EXIT', Error} ->
                    lager:warning("Error calling syntax fun: ~p", [Error]),
                    throw({internal_error, ?MODULE, ?LINE})
            end;
        SubSyntax when is_map(SubSyntax) ->
            case is_list(Val) orelse is_map(Val) of
                true ->
                    BinKey = nklib_util:to_binary(Key),
                    Opts1 = maps:remove(defaults, Opts),
                    Opts2 = Opts1#{path=>BinKey},
                    case parse_config(Val, SubSyntax, Opts2) of
                        {ok, Val1, _SubNoOK} ->
                            parse_config(Rest, [{Key, Val1}|OK], NoOK, Syntax, Opts);
                        {error, {syntax_error, Error}} ->
                            throw_syntax_error(Error, Opts);
                        {error, Term} ->
                            throw(Term)
                    end;
                false ->
                    throw_syntax_error(Key, Opts)
            end;
        {update, UpdType, Index2, Key2, SubSyntax} ->
            case do_parse_config(SubSyntax, Val) of
                {ok, Val2} ->
                    NewOK = case lists:keytake(Index2, 1, OK) of
                        false when UpdType==map -> 
                            [{Index2, maps:put(Key2, Val2, #{})}|OK];
                        false when UpdType==list -> 
                            [{Index2, [{Key2, Val2}]}|OK];
                        {value, {Index2, Base}, OKA} when UpdType==map ->
                            [{Index2, maps:put(Key2, Val2, Base)}|OKA];
                        {value, {Index2, Base}, OKA} when UpdType==list ->
                            [{Index2, [{Key2, Val2}|Base]}|OKA]
                    end,
                    parse_config(Rest, NewOK, NoOK, Syntax, Opts);
                error ->
                    throw_syntax_error(Key, Opts)
            end;
        ignore ->
            parse_config(Rest, OK, NoOK, Syntax, Opts);
        SyntaxOp ->
            case do_parse_config(SyntaxOp, Val) of
                {ok, Val1} ->
                    parse_config(Rest, [{Key, Val1}|OK], NoOK, Syntax, Opts);
                error ->
                    throw_syntax_error(Key, Opts);
                unknown ->
                    throw({invalid_spec, SyntaxOp})
            end
    end.


%% @private
to_existing_atom(Term) when is_atom(Term) ->
    {ok, Term};

to_existing_atom(Term) ->
    case catch list_to_existing_atom(nklib_util:to_list(Term)) of
        {'EXIT', _} -> error;
        Atom -> {ok, Atom}
    end.


%% @private
throw_syntax_error(Key, #{path:=Path}) ->
    Path1 = <<
        (nklib_util:to_binary(Path))/binary, $.,
        (nklib_util:to_binary(Key))/binary>>,
    throw({syntax_error, Path1});

throw_syntax_error(Key, _) ->
    throw({syntax_error, nklib_util:to_binary(Key)}).



%% @private
check_mandatory([], _) ->
    ok;

check_mandatory([Key|Rest], All) ->
    case lists:keymember(Key, 1, All) of
        true -> check_mandatory(Rest, All);
        false -> {missing, Key}
    end.


%% @private
-spec do_parse_config(syntax_opt(), term()) ->
    {ok, term()} | error | unknown.

do_parse_config(any, Val) ->
    {ok, Val};

do_parse_config(atom, Val) ->
    to_existing_atom(Val);

do_parse_config(boolean, Val) when Val==0; Val=="0" ->
    {ok, false};

do_parse_config(boolean, Val) when Val==1; Val=="1" ->
    {ok, true};

do_parse_config(boolean, Val) ->
    case nklib_util:to_boolean(Val) of
        true -> {ok, true};
        false -> {ok, false};
        error -> error
    end;

do_parse_config({enum, List}, Val) ->
    case to_existing_atom(Val) of
        {ok, Atom} ->
            case lists:member(Atom, List) of
                true -> {ok, Atom};
                false -> error
            end;
        error ->
            error
    end;

do_parse_config(list, Val) ->
    case is_list(Val) of
        true -> {ok, Val};
        false -> error
    end;

do_parse_config({List, Type}, Val) when List==list; List==slist; List==ulist ->
    case Val of
        [] ->
            {ok, []};
        [Head|_] when not is_integer(Head) ->
            do_parse_config_list(List, Val, Type, []);
        _ -> 
            do_parse_config_list(List, [Val], Type, [])
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
    if 
        is_list(Val) ->
            case catch erlang:list_to_binary(Val) of
                {'EXIT', _} -> error;
                Bin -> {ok, erlang:binary_to_list(Bin)}
            end;
        is_binary(Val); is_atom(Val); is_integer(Val) ->
            {ok, nklib_util:to_list(Val)};
        true ->
            error
    end;

do_parse_config(binary, Val) ->
    if
        is_binary(Val) ->
            {ok, Val};
        Val==[] ->
            {ok, <<>>};
        is_list(Val), is_integer(hd(Val)) ->
            case catch list_to_binary(Val) of
                {'EXIT', _} -> error;
                Bin -> {ok, Bin}
            end;
        is_atom(Val); is_integer(Val) ->
            {ok, nklib_util:to_binary(Val)};
        true ->
            error
    end;
 
do_parse_config(lower, Val) ->
    case do_parse_config(string, Val) of
        {ok, List} -> {ok, nklib_util:to_lower(List)};
        error -> error
    end;

do_parse_config(upper, Val) ->
    case do_parse_config(string, Val) of
        {ok, List} -> {ok, nklib_util:to_upper(List)};
        error -> error
    end;

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

do_parse_config(unquote, Val) when is_list(Val); is_binary(Val) ->
    case nklib_parse:unquote(Val) of
        error -> error;
        Bin -> {ok, Bin}
    end;

do_parse_config(path, Val) when is_list(Val); is_binary(Val) ->
    case nklib_parse:path(Val) of
        error -> error;
        Bin -> {ok, Bin}
    end;

do_parse_config(uri, Val) ->
    case nklib_parse:uris(Val) of
        [Uri] -> {ok, Uri};
        _r -> error
    end;

do_parse_config(uris, Val) ->
    case nklib_parse:uris(Val) of
        error -> error;
        Uris -> {ok, Uris}
    end;

do_parse_config(tokens, Val) ->
    case nklib_parse:tokens(Val) of
        error -> error;
        Tokens -> {ok, Tokens}
    end;

do_parse_config(words, Val) ->
    case nklib_parse:tokens(Val) of
        error -> error;
        Tokens -> {ok, [W || {W, _} <- Tokens]}
    end;

do_parse_config(log_level, Val) when Val>=0, Val=<8 -> 
    {ok, Val};

do_parse_config(log_level, Val) ->
    case Val of
        debug -> {ok, 8};
        info -> {ok, 7};
        notice -> {ok, 6};
        warning -> {ok, 5};
        error -> {ok, 4};
        critical -> {ok, 3};
        alert -> {ok, 2};
        emergency -> {ok, 1};
        none -> {ok, 0};
        _ -> error
    end;

do_parse_config([Opt|Rest], Val) ->
    case catch do_parse_config(Opt, Val) of
        {ok, Val1} -> {ok, Val1};
        _ -> do_parse_config(Rest, Val)
    end;

do_parse_config([], _Val) ->
    error;

do_parse_config(_Type, _Val) ->
    unknown.


%% @private
do_parse_config_list(list, [], _Type, Acc) ->
    {ok, lists:reverse(Acc)};

do_parse_config_list(slist, [], _Type, Acc) ->
    {ok, lists:sort(Acc)};

do_parse_config_list(ulist, [], _Type, Acc) ->
    {ok, lists:usort(Acc)};

do_parse_config_list(ListType, [Term|Rest], Type, Acc) ->
    case do_parse_config(Type, Term) of
        {ok, Val} ->
            do_parse_config_list(ListType, Rest, Type, [Val|Acc]);
        error ->
            error
    end;

do_parse_config_list(_, _, _, _) ->
    error.


       

%% ===================================================================
%% EUnit tests
%% ===================================================================


% -compile([export_all]).
% -define(TEST, 1).
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
        field12 => 
            #{
                field12_a => atom,
                field12_b => integer
            },
        field13 => {list, atom},
        field14 => {update, map, map1, m_field14, integer},
        field15 => {update, map, map1, m_field15, atom},
        fieldXX => invalid
    },

    {ok, [], []} = parse_config([], Spec),
    {ok, [], []} = parse_config(#{}, Spec),

    {error, {syntax_error, <<"field01">>}} = parse_config([{field01, "12345"}], Spec),
    
    {ok,[{field01, fieldXX}, {field02, false}],[{unknown, a}]} = 
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

    {error, {syntax_error, <<"field03">>}} = parse_config([{field03, c}], Spec),
    {error, {syntax_error, <<"mypath.field05">>}} = 
        parse_config([{field05, 0}], Spec, #{path=><<"mypath">>}),
    {error, {syntax_error, <<"field05">>}} = parse_config([{field05, 6}], Spec),
    {error, {invalid_spec, invalid}} = parse_config([{fieldXX, a}], Spec),

    {ok, [{field10, data1}], []} = parse_config([{field10, data}], Spec),
    {ok, [{field01, false}], []} = parse_config([{field01, true}, {field10, opts}], Spec),

    {ok, [{field11, a}], []} = parse_config([{field11, a}], Spec),
    {ok, [{field11, <<"b">>}], []} = parse_config([{field11, b}], Spec),

    {error, {syntax_error, <<"field12">>}} = parse_config([{field12, a}], Spec),
    {error, {syntax_error, <<"field12.field12_a">>}} = 
        parse_config([{field12, [{field12_a, 1}]}], Spec),
    {error, {syntax_error, <<"mypath.field12.field12_a">>}} = 
        parse_config([{field12, [{field12_a, 1}]}], Spec, #{path=><<"mypath">>}),

    % Field 12c is ignored
    {ok, [{field12, [{field12_a, ok},{field12_b, 1}]}],[]} = Sub1 = 
        parse_config(
            [{field12, [{field12_a, "ok"}, {field12_b, "1"}, {field_12_c, none}]}], 
            Spec),
    Sub1 = 
        parse_config(
            #{field12 => #{field12_a=>"ok", field12_b=>"1", field_12_c=>none}},
            Spec),
    {ok, #{field12 := #{field12_a:=ok, field12_b:=1}}, #{}} = Sub2 = 
        parse_config(
            [{field12, [{field12_a, "ok"}, {field12_b, "1"}, {field_12_c, none}]}], 
            Spec, #{return=>map}),
    Sub2 = 
        parse_config(
            #{field12 => #{field12_a=>"ok", field12_b=>"1", field_12_c=>none}},
            Spec, #{return=>map}),

    {ok, [{field13, [a, b, '3']}], []} = parse_config(#{field13 => [a, "b", 3]}, Spec),

    {ok, [{field01, a}, {map1, #{m_field14:=1, m_field15:=b}}],[]} = 
        parse_config(#{field01=>a, field14=>1, field15=>b}, Spec),

    {ok, #{field01:=a, map1:=#{m_field14:=1, m_field15:=b}}, #{}} = 
        parse_config([{field01, a}, {field14, 1}, {field15, b}], Spec, #{return=>map}),

    {error, {syntax_error, <<"field14">>}} = parse_config(#{field01=>a, field14=>a}, Spec),
    ok.


parse_fun(field10, data, _Opts) ->
    {ok, data1};
parse_fun(field10, opts, #{ok:=OK}) ->
    {new_ok, lists:keystore(field01, 1, OK, {field01, false})}.


-endif.










