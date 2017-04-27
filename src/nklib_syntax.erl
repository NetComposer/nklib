%% -------------------------------------------------------------------
%%
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

%% @doc NkLIB Syntax Processing
-module(nklib_syntax).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([parse/2, parse/3, spec/2]).
-export([add_defaults/2, add_mandatory/2, map_merge/2]).

-export_type([syntax/0]).


%% ===================================================================
%% Types
%% ===================================================================

-type syntax() :: #{ atom() => syntax_opt()}.

-type syntax_opt() ::
    syntax_term() |
    {list|slist|ulist, syntax_term()}.

-type syntax_term() ::
    ignore | 
    any | 
    atom | {atom, [atom()]} |
    boolean | 
    list | 
    pid | 
    proc | 
    module |
    integer | pos_integer | nat_integer | {integer, none|integer(), none|integer()} |
              {integer, [integer()]} | 
    float | 
    {record, atom()} |
    string | 
    binary | 
    base64 | base64url |
    lower | 
    upper |
    ip | ip4 | ip6 | host | host6 |
    email |
    {function, pos_integer()} |
    unquote | 
    path | fullpath | 
    uri | uris | 
    tokens | words | 
    map | 
    log_level |
    map() |                     % Allow for nested objects
    list() |                    % First matching option is used
    syntax_fun() |
    {syntax, syntax_opt()} |    % Nested syntax (i.e. {list, {syntax, Syntax}})
    '__defaults' |              % Defaults for this level
    '__mandatory'.              % Mandatory fields (full path for keys)

-type syntax_fun() ::
    fun((Val::term()) -> syntax_fun_out()) |
    fun((Key::atom(), Val::term()) -> syntax_fun_out()) |
    fun((Key::atom(), Val::term(), fun_ctx()) -> syntax_fun_out()).


-type syntax_fun_out() ::
    ok | 
    {ok, Val::term()} | 
    {ok, Key::atom(), Val::term()} |
    error | 
    {error, term()}.

-type fun_ctx() ::
    parse_opts() | 
    #{
        ok => [{atom(), term()}], 
        ok_exp => [binary()],
        no_ok => [binary()]
    }.

-type parse_opts() ::
    #{
        return => list,             % Default is map
        path => binary(),           % Use base path instead of <<>>
        defaults => map(), 
        mandatory => [atom()|binary()],
        warning_unknown => boolean(),
        {binary_key, binary()} => boolean()
    }.

-type error() ::
    {syntax_error, Path::binary()} |
    {missing_field, binary()} |
    term().                             % When syntax_fun() returns {error, term()}

-type out() :: #{atom() => term()} | [{atom(), term()}].

-type out_exp() :: [{binary(), term()}].

-type missing() :: [binary()].


