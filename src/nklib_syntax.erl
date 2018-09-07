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

%% @doc NkLIB Syntax Processing
-module(nklib_syntax).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([parse/2, parse/3, spec/2]).
-export_type([syntax/0, post_check_fun/0]).


%% ===================================================================
%% Types
%% ===================================================================

-type syntax() ::
    #{
        key() => syntax_opt(),
        '__defaults' => #{key() => term()}  ,       % Defaults for this level
        '__mandatory' => [key()],                   % Mandatory fields for this level
        '__unique_keys' => [key()],                 % Checks that keys are unique in a list
        '__allow_unknown' => boolean(),             % Allow unknown fields
        '__post_check' => post_check_fun()
    }.


-type syntax_opt() ::
    syntax_term() |
    {list|slist|ulist, syntax_term()}.


%% __defaults (#{atom() => term()})
%%   you can set any default at any level
%%   however, if the level is empty in the object, its defaults will not be processed
%%   you must set the whole level as default (key=>#{})
%%
%% __mandatory ([atom()])
%%   sets mandatory fields
%%   for nested objects, the parent object should include the child as mandatory
%%
%%


-type syntax_term() ::
    ignore |
    any |
    atom | {atom, [atom()]} | {atom_or_binary, [atom()]} |
    new_atom | raw_atom |
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
    binary | {binary, [binary()]} | {binary, none|integer(), none|integer()} |
    date_3339 |                      % From any format or epoch to rfc3339
    {epoch, secs|msecs|usecs} |
    base64 | base64url |
    lower |
    upper |
    ip | ip4 | ip6 | host | host6 |
    email |
    {function, pos_integer()} |
    unquote |
    path | basepath | fullpath |
    uri | uris |
    tokens | words |
    normalize | {normalize, nklib_parse:norm_opts()} |
    is_normalized | {is_normalized, nklib_parse:norm_opts()} |
    map |
    log_level |
    {mfa, module(), atom(), [term()]} |
    syntax() |                     % Allow for nested objects
    list() |                    % First matching option is used
    syntax_fun().


-type key() :: atom() | binary().
-type val() :: term().


-type syntax_fun() ::
    fun((val()) -> syntax_fun_out()) |
    fun((key(), val()) -> syntax_fun_out()) |
    fun((key(), val(), fun_ctx()) -> syntax_fun_out()).


-type syntax_fun_out() ::
    ok |
    {ok, val()} |
    {ok, key(), val()} |
    error |
    {error, term()}.

-type fun_ctx() ::
    parse_opts() |
    #{
        ok => [{key(), val()}],
        ok_all => [{binary(), val()}],
        no_ok => [binary()],
        path => binary()
    }.

-type post_check_fun() ::
    fun(([{term(), term()}]) ->
        ok | {ok, [{term(), term()}]} |
        {error, {field, term()}} | {error, {field_missing, term()}} | {error, term()}) |
    fun(([{term(), term()}], fun_ctx()) ->
        ok | {ok, [{term(), term()}]} |
        {error, {field, term()}} | {error, {field_missing, term()}} | {error, term()}).


-type parse_opts() ::
    #{
        path => binary(),           % Use base path instead of <<>>
        allow_unknown => boolean(), % TODO REMOVE, now a syntax-level opt
        term() => term()            % To be used as context in external functions
    }.

-type error() ::
    {syntax_error, Path :: binary()} |
    {field_missing, binary()} |
    {duplicated_key, binary()} |
    term().                             % When syntax_fun() returns {error, term()}

-type out() :: #{key() => term()}.

-type unknown_keys() :: [binary()].

