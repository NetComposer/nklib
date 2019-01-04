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

%% @doc NetComposer Erlang code parser and hot loader utilities
-module(nklib_code).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([expression/1, getter/2, getter_args/4, fun_expr/4, call_expr/4, callback_expr/3]).
-export([case_expr/5, case_expr_ok/5, export_attr/1, compile/2, do_compile/3, write/3]).
-export([get_funs/1]).
-export([forms_find_attribute/2, forms_add_attributes/2, forms_get_attributes/1,
         forms_find_exported/1, forms_get_funs/1, forms_add_funs/2,
         forms_replace_fun/4, forms_print/1]).

-include_lib("syntax_tools/include/merl.hrl").

%% ===================================================================
%% Private
%% ===================================================================


%% @doc Parses an erlang expression intro a syntaxTree()
%% i.e. expres
-spec expression(string()) ->
    {ok, erl_syntax:syntaxTree()} | error.

expression(Expr) ->
    case erl_scan:string(Expr) of
        {ok, Tokens, _} ->
            case erl_parse:parse_form(Tokens) of
                {ok, Form} -> {ok, Form};
                _ -> error
            end;
        _ ->
            error
    end.


%% @doc Generates a getter function (fun() -> Value.)
-spec getter(atom(), term()) ->
    erl_syntax:syntaxTree().

getter(Fun, Value) ->
    try
        erl_syntax:function(
           erl_syntax:atom(Fun),
           [erl_syntax:clause([], none, [erl_syntax:abstract(Value)])])
    catch
        error:Error -> lager:warning("Could not make getter for ~p", [Value]),
        error(Error)
    end.