-record(parse, {
    ok = [] :: [{atom(), term()}],
    ok_exp = [] :: [{binary(), term()}],
    no_ok = [] :: [binary()],
    syntax :: map(),
    path :: binary(),
    defaults :: map(),
    mandatory :: [binary()],
    opts :: parse_opts()
}).


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Equivalent to parse(Terms, Spec, #{})
-spec parse(map()|list(), syntax()) ->
    {ok, out(), out_exp(), missing()} |
    {error, error()}.

parse(Terms, Spec) ->
    parse(Terms, Spec, #{}).


%% @doc Parses a list of options using a syntaxis
%% It returns:
%% - the returning map or list
%% - a list with "expanded" values (<<"field1.fieldA">>)
%% - a list of missing fields

-spec parse(map()|list(), syntax(), parse_opts()) ->
    {ok, out(), out_exp(), missing()} |
    {error, error()}.

parse(Terms, Syntax, Opts) when is_list(Terms) ->
    Parse = #parse{
        syntax = Syntax,
        opts = Opts,
        path = maps:get(path, Opts, <<>>),
        defaults = maps:get(defaults, Opts, #{}),
        mandatory = maps:get(mandatory, Opts, [])
    },
    case do_parse(Terms, Parse) of
        {ok, #parse{ok=Ok, no_ok=NoOk, ok_exp=Exp}=Parse2} ->
            case check_mandatory(Parse2) of
                ok ->
                    case NoOk /= [] andalso maps:find(warning_unknown, Opts) of
                        {ok, true} ->
                            lager:warning("NkLIB Syntax: unknown keys in config: ~p", 
                                          [NoOk]);
                        _ -> 
                            ok
                    end,
                    case Opts of
                        #{return:=list} ->
                            {ok, Ok, Exp, NoOk};
                        _ ->
                            {ok, list_to_map(Ok), Exp, NoOk}
                    end;
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end;

parse(Terms, Syntax, Opts) when is_map(Terms) ->
    parse(maps:to_list(Terms), Syntax, Opts).


%% @doc
-spec add_defaults(map(), syntax()) ->
    syntax().

add_defaults(Defaults, Syntax) ->
    Base = maps:get('__defaults', Syntax, #{}),
    Syntax#{'__defaults' => maps:merge(Base, Defaults)}.


%% @doc
add_mandatory(List, Syntax) ->
    Base = maps:get('__mandatory', Syntax, []),
    Syntax#{'__mandatory' => List++Base}.



%% @doc Deep merge of two dictionaries
-spec map_merge(map(), map()) ->
    map().

map_merge(Update, Map) ->
    do_map_merge(maps:to_list(Update), Map).


%% @private
do_map_merge([], Map) ->
    Map;

do_map_merge([{Key, Val}|Rest], Map) when is_map(Val) ->
    Val2 = maps:get(Key, Map, #{}),
    Map2 = map_merge(Val, Val2),
    do_map_merge(Rest, Map#{Key=>Map2});

do_map_merge([{Key, Val}|Rest], Map) ->
    do_map_merge(Rest, Map#{Key=>Val}).



%% ===================================================================
%% Parse
%% ===================================================================



%% @private
-spec do_parse([{term(), term()}], #parse{}) ->
    {ok, #parse{}} | {error, error()}.

do_parse([], Parse) ->
    case parse_defaults(Parse) of
        {ok, #parse{ok_exp=Exp}=Parse2} ->
            {ok, Parse2#parse{ok_exp=lists:reverse(Exp)}};
        {error, Error} ->
            {error, Error}
    end;

do_parse([{Key, Val}|Rest], Parse) ->
    case do_parse_key(Key, Val, Parse) of
        {ok, Parse2} ->
            do_parse(Rest, Parse2);
        {error, Error} ->
            {error, Error}
    end;

do_parse([Key|Rest], Parse) ->
    do_parse([{Key, true}|Rest], Parse).


%% @private
do_parse_key(Key, Val, Parse) ->
    #parse{ok=OK, ok_exp=OkExp, no_ok=NoOk, opts=Opts} = Parse,
    case to_existing_atom(Key) of
        {ok, Key2} ->
            case find_config(Key2, Val, Parse) of
                {ok, Key3, Val3} ->
                    PathKey = path_key(Key3, Parse),
                    Key4 = case maps:get({binary_key, PathKey}, Opts, false) of
                        false -> Key3;
                        true -> to_bin(Key3)
                    end,
                    Parse2 = Parse#parse{
                        ok = [{Key4, Val3}|OK],
                        ok_exp = [{PathKey, Val3}|OkExp]
                    },
                    {ok, Parse2};
                {ok, Key3, Val3, Exp3, NoOk3} ->
                    PathKey = path_key(Key3, Parse),
                    Key4 = case maps:get({binary_key, PathKey}, Opts, false) of
                        false -> Key3;
                        true -> to_bin(Key3)
                    end,
                    Parse2 = Parse#parse{
                        ok = [{Key4, Val3}|OK],
                        ok_exp = [{PathKey, Val3}|Exp3++OkExp],
                        no_ok = NoOk3++NoOk
                    },
                    {ok, Parse2};
                {nested, Val2, Nested} ->
                    #parse{defaults=Defaults} = Parse,
                    NestedParse = Parse#parse{
                        ok = [], 
                        path = path_key(Key, Parse), 
                        syntax = Nested,
                        defaults = maps:get(Key2, Defaults, #{})
                    },
                    case do_parse(Val2, NestedParse) of
                        {ok, #parse{ok=OK2, ok_exp=Exp2, no_ok=NoOK2}} ->
                            PathKey = path_key(Key2, Parse),
                            Key3 = case maps:get({binary_key, PathKey}, Opts, false) of
                                false -> Key2;
                                true -> to_bin(Key2)
                            end,
                            Parse2 = Parse#parse{
                                ok = [{Key3, {OK2}}|OK],
                                ok_exp = Exp2,
                                no_ok = NoOK2
                            },
                            {ok, Parse2};
                        {error, Error} ->
                            {error, Error}
                    end;
                no_spec ->
                    {ok, Parse#parse{no_ok=[path_key(Key, Parse)|NoOk]}};
                ignore ->
                    {ok, Parse};
                {error, Error} ->
                    {error, Error}
            end;
        error ->
            {ok, Parse#parse{no_ok=[path_key(Key, Parse)|NoOk]}}
    end.


%% @private
find_config(Key, Val, #parse{syntax=Syntax}=Parse) ->
    case maps:get(Key, Syntax, not_found) of
        not_found ->
            no_spec;
        Fun when is_function(Fun) ->
            FunRes = if
                is_function(Fun, 1) ->
                    catch Fun(Val);
                is_function(Fun, 2) ->
                    catch Fun(Key, Val);
                is_function(Fun, 3) -> 
                    #parse{ok=Ok, ok_exp=Exp, no_ok=NoOk, opts=Opts} = Parse,
                    FunOpts = Opts#{ok=>Ok, ok_exp=>Exp, no_ok=>NoOk},
                    catch Fun(Key, Val, FunOpts)
            end,
            case FunRes of
                ok ->
                    {ok, Key, Val};
                {ok, Val2} ->
                    {ok, Key, Val2};
                {ok, Key2, Val2} when is_atom(Key2) ->
                    {ok, Key2, Val2};
                % {new_ok, OKB} ->
                %     parse(Rest, OKB, NoOk, Syntax, Opts);
                error ->
                    {error, syntax_error(Key, Parse)};
                {error, Error} ->
                    {error, Error};
                {'EXIT', Error} ->
                    lager:warning("NkLIB Syntax: error calling syntax fun for "
                                  "(~p, ~p) ~p", [Key, Val, Error]),
                    error(fun_call_error)
            end;
        Nested when is_map(Nested) ->
            case Val of
                _ when is_map(Val) ->
                    {nested, maps:to_list(Val), Nested};
                {List} when is_list(List) ->
                    {nested, List, Nested};
                _ ->
                    {error, syntax_error(Key, Parse)}
            end;
        ignore ->
            ignore;
        SyntaxOp ->
            case spec(SyntaxOp, Key, Val, Parse) of
                {ok, Val2} ->
                    {ok, Key, Val2};
                {ok, Val2, Exp2, NoOk2} ->
                    {ok, Key, Val2, Exp2, NoOk2};
                error ->
                    {error, syntax_error(Key, Parse)};
                {error, Error} ->
                    {error, Error};
                unknown ->
                    error({invalid_syntax, SyntaxOp})
            end
    end.



%% @private
-spec spec(syntax_opt(), term(), term(), #parse{}) ->
    {ok, term()} | {ok, term(), [binary()], [binary()]} |
    error | {error, term()} | unknown.

spec({ListType, SyntaxOp}, Key, Val, Parse) when ListType==list; ListType==slist; ListType==ulist ->
    case Val of
        [] ->
            {ok, []};
        [Head|_] when not is_integer(Head) ->
            do_parse_list(ListType, SyntaxOp, Key, Val, Parse, []);
        _ ->
            do_parse_list(ListType, SyntaxOp, Key, [Val], Parse, [])
    end;

spec({syntax, Syntax}, Key, Val, Parse) ->
    Path2 = path_key(Key, Parse),
    case parse(Val, Syntax, #{path=>Path2}) of
        {ok, Parsed, Exp, NoOk} ->
            %% lager:warning("Parsed: ~p\nExp: ~p\nNoOk: ~p", [Parsed, Exp, NoOk]),
            {ok, Parsed, Exp, NoOk};
        {error, Error} ->
            {error, Error}
    end;

spec([Opt|Rest], Key, Val, Parse) ->
    case spec(Opt, Key, Val, Parse) of
        {ok, Val2} ->
            {ok, Val2};
        _ ->
            spec(Rest, Key, Val, Parse)
    end;

spec([], _Key, _Val, _Parse) ->
    error;

spec(SyntaxOp, _Key, Val, _Parse) ->
    spec(SyntaxOp, Val).



%% @private
-spec spec(syntax_opt(), term()) ->
    {ok, term()} | error | {error, term()} | unknown.

spec(any, Val) ->
    {ok, Val};

spec(atom, Val) ->
    to_existing_atom(Val);

spec(boolean, Val) when Val==0; Val=="0" ->
    {ok, false};

spec(boolean, Val) when Val==1; Val=="1" ->
    {ok, true};

spec(boolean, Val) ->
    case nklib_util:to_boolean(Val) of
        true -> {ok, true};
        false -> {ok, false};
        error -> error
    end;

spec({atom, List}, Val) ->
    case to_existing_atom(Val) of
        {ok, Atom} ->
            case lists:member(Atom, List) of
                true -> {ok, Atom};
                false -> error
            end;
        error ->
            error
    end;

spec(list, Val) ->
    case is_list(Val) of
        true -> {ok, Val};
        false -> error
    end;

spec(proc, Val) ->
    case is_atom(Val) orelse is_pid(Val) of
        true -> {ok, Val};
        false -> error
    end;

spec(pid, Val) ->
    case is_pid(Val) of
        true ->
            {ok, Val};
        false when is_binary(Val) ->
            try binary_to_term(base64:decode(Val)) of
                Pid when is_pid(Pid) -> {ok, Pid};
                _ -> error
            catch
                _:_ -> error
            end;
        false ->
            error
    end;

spec(module, Val) ->
    case code:ensure_loaded(Val) of
        {module, Val} -> {ok, Val};
        _ -> error
    end;

spec(integer, Val) ->
    spec({integer, none, none}, Val);

spec(pos_integer, Val) ->
    spec({integer, 0, none}, Val);

spec(nat_integer, Val) ->
    spec({integer, 1, none}, Val);

spec({integer, Min, Max}, Val) ->
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

spec({integer, List}, Val) when is_list(List) ->
    case nklib_util:to_integer(Val) of
        error -> 
            error;
        Int ->
            case lists:member(Int, List) of
                true -> {ok, Int};
                false -> error
        end
    end;
    
spec(float, Val) ->
    case nklib_util:to_float(Val) of
        error -> 
            error;
        Float ->
            {ok, Float}
    end;

spec({record, Type}, Val) ->
    case is_record(Val, Type) of
        true -> {ok, Val};
        false -> error
    end;

spec(string, Val) ->
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

spec(binary, Val) ->
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

spec(urltoken, Val) ->
    to_urltoken(nklib_util:to_list(Val), []);

spec(base64, Val) ->
    case catch base64:decode(Val) of
        {'EXIT', _} ->
            error;
        Bin ->
            {ok, Bin}
    end;

spec(base64url, Val) ->
    case catch nklib_util:base64url_decode(Val) of
        {'EXIT', _} ->
            error;
        Bin ->
            {ok, Bin}
    end;

spec(lower, Val) ->
    case spec(string, Val) of
        {ok, List} -> {ok, nklib_util:to_lower(List)};
        error -> error
    end;

spec(upper, Val) ->
    case spec(string, Val) of
        {ok, List} -> {ok, nklib_util:to_upper(List)};
        error -> error
    end;

spec(ip, Val) ->
    case nklib_util:to_ip(Val) of
        {ok, Ip} -> {ok, Ip};
        _ -> error
    end;

spec(ip4, Val) ->
    case nklib_util:to_ip(Val) of
        {ok, {_, _, _, _}=Ip} -> {ok, Ip};
        _ -> error
    end;

spec(ip6, Val) ->
    case nklib_util:to_ip(Val) of
        {ok, {_, _, _, _, _, _, _, _}=Ip} -> {ok, Ip};
        _ -> error
    end;

spec(host, Val) ->
    {ok, nklib_util:to_host(Val)};

spec(host6, Val) ->
    case nklib_util:to_ip(Val) of
        {ok, HostIp6} -> 
            % Ensure it is enclosed in `[]'
            {ok, nklib_util:to_host(HostIp6, true)};
        error -> 
            {ok, nklib_util:to_binary(Val)}
    end;

spec({function, N}, Val) ->
    case is_function(Val, N) of
        true -> {ok, Val};
        false -> error
    end;

spec(unquote, Val) when is_list(Val); is_binary(Val) ->
    case nklib_parse:unquote(Val) of
        error -> error;
        Bin -> {ok, Bin}
    end;

spec(path, Val) when is_list(Val); is_binary(Val) ->
    {ok, nklib_parse:path(Val)};

spec(fullpath, Val) when is_list(Val); is_binary(Val) ->
    {ok, nklib_parse:fullpath(filename:absname(Val))};

spec(uri, Val) ->
    case nklib_parse:uris(Val) of
        [Uri] -> {ok, Uri};
        _ -> error
    end;

spec(uris, Val) ->
    case nklib_parse:uris(Val) of
        error -> error;
        Uris -> {ok, Uris}
    end;

spec(email, Val) ->
    Val2 = to_bin(Val),
    case binary:split(Val2, <<"@">>, [global]) of
        [_, _] -> {ok, Val2};
        _ -> error
    end;

spec(tokens, Val) ->
    case nklib_parse:tokens(Val) of
        error -> error;
        Tokens -> {ok, Tokens}
    end;

spec(words, Val) ->
    case nklib_parse:tokens(Val) of
        error -> error;
        Tokens -> {ok, [W || {W, _} <- Tokens]}
    end;

spec(log_level, Val) when Val>=0, Val=<8 -> 
    {ok, Val};

spec(log_level, Val) ->
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

spec(map, Map) ->
    case is_map(Map) andalso do_parse_map(maps:to_list(Map)) of
        ok -> {ok, Map};
        _ -> error
    end;

spec(_Type, _Val) ->
    unknown.


%% @private
do_parse_list(list, _SyntaxOp, _Key, [], _Parse, Acc) ->
    {ok, lists:reverse(Acc)};

do_parse_list(slist, _SyntaxOp, _Key, [], _Parse, Acc) ->
    {ok, lists:sort(Acc)};

do_parse_list(ulist, _SyntaxOp, _Key, [], _Parse, Acc) ->
    {ok, lists:usort(Acc)};

do_parse_list(ListType, SyntaxOp, Key, [Term|Rest], Parse, Acc) ->
    case spec(SyntaxOp, Key, Term, Parse) of
        {ok, Val} ->
            do_parse_list(ListType, SyntaxOp, Key, Rest, Parse, [Val|Acc]);
        Other ->
            Other
    end;

do_parse_list(_ListType, _Key, _Val, _Parse, _SyntaxOp, _Acc) ->
    error.

%% @private
do_parse_map([]) -> 
    ok;

do_parse_map([{Key, Val}|Rest]) ->
    case is_binary(Key) orelse is_atom(Key) of
        true when is_map(Val) ->
            case do_parse_map(maps:to_list(Val)) of
                ok ->
                    do_parse_map(Rest);
                error ->
                    error
            end;
        true ->
            do_parse_map(Rest);
        false ->
            error
    end.


%% ===================================================================
%% Private
%% ===================================================================


%% @private
parse_defaults(#parse{defaults=Defs1, syntax=Syntax}=Parse) ->
    SynDefs = maps:get('__defaults', Syntax, #{}),
    Defs2 = maps:merge(SynDefs, Defs1),
    parse_defaults(maps:to_list(Defs2), Parse).


%% @private
parse_defaults([], Parse) ->
    {ok, Parse};

parse_defaults([{Key, Val}|Rest], #parse{ok=Ok}=Parse) ->
    case lists:keymember(Key, 1, Ok) of
        true ->
            parse_defaults(Rest, Parse);
        false ->
            % If Val is a map, it will go nested
            case do_parse_key(Key, Val, Parse) of
                {ok, Parse2} ->
                    parse_defaults(Rest, Parse2);
                {error, Error} ->
                    {error, Error}
            end
    end.

%% @private
check_mandatory(#parse{mandatory=Mandatory, syntax=Syntax}=Parse) ->
    SynMand = maps:get('__mandatory', Syntax, []),
    check_mandatory(Mandatory++SynMand, Parse).


%% @private
check_mandatory([], _Parse) ->
    ok;

check_mandatory([Term|Rest], #parse{ok_exp=Exp}=Parse) ->
    case lists:keymember(to_bin(Term), 1, Exp) of
        true ->
            check_mandatory(Rest, Parse);
        false ->
            {error, {missing_field, path_key(Term, Parse)}}
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
syntax_error(Key, Parse) ->
    {syntax_error, path_key(Key, Parse)}.


%% @private
path_key(Key, #parse{path=Path}) ->
    case Path of
        <<>> ->
            to_bin(Key);
        _ ->
            <<Path/binary, $., (to_bin(Key))/binary>>
    end.


%% @private
list_to_map(List) ->
    % lager:error("List: ~p", [List]),
    list_to_map(List, []).


%% @private
list_to_map([], Acc) ->
    maps:from_list(Acc);

list_to_map([{K, {List}}|Rest], Acc) when is_list(List) ->
    list_to_map(Rest, [{K, list_to_map(List)}|Acc]);

list_to_map([{K, V}|Rest], Acc) ->
    list_to_map(Rest, [{K, V}|Acc]).


to_urltoken([], Acc) ->
    list_to_binary(lists:reverse(Acc));
to_urltoken([Char|Rest], Acc) when Char >= $0, Char =< $9 ->
    to_urltoken(Rest, [Char|Acc]);
to_urltoken([Char|Rest], Acc) when Char >= $A, Char =< $Z ->
    to_urltoken(Rest, [Char+32|Acc]);
to_urltoken([Char|Rest], Acc) when Char >= $a, Char =< $z ->
    to_urltoken(Rest, [Char|Acc]);
to_urltoken([32|Rest], Acc) ->
    to_urltoken(Rest, [$-|Acc]);
to_urltoken([Char|Rest], Acc) when Char==$- ->
    to_urltoken(Rest, [Rest|Acc]);
to_urltoken([_|Rest], Acc) ->
    to_urltoken(Rest, Acc).


%% @private
to_bin(K) -> nklib_util:to_binary(K).



%% ===================================================================
%% EUnit tests
%% ===================================================================

-define(TEST, 1).
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").


parse1_test() ->
    Spec = #{
        field01 => atom,
        field02 => boolean,
        field03 => {atom, [a, b]},
        field04 => integer,
        field05 => {integer, 1, 5},
        field06 => string,
        field07 => binary,
        field08 => host,
        field09 => host6,
        field10 => fun parse_fun/3,
        field11 => [{atom, [a]}, binary],
        field12 => {list, atom},
        field13 => module,
        fieldXX => invalid
    },

    {ok, #{}, [], []} = parse([], Spec),
    {ok, [], [], []} = parse(#{}, Spec, #{return=>list}),

    {error, {syntax_error, <<"field01">>}} = parse([{field01, "12345"}], Spec),
    
    {ok, 
        #{field01:=fieldXX, field02:=false},
        [{<<"field01">>, fieldXX}, {<<"field02">>, false}],
        [<<"unknown">>]
    } = 
        parse(
            [{field01, "fieldXX"}, {field02, <<"false">>}, {"unknown", a}],
            Spec),

    {ok,
        #{
            field03:=b,
            field04:=-1,
            field05:=2,
            field06:="a",
            field07:=<<"b">>,
            field08:=<<"host">>,
            field09:=<<"[::1]">>
        },
        _, 
        []
    } = 
        parse(
            [{field03, <<"b">>}, {"field04", -1}, {field05, 2}, {field06, "a"}, 
            {field07, "b"}, {<<"field08">>, "host"}, {field09, <<"::1">>}],
            Spec),

    {error, {syntax_error, <<"field03">>}} = parse([{field03, c}], Spec),
    {error, {syntax_error, <<"mypath.field05">>}} = 
        parse([{field05, 0}], Spec, #{path=><<"mypath">>}),
    {error, {syntax_error, <<"field05">>}} = parse([{field05, 6}], Spec),
    {'EXIT', {{invalid_syntax, invalid}, _}} = (catch parse([{fieldXX, a}], Spec)),

    {ok, #{field10:=data1}, _, []} = parse([{field10, data}], Spec),

    {ok, #{field11:=a}, _, []} = parse([{field11, a}], Spec),
    {ok, #{field11:=<<"b">>}, _, []} = parse([{field11, b}], Spec),

    {ok, #{field12:=[a, b, '3']}, _, []} = parse(#{field12 => [a, "b", 3]}, Spec),

    {error, {syntax_error, <<"field13">>}} = parse([{field13, kkk383838}], Spec),
    {ok, #{field13:=string}, _, []} = parse([{field13, string}], Spec),
    ok.


parse2_test() ->
    Spec = #{
        field1 => integer,
        field2 => #{
            field3 => binary,
            field4 => integer,
            field5 => #{
                field6 => binary
            }
        }
    },

    {error,{syntax_error,<<"field1">>}} = parse(#{field1=>[]}, Spec),
    {error,{syntax_error,<<"field2">>}} = parse(#{field2=>1}, Spec),
    {ok, #{field1:=1}, [{<<"field1">>,1}], [<<"fieldX">>]} = 
        parse(#{field1=>1, fieldX=>a}, Spec),
    {ok, #{field2:=#{}}, [], []} = parse(#{field2=>#{}}, Spec),
    {error,{syntax_error,<<"field2.field4">>}} = parse(#{field2=>#{field4=>a}}, Spec),
    
    {ok,
        #{field2 := #{field4 := 2}},
        [{<<"field2.field4">>, 2}],
        [<<"field2.fieldX">>]
    } = 
        parse(#{field2=>#{field4=>2, fieldX=>3}}, Spec),

    {ok,
        #{field1 := 1,field2 := #{field4 := 2,field5 := #{field6 := <<"a">>}}},
        [{<<"field1">>,1}, {<<"field2.field4">>,2}, {<<"field2.field5.field6">>,<<"a">>}],
        [<<"fieldX1">>, <<"field2.fieldX2">>, <<"field2.field5.fieldX3">>]
    } = 
        parse(#{
            field1 => 1, 
            fieldX1 => a,
            field2 => #{
                field4 => 2, 
                fieldX2 => b,
                field5 => #{
                    field6 => a,
                    fieldX3 => c
                }
            }}, Spec),
    ok.

parse3_test() ->
    Spec = #{
        field1 => integer,
        field2 => #{
            field3 => binary,
            field4 => integer,
            field5 => #{
                field6 => binary,
                field7 => integer
            }
        }
    },

    Def = #{field1=>11, field2=>#{field3=>a, field5=>#{field6=>b}}},
    {ok, 
        #{field1:=11, field2:=#{field3:=<<"a">>, field5:=#{field6:=<<"b">>}}},
        [{<<"field1">>,11}, {<<"field2.field3">>,<<"a">>}, {<<"field2.field5.field6">>,<<"b">>}],
        []
    } = 
        parse(#{}, Spec, #{defaults=>Def}),

    {ok, 
        #{field1:=12, field2:=#{field3:=<<"a">>, field5:=#{field6:=<<"b">>}}},
        [{<<"field1">>,12}, {<<"field2.field3">>,<<"a">>}, {<<"field2.field5.field6">>,<<"b">>}],
        []
    } = 
        parse(#{field1=>12}, Spec, #{defaults=>Def}),

    {ok,
        #{
            field1:=12, 
            field2:=#{field3:=<<"a">>, field4:=5, field5:=#{field6:=<<"b">>}}},
        [
            {<<"field1">>,12},
            {<<"field2.field4">>,5},
            {<<"field2.field3">>,<<"a">>},
            {<<"field2.field5.field6">>,<<"b">>}
        ],
        []
    } = 
        parse(#{field1=>12, field2=>#{field4=>5}}, Spec, #{defaults=>Def}),

    {ok,
        #{
            field1:=12, 
            field2:=#{field3:=<<"a">>, field4:=5, field5:=#{field6:=<<"f">>}}},
        [
            {<<"field2.field3">>,<<"a">>},
            {<<"field1">>,12},
            {<<"field2.field4">>,5},
            {<<"field2.field5.field6">>,<<"f">>}
        ],
        [<<"field2.field5.fieldX">>]
    } = 
        parse(#{field1=>12, field2=>#{field4=>5, field5=>#{field6=>f, fieldX=>1}}}, 
              Spec, #{defaults=>Def}),

    Mand = [<<"field1">>, <<"field2.field4">>, <<"field2.field5.field6">>],

    {error, {missing_field, <<"field1">>}} = parse(#{}, Spec, #{mandatory=>Mand}),
    {error, {missing_field, <<"field2.field4">>}} = 
        parse(#{field1=>1}, Spec, #{mandatory=>Mand}),
    {error, {missing_field,<<"field2.field5.field6">>}} = 
        parse(#{field1=>1, field2=>#{field4=>22}}, Spec, #{mandatory=>Mand}),
    {ok, _, _, []} = 
        parse(#{field1=>1, field2=>#{field4=>22, field5=>#{field6=>33}}}, Spec, 
              #{mandatory=>Mand}),

    {error, {missing_field, <<"field2.field4">>}} = 
        parse(#{}, Spec, #{mandatory=>Mand, defaults=>Def}),

    {ok, _, _, _} = 
        parse(#{field2=>#{field4=>22}}, Spec, #{mandatory=>Mand, defaults=>Def}),
    ok.


parse_fun(field10, data, _Opts) ->
    {ok, data1}.


-endif.