-record(parse, {
    ok = [] :: [{key(), val()}],
    no_ok = [] :: [binary()],
    ok_all = [] :: [{binary(), val()}],
    syntax :: map(),
    path :: binary(),
    allow_unknown :: boolean(),
    opts :: parse_opts()
}).


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Equivalent to parse(Terms, Spec, #{})
-spec parse(map()|list(), syntax()) ->
    {ok, out(), unknown_keys()} | {error, error()}.

parse(Terms, Spec) ->
    parse(Terms, Spec, #{}).


%% @doc Parses a list of options using a syntaxis
%% It returns:
%% - the returning map (keys can be atoms or binaries depending on the syntax)
%% - a list with "expanded" values (<<"field1.fieldA">>)
%% - a list of missing fields

-spec parse(map()|list(), syntax(), parse_opts()) ->
    {ok, out(), unknown_keys()} | {error, error()}.

parse(Terms, Syntax, Opts) when is_list(Terms) ->
    AllowUnknown = case Syntax of
        #{'__allow_unknown':=Allow} ->
            Allow;
        _ ->
            maps:get(allow_unknown, Opts, false)
    end,
    Parse = #parse{
        syntax = Syntax,
        opts = Opts,
        path = maps:get(path, Opts, <<>>),
        allow_unknown = AllowUnknown
    },
    case do_parse(Terms, Parse) of
        {ok, #parse{ok=Ok, no_ok=NoOk}} ->
            {ok, list_to_map(Ok), NoOk};
        {error, Error} ->
            {error, Error}
    end;

parse(Terms, Syntax, Opts) when is_map(Terms) ->
    parse(maps:to_list(Terms), Syntax, Opts).


%% ===================================================================
%% Complex Parsing
%% ===================================================================


%% @private
-spec do_parse([{term(), term()}], #parse{}) ->
    {ok, #parse{}} | {error, error()}.

do_parse([], Parse) ->
    case parse_defaults(Parse) of
        {ok, Parse2} ->
            case check_mandatory(Parse2) of
                ok ->
                    check_post_check(Parse2);
                {error, Error} ->
                    {error, Error}
            end;
        {error, Error} ->
            {error, Error}
    end;

do_parse([{Key, Val} | Rest], Parse) ->
    case do_parse_key(Key, Val, Parse) of
        {ok, Parse2} ->
            do_parse(Rest, Parse2);
        {error, Error} ->
            {error, Error}
    end;

do_parse([Key | Rest], Parse) ->
    do_parse([{Key, true} | Rest], Parse).


%% @private
do_parse_key(Key, Val, #parse{allow_unknown=AllowUnknown}=Parse) ->
     case find_config(Key, Parse) of
         {ok, _Key2, ignore} ->
             {ok, Parse};
         {ok, Key2, SyntaxOp} ->
             case parse_opt(SyntaxOp, Key2, Val, Parse) of
                 {ok, Key3, Val3, Parse3} ->
                     #parse{ok=OK, ok_all=OkAll} = Parse3,
                     PathKey = path_key(Key3, Parse3),
                     Parse4 = Parse3#parse{
                         ok = [{Key3, Val3} | OK],
                         ok_all = [{PathKey, Val3} | OkAll]
                     },
                     {ok, Parse4};
                 {error, unknown} ->
                     error({invalid_syntax, SyntaxOp});
                 {error, syntax} ->
                     {error, syntax_error(Key2, Parse)};
                 {error, Error} ->
                     {error, Error}
             end;
         no_spec when AllowUnknown ->
             #parse{ok=OK, ok_all=OkAll} = Parse,
             PathKey = path_key(Key, Parse),
             Parse2 = Parse#parse{
                 ok = [{Key, Val} | OK],
                 ok_all = [{PathKey, Val} | OkAll]
             },
             {ok, Parse2};
         no_spec ->
            #parse{no_ok=NoOk} = Parse,
            {ok, Parse#parse{no_ok = [path_key(Key, Parse) | NoOk]}}
     end.


%% @private
find_config(Key, #parse{syntax = Syntax}) when is_atom(Key) ->
    case maps:get(Key, Syntax, not_found) of
        not_found ->
            Key2 = to_bin(Key),
            case maps:get(Key2, Syntax, not_found) of
                not_found ->
                    no_spec;
                SyntaxOp ->
                    {ok, Key2, SyntaxOp}
            end;
        SyntaxOp ->
            {ok, Key, SyntaxOp}
    end;

find_config(Key, #parse{syntax = Syntax}) ->
    Key2 = to_bin(Key),
    case maps:get(Key2, Syntax, not_found) of
        not_found ->
            case catch binary_to_existing_atom(Key2, utf8) of
                {'EXIT', _} ->
                    no_spec;
                Key3 ->
                    case maps:get(Key3, Syntax, not_found) of
                        not_found ->
                            no_spec;
                        SyntaxOp ->
                            {ok, Key3, SyntaxOp}
                    end
            end;
        SyntaxOp ->
            {ok, Key, SyntaxOp}
    end.


%% @private
-spec parse_opt(syntax_opt(), term(), term(), #parse{}) ->
    {ok, key(), val(), #parse{}} | {error, term()}.

parse_opt({mfa, Mod, Fun, Args}, Key, Val, Parse) ->
    FunRes = case erlang:function_exported(Mod, Fun, length(Args)+1) of
        true ->
            catch apply(Mod, Fun, Args++[Val]);
        false ->
            case erlang:function_exported(Mod, Fun, length(Args)+2) of
                true ->
                    catch apply(Mod, Fun, Args++[Key, Val]);
                false ->
                    case erlang:function_exported(Mod, Fun, length(Args)+3) of
                        true ->
                            #parse{ok = Ok, ok_all = OkAll, no_ok = NoOk, path = Path, opts = Opts} = Parse,
                            FunOpts = Opts#{ok=>Ok, ok_all=>OkAll, no_ok=>NoOk, path=>Path},
                            catch apply(Mod, Fun, Args++[Key, Val, FunOpts]);
                        false ->
                            function_not_exported
                    end
            end
    end,
    parse_fun_res(FunRes, Key, Val, Parse);

parse_opt(Fun, Key, Val, Parse) when is_function(Fun) ->
    FunRes = if
        is_function(Fun, 1) ->
            catch Fun(Val);
        is_function(Fun, 2) ->
            catch Fun(Key, Val);
        is_function(Fun, 3) ->
            #parse{ok = Ok, ok_all = OkAll, no_ok = NoOk, path = Path, opts = Opts} = Parse,
            FunOpts = Opts#{ok=>Ok, ok_all=>OkAll, no_ok=>NoOk, path=>Path},
            catch Fun(Key, Val, FunOpts)
    end,
    parse_fun_res(FunRes, Key, Val, Parse);

parse_opt({ListType, SyntaxOp}, Key, Val, Parse)
        when ListType == list; ListType == slist; ListType == ulist ->
    case Val of
        [] ->
            {ok, Key, [], Parse};
        [{1, _}|_] ->
            % Luerl-style arrays
            Val2 = [V || {_, V} <- Val],
            parse_opt({ListType, SyntaxOp}, Key, Val2, Parse);
        [{_, _} | _] ->
            parse_opt_list(ListType, SyntaxOp, Key, [Val], Parse, []);
        [Head | _] when not is_integer(Head) ->
            parse_opt_list(ListType, SyntaxOp, Key, Val, Parse, []);
        _ ->
            parse_opt_list(ListType, SyntaxOp, Key, [Val], Parse, [])
    end;

parse_opt(Syntax, Key, Val, #parse{opts=Opts}=Parse) when is_map(Syntax) ->
    case is_list(Val) orelse is_map(Val) of
        true ->
            Path2 = path_key(Key, Parse),
            case parse(Val, Syntax, Opts#{path=>Path2}) of
                {ok, Parsed, NoOk2} ->
                    #parse{ok_all = OkAll, no_ok = NoOk} = Parse,
                    Parse2 = Parse#parse{no_ok = NoOk++NoOk2, ok_all = [{Path2, Parsed}|OkAll]},
                    {ok, Key, Parsed, Parse2};
                {error, Error} ->
                    {error, Error}
            end;
        false ->
            {error, syntax}
    end;

parse_opt([Opt | Rest], Key, Val, Parse) ->
    case parse_opt(Opt, Key, Val, Parse) of
        {ok, Key2, Val2, Parse2} ->
            {ok, Key2, Val2, Parse2};
        {error, _} ->
            parse_opt(Rest, Key, Val, Parse)
    end;

parse_opt([], _Key, _Val, _Parse) ->
    {error, syntax};

parse_opt(SyntaxOp, Key, Val, Parse) ->
    case spec(SyntaxOp, Val) of
        {ok, Val2} ->
            {ok, Key, Val2, Parse};
        error ->
            {error, syntax};
        unknown ->
            {error, unknown}
    end.


%% @private
parse_fun_res(Res, Key, Val, Parse) ->
    case Res of
        ok ->
            {ok, Key, Val, Parse};
        {ok, Val2} ->
            {ok, Key, Val2, Parse};
        {ok, Key2, Val2} when is_atom(Key2) ->
            {ok, Key2, Val2, Parse};
        error ->
            {error, syntax};
        {error, Error} ->
            {error, Error};
        {'EXIT', Error} ->
            lager:warning("NkLIB Syntax: error calling syntax fun for "
                          "(~s, ~p) ~p", [Key, Val, Error]),
            error(fun_call_error)
    end.


%% @private
parse_opt_list(list, SyntaxOp, Key, [], Parse, Acc) ->
    check_unique_key(Key, lists:reverse(Acc), SyntaxOp, Parse);

parse_opt_list(slist, SyntaxOp, Key, [], Parse, Acc) ->
    check_unique_key(Key, lists:sort(Acc), SyntaxOp, Parse);

parse_opt_list(ulist, SyntaxOp, Key, [], Parse, Acc) ->
    check_unique_key(Key, lists:usort(Acc), SyntaxOp, Parse);

parse_opt_list(ListType, SyntaxOp, Key, [Term | Rest], Parse, Acc) ->
    case parse_opt(SyntaxOp, Key, Term, Parse) of
        {ok, Key2, Val2, Parse2} ->
            parse_opt_list(ListType, SyntaxOp, Key2, Rest, Parse2, [Val2 | Acc]);
        {error, Error} ->
            {error, Error}
    end;

parse_opt_list(_ListType, _Key, _Val, _Parse, _SyntaxOp, _Acc) ->
    {error, syntax}.


%% @private
check_unique_key(Key, List, #{'__check_unique_keys':=UniqueKeys}, Parse) ->
    case do_check_unique_keys(UniqueKeys, List) of
        ok ->
            {ok, Key, List, Parse};
        {error, UniqueKey} ->
            UniqueKey2 = list_to_binary([to_bin(Key), $., to_bin(UniqueKey)]),
            {error, duplicated_key_error(UniqueKey2, Parse)}
    end;

check_unique_key(Key, List, _SyntaxOp, Parse) ->
    {ok, Key, List, Parse}.


%% @private
do_check_unique_keys([], _List) ->
    ok;

do_check_unique_keys([UniqueKey|Rest], List) ->
    Values = [Value || #{UniqueKey:=Value} <- List],
    case lists:usort(Values) of
        Values ->
            do_check_unique_keys(Rest, List);
        _ ->
            {error, UniqueKey}
    end.



%% ===================================================================
%% Simple Parsing
%% ===================================================================


%% @private
-spec spec(syntax_opt(), term()) ->
    {ok, term()} | error | unknown.

spec(any, Val) ->
    case nklib_util:to_binary(Val) of
        <<"null">> ->
            {ok, null};
        _ ->
            {ok, Val}
    end;

spec(raw_atom, Val) when is_atom(Val) ->
    {ok, Val};

spec(raw_atom, _Val) ->
    error;

spec(atom, Val) ->
    to_existing_atom(Val);

% Use with caution!
spec(new_atom, Val) when is_atom(Val) ->
    {ok, Val};

spec(new_atom, Val) ->
    {ok, binary_to_atom(nklib_util:to_binary(Val), utf8)};

spec(boolean, Val) when Val == 0; Val == "0" ->
    {ok, false};

spec(boolean, Val) when Val == 1; Val == "1" ->
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

spec({atom_or_binary, List}, Val) ->
    case to_existing_atom(Val) of
        {ok, Atom} ->
            case lists:member(Atom, List) of
                true -> {ok, Atom};
                false -> {ok, to_bin(Val)}
            end;
        error ->
            {ok, to_bin(Val)}
    end;

%%% Luerl-style lists
%%spec(list, [{1, _}|_]=Val) ->
%%    lager:error("NKLOG VV0 ~p", [Val]),
%%    spec(list, [V || {_, V} <- Val]);
%%
%%spec(list, Val) ->
%%    lager:error("NKLOG VV ~p", [Val]),
%%    case is_list(Val) of
%%        true -> {ok, Val};
%%        false -> error
%%    end;


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
    case to_existing_atom(Val) of
        {ok, Module} ->
            case code:ensure_loaded(Module) of
                {module, Module} -> {ok, Module};
                _ -> error
            end;
        error ->
            error
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
            (Min == none orelse Int >= Min) andalso
                (Max == none orelse Int =< Max) ->
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

spec({integer, _}, _Val) ->
    error;

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
        Val == [] ->
            {ok, <<>>};
        is_list(Val), is_integer(hd(Val)) ->
            case catch list_to_binary(Val) of
                {'EXIT', _} -> error;
                Bin -> {ok, Bin}
            end;
        is_list(Val) ->
            Val2 = [nklib_util:to_binary(Term) || Term <- Val],
            case catch list_to_binary(Val2) of
                {'EXIT', _} -> error;
                Bin -> {ok, Bin}
            end;
        is_atom(Val); is_integer(Val) ->
            {ok, nklib_util:to_binary(Val)};
        true ->
            error
    end;

spec({binary, List}, Val) ->
    Bin = to_bin(Val),
    case lists:member(Bin, List) of
        true -> {ok, Bin};
        false -> error
    end;

spec({binary, Min, Max}, Val) ->
    Bin = to_bin(Val),
    case
        (Min == none orelse byte_size(Bin) >= Min) andalso
        (Max == none orelse byte_size(Bin) =< Max)
    of
        true ->
            {ok, Bin};
        _ ->
            error
    end;

spec(urltoken, Val) ->
    to_urltoken(nklib_util:to_list(Val), []);

spec(base64, Val) ->
    case catch nklib_util:base64_decode(Val) of
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

spec(date_3339, Val) ->
    % First, we try if is already a valid date in a speedy way
    case nklib_date:is_3339(Val) of
        {true, _} ->
            {ok, to_bin(Val)};
        false ->
            % It is not, let's try full parser
            case nklib_date:to_3339(Val, msecs) of
                {ok, Val2} ->
                    {ok, Val2};
                {error, _Error} ->
                    error
            end
    end;

spec({epoch, Unit}, Val) ->
    % First, we try if is already a valid date in a speedy way
    case nklib_date:to_epoch(Val, Unit) of
        {ok, Val2} ->
            {ok, Val2};
        {error, _Error} ->
            error
    end;

spec(ip, Val) ->
    case nklib_util:to_ip(Val) of
        {ok, Ip} -> {ok, Ip};
        _ -> error
    end;

spec(ip4, Val) ->
    case nklib_util:to_ip(Val) of
        {ok, {_, _, _, _} = Ip} -> {ok, Ip};
        _ -> error
    end;

spec(ip6, Val) ->
    case nklib_util:to_ip(Val) of
        {ok, {_, _, _, _, _, _, _, _} = Ip} -> {ok, Ip};
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

% For luerl
spec({function, N}, {function, Val}) ->
    case is_function(Val, N) of
        true -> {ok, Val};
        false -> error
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

spec(unquote, _Val) ->
    error;

spec(path, Val) when is_list(Val); is_binary(Val) ->
    {ok, nklib_parse:path(Val)};

spec(path, _) ->
    error;

spec(basepath, Val) when is_list(Val); is_binary(Val) ->
    {ok, nklib_parse:basepath(Val)};

spec(basepath, _) ->
    error;

spec(fullpath, Val) when is_list(Val); is_binary(Val) ->
    {ok, nklib_parse:fullpath(filename:absname(Val))};

spec(fullpath, _) ->
    error;

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

spec(normalize, Val) ->
    spec({normalize, #{}}, Val);

spec({normalize, Opts}, Val) ->
    {ok, nklib_parse:normalize(Val, Opts)};

spec(is_normalized, Val) ->
    spec({is_normalized, #{}}, Val);

spec({is_normalized, Opts}, Val) ->
    Norm = nklib_parse:normalize(Val, Opts),
    case to_bin(Val) of
        Norm -> {ok, Norm};
        _ -> error
    end;

spec(log_level, Val) when Val >= 0, Val =< 8 ->
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

spec(map, Map) when is_map(Map) ->
    case do_parse_map(maps:to_list(Map)) of
        ok -> {ok, Map};
        _ -> error
    end;

spec(map, List) when is_list(List) ->
    case do_parse_map(List) of
        ok -> {ok, maps:from_list(List)};
        _ -> error
    end;

spec(map, _) ->
    error;

spec(_Type, _Val) ->
    unknown.



%% ===================================================================
%% Private
%% ===================================================================


%% @private
do_parse_map([]) ->
    ok;

do_parse_map([{Key, Val} | Rest]) ->
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
    end;

do_parse_map(_) ->
    error.


%% @private
parse_defaults(#parse{syntax = Syntax} = Parse) ->
    SynDefs = maps:get('__defaults', Syntax, #{}),
    parse_defaults(maps:to_list(SynDefs), Parse).


%% @private
parse_defaults([], Parse) ->
    {ok, Parse};

parse_defaults([{Key, Val} | Rest], #parse{ok = Ok} = Parse) ->
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
check_mandatory(#parse{syntax = Syntax} = Parse) ->
    SynMand = maps:get('__mandatory', Syntax, []),
    check_mandatory(SynMand, Parse).


%% @private
check_mandatory([], _Parse) ->
    ok;

check_mandatory([Key | Rest], #parse{ok = Ok} = Parse) ->
    case lists:keymember(Key, 1, Ok) of
        true ->
            check_mandatory(Rest, Parse);
        false ->
            {error, {field_missing, path_key(Key, Parse)}}
    end.


%% @private
check_post_check(#parse{syntax = Syntax, ok = Ok, opts=Opts} = Parse) ->
    case maps:get('__post_check', Syntax, none) of
        Fun when is_function(Fun, 1) ->
            case Fun(Ok) of
                ok ->
                    {ok, Parse};
                {ok, Ok2} ->
                    {ok, Parse#parse{ok=Ok2}};
                {error, {field, Key}} ->
                    {error, {syntax_error, path_key(Key, Parse)}};
                {error, {field_missing, Key}} ->
                    {error, {field_missing, path_key(Key, Parse)}};
                {error, Error} ->
                    {error, Error}
            end;
        Fun when is_function(Fun, 2) ->
            case Fun(Ok, Opts) of
                ok ->
                    {ok, Parse};
                {ok, Ok2} ->
                    {ok, Parse#parse{ok=Ok2}};
                {error, {field, Key}} ->
                    {error, {syntax_error, path_key(Key, Parse)}};
                {error, {field_missing, Key}} ->
                    {error, {field_missing, path_key(Key, Parse)}};
                {error, Error} ->
                    {error, Error}
            end;
        _ ->
            {ok, Parse}
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
duplicated_key_error(Key, Parse) ->
    {duplicated_key, path_key(Key, Parse)}.


%% @private
path_key(Key, #parse{path = Path}) ->
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

list_to_map([{K, {List}} | Rest], Acc) when is_list(List) ->
    list_to_map(Rest, [{K, list_to_map(List)} | Acc]);

list_to_map([{K, V} | Rest], Acc) ->
    list_to_map(Rest, [{K, V} | Acc]).


to_urltoken([], Acc) ->
    list_to_binary(lists:reverse(Acc));
to_urltoken([Char | Rest], Acc) when Char >= $0, Char =< $9 ->
    to_urltoken(Rest, [Char | Acc]);
to_urltoken([Char | Rest], Acc) when Char >= $A, Char =< $Z ->
    to_urltoken(Rest, [Char + 32 | Acc]);
to_urltoken([Char | Rest], Acc) when Char >= $a, Char =< $z ->
    to_urltoken(Rest, [Char | Acc]);
to_urltoken([32 | Rest], Acc) ->
    to_urltoken(Rest, [$- | Acc]);
to_urltoken([Char | Rest], Acc) when Char == $- ->
    to_urltoken(Rest, [Rest | Acc]);
to_urltoken([_ | Rest], Acc) ->
    to_urltoken(Rest, Acc).


%% @private
to_bin(K) when is_binary(K) -> K;
to_bin(K) -> nklib_util:to_binary(K).


%% ===================================================================
%% EUnit tests
%% ===================================================================

%-define(TEST, 1).
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

    {ok, #{}, []} = parse([], Spec),

    {error, {syntax_error, <<"field01">>}} = parse([{field01, "12345"}], Spec),

    {ok, #{field01:=fieldXX, field02:=false}, [<<"unknown">>]} =
        parse([{field01, "fieldXX"}, {field02, <<"false">>}, {"unknown", a}], Spec),

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
        []
    } =
        parse(
            [{field03, <<"b">>}, {"field04", -1}, {field05, 2}, {field06, "a"},
                {field07, "b"}, {<<"field08">>, "host"}, {field09, <<"::1">>}],
            Spec),

    {error, {syntax_error, <<"field03">>}} = parse([{field03, c}], Spec),
    {error, {syntax_error, <<"mypath.field05">>}} = parse([{field05, 0}], Spec, #{path=><<"mypath">>}),
    {error, {syntax_error, <<"field05">>}} = parse([{field05, 6}], Spec),
    {'EXIT', {{invalid_syntax, invalid}, _}} = (catch parse([{fieldXX, a}], Spec)),

    {ok, #{field10:=data1}, []} = parse([{field10, data}], Spec),

    {ok, #{field11:=a}, []} = parse([{field11, a}], Spec),
    {ok, #{field11:=<<"b">>}, []} = parse([{field11, b}], Spec),

    {ok, #{field12:=[a, b, '3']}, []} = parse(#{field12 => [a, "b", 3]}, Spec),

    {error, {syntax_error, <<"field13">>}} = parse([{field13, kkk383838}], Spec),
    {ok, #{field13:=string}, []} = parse([{field13, string}], Spec),
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

    {error, {syntax_error, <<"field1">>}} = parse(#{field1=>[]}, Spec),
    {error, {syntax_error, <<"field2">>}} = parse(#{field2=>1}, Spec),
    {ok, #{field1:=1}, [<<"fieldX">>]} = parse(#{field1=>1, fieldX=>a}, Spec),
    {ok, #{field2:=#{}}, []} = parse(#{field2=>#{}}, Spec),
    {error, {syntax_error, <<"field2.field4">>}} = parse(#{field2=>#{field4=>a}}, Spec),

    {ok, #{field2 := #{field4 := 2}}, [<<"field2.fieldX">>]} = parse(#{field2=>#{field4=>2, fieldX=>3}}, Spec),

    {ok,
        #{field1 := 1, field2 := #{field4 := 2, field5 := #{field6 := <<"a">>}}},
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

    Def = #{
        '__defaults' => #{field1=>11, field2=>#{}},
        field2=> #{
            '__defaults' => #{field3=>a, field5=>#{}},
            field5 => #{
                '__defaults' => #{field6=>b}
            }
        }
    },
    Spec2 = nklib_util:map_merge(Def, Spec),

    {ok, #{field1:=11, field2:=#{field3:=<<"a">>, field5:=#{field6:=<<"b">>}}}, []} =parse(#{}, Spec2),

    {ok, #{field1:=12, field2:=#{field3:=<<"a">>, field5:=#{field6:=<<"b">>}}}, []} = parse(#{field1=>12}, Spec2),

    {ok,
        #{
            field1:=12,
            field2:=#{field3:=<<"a">>, field4:=5, field5:=#{field6:=<<"b">>}}},
        []
    } =
        parse(#{field1=>12, field2=>#{field4=>5}}, Spec2),

    {ok,
        #{
            field1:=12,
            field2:=#{field3:=<<"a">>, field4:=5, field5:=#{field6:=<<"f">>}}},
        [<<"field2.field5.fieldX">>]
    } =
        parse(#{field1=>12, field2=>#{field4=>5, field5=>#{field6=>f, fieldX=>1}}}, Spec2),

    Mand = #{
        '__mandatory' => [field1, field2],
        field2 => #{
            '__mandatory' => [field4, field5],
            field5 => #{
                '__mandatory' => [field6]
            }
        }
    },
    Spec3 = nklib_util:map_merge(Spec, Mand),

    {error, {field_missing, <<"field1">>}} = parse(#{}, Spec3),
    {error, {field_missing, <<"field2">>}} = parse(#{field1=>1}, Spec3),
    {error, {field_missing, <<"field2.field4">>}} = parse(#{field1=>1, field2=>#{}}, Spec3),
    {error, {field_missing, <<"field2.field5">>}} = parse(#{field1=>1, field2=>#{field4=>22}}, Spec3),
    {error, {field_missing, <<"field2.field5.field6">>}} = parse(#{field1=>1, field2=>#{field4=>22, field5=>#{}}}, Spec3),
    {ok, _, []} = parse(#{field1=>1, field2=>#{field4=>22, field5=>#{field6=>33}}}, Spec3),

    Spec4 = nklib_util:map_merge(Spec3, Def),
    {error, {field_missing, <<"field2.field4">>}} = parse(#{}, Spec4),

    {ok, _, _} = parse(#{field2=>#{field4=>22}}, Spec4),
    ok.


parse4_test() ->
    Spec = #{
        field2 =>
        {list,
            #{
                field3 => binary,
                field4 => integer
            }
        }
    },

    {ok,
        #{field2 :=
            [
                #{field3 := <<"a">>},
                #{field4 := 1},
                #{}
            ]}=Res1,
        [<<"field2.fieldX">>]
    } =
        parse(#{<<"field2">>=>[#{<<"field3">>=>a, fieldX=>1}, #{field4=>1}, #{}]}, Spec),

    {error, {syntax_error, <<"field2.field4">>}} =
        parse(#{field2=>[#{field3=>a, fieldX=>1}, #{field4=>1}, #{field4=>a}]}, Spec),

    {error, {syntax_error, <<"base.field2.field4">>}} =
        parse(#{field2=>[#{field3=>a, fieldX=>1}, #{field4=>1}, #{field4=>a}]}, Spec, #{path=><<"base">>}),

    {ok, Res1, [<<"base.field2.fieldX">>]} =
        parse(#{field2=>[#{field3=>a, fieldX=>1}, #{field4=>1}, #{}]}, Spec, #{path=><<"base">>}),

    Spec2 = #{
        <<"field2">> =>
        {list,
            #{
                field3 => binary,
                <<"field4">> => integer
            }
        }
    },

    {ok,
        #{<<"field2">> :=
            [
                #{field3 := <<"a">>},
                #{<<"field4">> := 1},
                #{}
            ]},
        [<<"field2.fieldX">>]
    } =
        parse(#{<<"field2">>=>[#{<<"field3">>=>a, fieldX=>1}, #{field4=>1}, #{}]}, Spec2),


    Spec3 = #{
        <<"field2">> =>
        {list,
            #{
                field3 => binary,
                <<"field4">> => integer,
                '__mandatory' => [<<"field4">>]
            }
        },
        '__mandatory' => [<<"field2">>]
    },

    {error, {field_missing, <<"field2">>}} = parse(#{}, Spec3),
    {error, {field_missing, <<"field2.field4">>}} = parse(#{field2=>#{}}, Spec3),
    {error, {field_missing, <<"field2.field4">>}} = parse(#{field2=>[#{field3=>a}]}, Spec3),
    {error, {field_missing, <<"field2.field4">>}} = parse(#{field2=>[#{field4=>1}, #{}]}, Spec3),
    {ok, #{<<"field2">> := [#{<<"field4">> := 1}]}, []} = parse(#{field2=>[#{field4=>1}]}, Spec3),
    {error, {field_missing, <<"base.field2.field4">>}} = parse(#{field2=>#{}}, Spec3, #{path=><<"base">>}),

    Spec4 = #{
        <<"field2">> =>
        {list,
            #{
                field3 => binary,
                <<"field4">> => integer,
                '__mandatory' => [<<"field4">>],
                '__defaults' => #{field3=>t1}
            }
        },
        '__mandatory' => [<<"field2">>]
    },

    {ok,
        #{
            <<"field2">> := [
                #{field3 := <<"t1">>,<<"field4">> := 1},
                #{field3 := <<"a">>,<<"field4">> := 2}
            ]
        },
        []
    } =
        parse(#{field2=>[#{field4=>1}, #{field4=>2, field3=>a}]}, Spec4),
    ok.


parse_fun(field10, data, _Opts) ->
    {ok, data1}.



    -endif.