%% @doc Generates a getter function (fun(X, Y, Z) -> Value; fun(_, _, _) -> Default
% If Default=none, not catch-all clause will be added
-spec getter_args(atom(), integer(), [{[term()], term()}], term()|none) ->
    erl_syntax:syntaxTree().

getter_args(Fun, Arity, ArgsValues, Default) ->
    try
        erl_syntax:function(
            erl_syntax:atom(Fun),
            [
                erl_syntax:clause(
                    [erl_syntax:abstract(Arg) || Arg <- Args],
                    none, [erl_syntax:abstract(Val)])
                ||
                {Args, Val} <- ArgsValues, length(Args)==Arity
            ]
            ++
            case Default of
                none ->
                    [];
                _ ->
                    [
                        erl_syntax:clause(
                            [erl_syntax:variable('_') || _ <- lists:seq(1,Arity)],
                            none, [erl_syntax:abstract(Default)])
                    ]
            end)
    catch
        error:Error -> lager:warning("Could not make getter for ~p", [ArgsValues]),
            error(Error)
    end.


%% @doc Generates a function expression (fun(A1,B1,..) -> Value)
%% Vers represents the suffix to use in the variable names
-spec fun_expr(atom(), integer(), integer(), term()) ->
    erl_syntax:syntaxTree().

fun_expr(Fun, Arity, Vers, Value) ->
    erl_syntax:function(
        erl_syntax:atom(Fun),
        [erl_syntax:clause(var_list(Arity, Vers), none, Value)]).


%% @doc Generates a call expression (mod:fun(A1,B1,..))
%% Vers represents the suffix to use in the variable names.
-spec call_expr(atom(), atom(), integer(), integer()) ->
    erl_syntax:syntaxTree().

call_expr(Mod, Fun, Arity, Vers) ->
    erl_syntax:application(
        case Mod of none -> none; _ -> erl_syntax:atom(Mod) end,
        erl_syntax:atom(Fun),
        var_list(Arity, Vers)).


%% @doc Generates a call expression (fun(A0,B0...) -> mod:fun(A0,B0,..))
-spec callback_expr(atom(), atom(), integer()) ->
    erl_syntax:syntaxTree().

callback_expr(Mod, Fun, Arity) ->
    fun_expr(Fun, Arity, 0, [call_expr(Mod, Fun, Arity, 0)]).


%% @doc Generates a case expression
%% case mod:fun(A2,B2...) of
%%     continue -> [A1,B1..] = [A2,B2..], (NextCode);
%%     {continue, (NextCode); 
%%     Other -> Other
%% end
%% Vers represents the suffix to use in the variable names.
-spec case_expr(atom(), atom(), integer(), integer(), 
               [erl_syntax:syntaxTree()]) ->
    erl_syntax:syntaxTree().

case_expr(Mod, Fun, Arity, Vers, NextCode) ->
    erl_syntax:case_expr(
        call_expr(Mod, Fun, Arity, Vers),
        [
            erl_syntax:clause(
                [erl_syntax:atom(continue)],
                none,
                case Arity of
                    0 ->
                        NextCode;
                    _ ->
                        [
                            erl_syntax:match_expr(
                                erl_syntax:list(var_list(Arity, Vers-1)),
                                erl_syntax:list(var_list(Arity, Vers)))
                        | NextCode]
                end),
            erl_syntax:clause(
                [erl_syntax:tuple([
                    erl_syntax:atom(continue), 
                    erl_syntax:list(var_list(Arity, Vers-1))])],
                none,
                NextCode),
            erl_syntax:clause(
                [erl_syntax:variable('Other')],
                none,
                [erl_syntax:variable('Other')])
        ]).


%% @doc Generates a case expression
%% case mod:fun(A2,B2) of
%%     ok -> [A1,B1..] = [A2,B2..], (NextCode);
%%     {ok, B1} -> [A1=A2], (NextCode); 
%%     Other -> Other
%% end
%% Vers represents the suffix to use in the variable names.
-spec case_expr_ok(atom(), atom(), integer(), integer(),  
               [erl_syntax:syntaxTree()]) ->
    erl_syntax:syntaxTree().

case_expr_ok(Mod, Fun, 2, Vers, NextCode) ->
    erl_syntax:case_expr(
        call_expr(Mod, Fun, 2, Vers),
        [
            erl_syntax:clause(
                [erl_syntax:atom(ok)],
                none,
                [
                    erl_syntax:match_expr(
                        erl_syntax:list(var_list(2, Vers-1)),
                        erl_syntax:list(var_list(2, Vers)))
                | NextCode]),
            erl_syntax:clause(
                [erl_syntax:tuple([
                    erl_syntax:atom(ok), 
                    erl_syntax:variable([$B|integer_to_list(Vers-1)])])],
                none,
                [
                    erl_syntax:match_expr(
                        erl_syntax:list(var_list(1, Vers-1)),
                        erl_syntax:list(var_list(1, Vers)))
                | NextCode]),
            erl_syntax:clause(
                [erl_syntax:variable('Other')],
                none,
                [erl_syntax:variable('Other')])
        ]).


%% @doc
export_attr(List) ->
    erl_syntax:attribute(
        erl_syntax:atom(export),
        [erl_syntax:list(
            [
                erl_syntax:arity_qualifier(
                    erl_syntax:atom(Name), erl_syntax:integer(Arity))
                || {Name, Arity} <- List
            ]
        )]).


%% @doc Compiles a syntaxTree into a module
-spec compile(atom(), [erl_syntax:syntaxTree()]) ->
    ok | {error, term()}.

compile(Mod, Tree) ->
    Tree1 = [
        erl_syntax:attribute(
            erl_syntax:atom(module),
            [erl_syntax:atom(Mod)]),
        erl_syntax:attribute(
            erl_syntax:atom(compile),
            [erl_syntax:list([erl_syntax:atom(nowarn_export_all)])]),
        erl_syntax:attribute(
            erl_syntax:atom(compile),
            [erl_syntax:list([erl_syntax:atom(export_all)])])
        | Tree
    ],
    do_compile(Mod, Tree1, [report_errors, report_warnings, return_errors]).



%% @doc Compiles a syntaxTree into a module
-spec do_compile(atom(), [erl_syntax:syntaxTree()], list()) ->
    ok | {error, term()}.

do_compile(Mod, Tree, Opts) ->
%%    io:format("\nGenerated ~p:\n\n", [Mod]),
%%    [io:format("~s\n\n", [erl_prettypr:format(S)]) || S<-Tree],
    Forms1 = [erl_syntax:revert(X) || X <- Tree],
    case compile:noenv_forms(Forms1, Opts) of
        {ok, Mod, Bin} ->
            code:purge(Mod),
            File = atom_to_list(Mod)++".erl",
            case code:load_binary(Mod, File, Bin) of
                {module, Mod} ->
                    {ok, Tree};
                Error ->
                    {error, Error}
            end;
        Error ->
            {error, Error}
    end.




%% @doc Writes a generated tree as a standard erlang file
-spec write(atom(), [erl_syntax:syntaxTree()], string()) ->
    ok | {error, term()}.

write(Mod, Tree, BasePath) ->
    Path = filename:join(BasePath, nklib_util:to_list(Mod)++".erl"),
    Content = list_to_binary(
        [io_lib:format("~s\n\n", [erl_prettypr:format(S)]) || S <-Tree]),
    file:write_file(Path, Content).


%% @doc Gets the list of exported functions of a module
-spec get_funs(atom()) ->
    [{atom(), integer()}] | error.

get_funs(Mod) ->
    case catch Mod:module_info() of
        List when is_list(List) ->
            lists:foldl(
                fun({Fun, Arity}, Acc) ->
                    case Fun of
                        module_info -> Acc;
                        behaviour_info -> Acc;
                        _ -> [{Fun, Arity}|Acc]
                    end
                end,
                [],
                nklib_util:get_value(exports, List));
        _ ->
            error
    end.





%% ===================================================================
%% Forms utilities
%% ===================================================================


%% @doc Finds the module attribute
forms_find_attribute(_Key, []) ->
    undefined;

forms_find_attribute(Key, [{attribute, _, Key, Value}|_]) ->
    Value;

forms_find_attribute(Key, [_|Rest]) ->
    forms_find_attribute(Key, Rest).


%% @private Adds an attribute at the end of the attribute list
forms_add_attributes(Attrs, Forms) ->
    forms_add_attributes(Forms, Attrs, []).


%% @private
forms_add_attributes([{attribute, _, _, _}=Attr|Rest], Attrs, Acc) ->
    forms_add_attributes(Rest, Attrs, [Attr|Acc]);

forms_add_attributes(Rest, Attrs, Acc) ->
    lists:reverse(Acc) ++ Attrs ++ Rest.


%% @private Gets all attributes
forms_get_attributes(Forms) ->
    forms_get_attributes(Forms, []).


%% @private
forms_get_attributes([], Acc) ->
    lists:reverse(Acc);

forms_get_attributes([{attribute, _, _, _}=Attr|Rest], Acc) ->
    forms_get_attributes(Rest, [Attr|Acc]);

forms_get_attributes([_|Rest], Acc) ->
    forms_get_attributes(Rest, Acc).


%% @private Finds all exported functions
forms_find_exported(Forms) ->
    forms_find_exported(Forms, []).


forms_find_exported([], Acc) ->
    Acc;

forms_find_exported([{attribute, _, export, List}|Rest], Acc) ->
    forms_find_exported(Rest, Acc++List);

forms_find_exported([_|Rest], Acc) ->
    forms_find_exported(Rest, Acc).



%% @private Gets all defined funs
forms_get_funs(Forms) ->
    forms_get_funs(Forms, #{}).


%% @private
forms_get_funs([], Acc) ->
    Acc;

forms_get_funs([{function, _Line, Name, Arity, Spec}|Rest], Acc) ->
    forms_get_funs(Rest, Acc#{{Name, Arity}=>Spec});

forms_get_funs([_|Rest], Acc) ->
    forms_get_funs(Rest, Acc).


%% @private Adds a number of funs at the end of the module
%% Funs must be [{function, ...}]
forms_add_funs(Funs, Forms) ->
    forms_add_funs(Forms, Funs, []).


%% @private
forms_add_funs([{eof, _}|_]=End, Funs, Acc) ->
    lists:reverse(Acc) ++ Funs ++ End;

forms_add_funs([Term|Rest], Funs, Acc) ->
    forms_add_funs(Rest, Funs, [Term|Acc]).


%% @private
forms_replace_fun(Name, Arity, Spec, Forms) ->
    forms_replace_fun(Forms, Name, Arity, Spec, []).


%% @private
forms_replace_fun([], _Name, _Arity, _Spec, Acc) ->
    lists:reverse(Acc);

forms_replace_fun([{function, _Line, Name, Arity, _}|Rest], Name, Arity, Spec, Acc) ->
    forms_replace_fun(Rest, Name, Arity, Spec, [Spec|Acc]);

forms_replace_fun([Other|Rest], Name, Arity, Spec, Acc) ->
    forms_replace_fun(Rest, Name, Arity, Spec,  [Other|Acc]).


%% @private
forms_print(Forms) ->
    Content = list_to_binary([io_lib:format("~s\n\n", [erl_prettypr:format(S)]) || S <- Forms]),
    io:format("Forms: \n~s\n", [Content]).



%% ===================================================================
%% Internal
%% ===================================================================


%% @private Generates a var list (A1,B1..)
var_list(Arity, Vers) ->
    VersS = nklib_util:to_list(Vers),
    [erl_syntax:variable([V|VersS]) || V <- lists:seq(65, 64+Arity)].




