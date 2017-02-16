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

-export([parse/2, parse/3]).

-export_type([syntax/0, parse_opts/0]).


%% ===================================================================
%% Types
%% ===================================================================


-type syntax_subopt() ::
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
    {function, pos_integer()} |
    unquote | 
    path | fullpath | 
    uri | uris | 
    tokens | words | 
    map | 
    log_level |
    map() | 
    list() |                    % First mathing option is used
    syntax_fun().

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

-type syntax_opt() ::
    syntax_subopt() | 
    {list|slist|ulist, syntax_subopt()} | 
    {update, map|list, MapOrList::atom(), Key::atom(), syntax_subopt()}.

-type syntax() :: #{ atom() => syntax_opt()}.

-type parse_opts() ::
    #{
        return => map|list,         % Default is map
        path => binary(),           % Returned in errors
        defaults => map(), 
        mandatory => [atom()|binary()],
        warning_unknown => boolean()
    }.

-type out_opts() ::
    #{

    }.


-type error() ::
    {syntax_error, Path::binary()} |
    internal_error.



-record(parse, {
    ok = [],
    no_ok = [],
    ok_exp = [],
    syntax,
    path,
    defaults,
    opts
}).



%% ===================================================================
%% Public
%% ===================================================================


%% @doc Equivalent to parse(Terms, Spec, #{})
-spec parse(map()|list(), syntax()) ->
    {ok, [{atom(), term()}], out_opts()} |
    {ok, #{atom()=>term()}, out_opts()} |
    {error, error()}.

parse(Terms, Spec) ->
    parse(Terms, Spec, #{}).


%% @doc Parses a list of options
%% For lists, if duplicated entries, the last one wins
-spec parse(map()|list(), syntax(), parse_opts()) ->
    {ok, [{atom(), term()}], out_opts()} |
    {ok, #{atom()=>term()}, out_opts()} |
    {error, error()}.

parse(Terms, Syntax, Opts) when is_list(Terms) ->
    Parse = #parse{
        syntax = Syntax,
        opts = Opts,
        path = maps:get(path, Opts, <<>>),
        defaults = maps:get(defaults, Opts, [])
    },
    case do_parse(Terms, Parse) of
        {ok, #parse{ok=Ok, no_ok=NoOk, ok_exp=Exp}=Parse2} ->
            Mandatory = maps:get(mandatory, Opts, []),
            case check_mandatory(Mandatory, Parse2) of
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




%% ===================================================================
%% Parse
%% ===================================================================



%% @private
-spec do_parse([{term(), term()}], #parse{}) ->
    {ok, #parse{}} | {error, error()}.

do_parse([], Parse) ->
    parse_defaults(Parse);

do_parse([{Key, Val}|Rest], #parse{ok=OK, ok_exp=OkExp, no_ok=NoOk}=Parse) ->
    case to_existing_atom(Key) of
        {ok, Key2} ->
            case find_config(Key2, Val, Parse) of
                {ok, Key3, Val3, Parse2} ->
                    Parse3 = Parse2#parse{
                        ok = [{Key3, Val3}|OK],
                        ok_exp = [{path_key(Key3, Parse), Val3}|OkExp]
                    },
                    do_parse(Rest, Parse3);
                no_spec ->
                    Parse2 = Parse#parse{no_ok = [path_key(Key, Parse)|NoOk]},
                    do_parse(Rest, Parse2);
                ignore ->
                    do_parse(Rest, Parse);
                {error, Error} ->
                    {error, Error}
            end;
        error ->
            Parse2 = Parse#parse{no_ok=[path_key(Key, Parse)|NoOk]},
            do_parse(Rest, Parse2)
    end;

do_parse([Key|Rest], Parse) ->
    do_parse([{Key, true}|Rest], Parse).


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
                    {ok, Key, Val, Parse};
                {ok, Val2} ->
                    {ok, Key, Val2, Parse};
                {ok, Key2, Val2} when is_atom(Key2) ->
                    {ok, Key2, Val2, Parse};
                % {new_ok, OKB} ->
                %     parse(Rest, OKB, NoOk, Syntax, Opts);
                error ->
                    {error, syntax_error(Key, Parse)};
                {error, Error} ->
                    {error, Error};
                {'EXIT', Error} ->
                    lager:warning("NkLIB Syntax: error calling syntax fun for ~p:~p ~p", 
                                  [Key, Val, Error]),
                    {error, internal_error}
            end;
        Nested when is_map(Nested) ->
            case is_list(Val) orelse is_map(Val) of
                true ->
                    NestedParse = Parse#parse{
                        ok = [], 
                        path = path_key(Key, Parse), 
                        syntax = Nested
                    },
                    case parse(Val, NestedParse) of
                        {ok, #parse{ok=Ok2, ok_exp=Exp2}} ->
                            {ok, Key, Ok2, Parse#parse{ok_exp=Exp2}};
                        Other ->
                            Other
                    end;
                false ->
                    {error, syntax_error(Key, Parse)}
            end;
        % {update, UpdType, Index2, Key2, SubSyntax} ->
        %     case do_parse(SubSyntax, Val) of
        %         {ok, Val2} ->
        %             NewOK = case lists:keytake(Index2, 1, OK) of
        %                 false when UpdType==map -> 
        %                     [{Index2, maps:put(Key2, Val2, #{})}|OK];
        %                 false when UpdType==list -> 
        %                     [{Index2, [{Key2, Val2}]}|OK];
        %                 {value, {Index2, Base}, OKA} when UpdType==map ->
        %                     [{Index2, maps:put(Key2, Val2, Base)}|OKA];
        %                 {value, {Index2, Base}, OKA} when UpdType==list ->
        %                     [{Index2, [{Key2, Val2}|Base]}|OKA]
        %             end,
        %             parse(Rest, NewOK, NoOk, Syntax, Opts);
        %         error ->
        %             throw_syntax_error(Key, Opts)
        %     end;
        ignore ->
            ignore;
        SyntaxOp ->
            case spec(SyntaxOp, Val) of
                {ok, Val2} ->
                    {ok, Key, Val2, Parse};
                error ->
                    {error, syntax_error(Key, Parse)};
                unknown ->
                    error({invalid_syntax, SyntaxOp})
            end
    end.


%% @private
-spec spec(syntax_opt(), term()) ->
    {ok, term()} | error | unknown.

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

spec({atoms, List}, Val) ->
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

spec({List, Type}, Val) when List==list; List==slist; List==ulist ->
    case Val of
        [] ->
            {ok, []};
        [Head|_] when not is_integer(Head) ->
            do_parse_list(List, Val, Type, []);
        _ -> 
            do_parse_list(List, [Val], Type, [])
    end;

spec(proc, Val) ->
    case is_atom(Val) orelse is_pid(Val) of
        true -> {ok, Val};
        false -> error
    end;

spec(pid, Val) ->
    case is_pid(Val) of
        true -> {ok, Val};
        false -> error
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

spec([Opt|Rest], Val) ->
    case spec(Opt, Val) of
        {ok, Val2} -> {ok, Val2};
        _ -> spec(Rest, Val)
    end;

spec([], _Val) ->
    error;

spec(_Type, _Val) ->
    unknown.


%% @private
do_parse_list(list, [], _Type, Acc) ->
    {ok, lists:reverse(Acc)};

do_parse_list(slist, [], _Type, Acc) ->
    {ok, lists:sort(Acc)};

do_parse_list(ulist, [], _Type, Acc) ->
    {ok, lists:usort(Acc)};

do_parse_list(ListType, [Term|Rest], Type, Acc) ->
    case spec(Type, Term) of
        {ok, Val} ->
            do_parse_list(ListType, Rest, Type, [Val|Acc]);
        error ->
            error
    end;

do_parse_list(_, _, _, _) ->
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
parse_defaults(#parse{ok=Ok, defaults=Defaults}=Parse) ->
    case parse_defaults(Ok, [], Defaults) of
        [] ->
            {ok, Parse};
        New ->
            parse(New, Parse#parse{defaults=[]})
    end.


%% @private
parse_defaults(_Ok, Acc, []) ->
    Acc;

parse_defaults(Ok, Acc, [{Key, Val}|Rest]) ->
    case lists:keymember(Key, 1, Ok) of
        true ->
            parse_defaults(Ok, Acc, Rest);
        false ->
            parse_defaults(Ok, [{Key, Val}|Acc], Rest)
    end;

parse_defaults(Ok, Acc, Map) when is_map(Map) ->
    parse_defaults(Ok, Acc, maps:to_list(Map)).


%% @private
check_mandatory([], _Parse) ->
    ok;

check_mandatory([Term|Rest], #parse{ok_exp=Exp}=Parse) ->
    case lists:member(to_bin(Term), Exp) of
        true ->
            check_mandatory(Rest, Parse);
        false ->
            {error, {missing_field, to_bin(Exp)}}
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
    list_to_map(List, []).


%% @private
list_to_map([], Acc) ->
    maps:from_list(Acc);

list_to_map([{K, V}|Rest], Acc) when is_list(V) ->
    list_to_map(Rest, [{K, list_to_map(V)}|Acc]);

list_to_map([{K, V}|Rest], Acc) ->
    list_to_map(Rest, [{K, V}|Acc]).


%% @private
to_bin(K) -> nklib_util:to_binary(K).
