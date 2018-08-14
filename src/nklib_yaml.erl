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

%% @doc JSON Processing
-module(nklib_yaml).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([decode/1, test/0]).


%% ===================================================================
%% Types
%% ===================================================================




%% ===================================================================
%% Public
%% ===================================================================


%% @doc Decodes a YAML as a maps and binaries
-spec decode(binary()|iolist()) ->
    [map()].

decode(Term) ->
    try yamerl_constr:string(Term) of
        Objs ->
            parse_decoded_list(Objs, [])
    catch
        error:Error:Trace ->
           lager:debug("Error decoding YAML: ~p (~~) (~p)", [Error, Term, Trace]),
            error({yaml_decode_error, Error});
        throw:
            {yamerl_exception, [
                {yamerl_parsing_error, error, Txt, Line, Col, _Code, _, _}
                |_]} ->
            error({yaml_decode_error, {list_to_binary(Txt), Line, Col}});
        throw:Error:Trace ->
            lager:debug("Error decoding YAML: ~p (~~) (~p)", [Error, Term, Trace]),
            error({yaml_decode_error, Error})
    end.


%% @private
parse_decoded_list([], Acc) ->
    case Acc of
        [List] when is_list(List) ->
            List;
        [Tuple] ->
            [Tuple];
        _ ->
            lists:reverse(Acc)
    end;

parse_decoded_list([Obj|Rest], Acc) ->
    case Obj of
        [Tuple|_] when is_tuple(Tuple) ->
            Obj2 = parse_decoded_obj(Obj, []),
            parse_decoded_list(Rest, [Obj2|Acc]);
        [List|_] when is_list(List) ->
            Obj2 = parse_decoded_list(Obj, []),
            parse_decoded_list(Rest, [Obj2|Acc])
    end.



%% @private
parse_decoded_obj([], Acc) ->
    maps:from_list(Acc);

parse_decoded_obj([{Key, Val}|Rest], Acc) ->
    Val2 = case Val of
        [Tuple|_] when is_tuple(Tuple) ->
            parse_decoded_obj(Val, []);
        [List|_] when is_list(List) ->
            parse_decoded_list(Val, []);
        String when is_list(String) ->
            to_bin(String);
        _ ->
            Val
    end,
    parse_decoded_obj(Rest, [{to_bin(Key), Val2}|Acc]).


%% @private
to_bin(List) ->
    unicode:characters_to_binary(List).



%% ===================================================================
%% Tests
%% ===================================================================


test() ->
    test_1(),
    test_2(),
    test_3(),
    ok.


test_1() ->
    Body = <<"
        a: 1
        b:
            b1: 1
            b2:
                - b11: a
                  b12:
                    b121: my word
                    b122:
                        - b1221: a
                          b1222: a
                        - b1223: b
                          b1224: b
    "/utf8>>,
    [#{
        <<"a">> := 1,
        <<"b">> := #{
            <<"b1">> := 1,
            <<"b2">> := [
                #{
                    <<"b11">> := <<"a">>,
                    <<"b12">> := #{
                        <<"b121">> := <<"my word">>,
                        <<"b122">> := [
                            #{<<"b1221">> := <<"a">>,<<"b1222">> := <<"a">>},
                            #{<<"b1223">> := <<"b">>,<<"b1224">> := <<"b">>}
                        ]
                    }
                }
            ]
        }
    }] = decode(Body).


test_2() ->
    Body = <<"
        spec:
            name: 'íé'
            surname: 'my surñame3'
            birthTime: '1970-01-02'
            gender: M
            email:
                - type: main
                  email: email1
                - type: home
                  email: email2
        metadata:
            name: contact4
            fts:
                name: 'íé'
                surname: 'my surñame3'

            links:
                user: /nkdomain-root/nkdomain-core/user/k1
    "/utf8>>,

    [#{
        <<"spec">> := #{
            <<"name">> := <<"íé"/utf8>>,
            <<"surname">> := <<"my surñame3"/utf8>>,
            <<"birthTime">> := <<"1970-01-02">>,
            <<"gender">> := <<"M">>,
            <<"email">> := [
                #{<<"email">> := <<"email1">>,<<"type">> := <<"main">>},
                #{<<"email">> := <<"email2">>,<<"type">> := <<"home">>}
            ]
        },
        <<"metadata">> := #{
            <<"name">> := <<"contact4">>,
            <<"fts">> := #{
                <<"name">> := <<"íé"/utf8>>,
                <<"surname">> := <<"my surñame3"/utf8>>
            },
            <<"links">> := #{
                <<"user">> := <<"/nkdomain-root/nkdomain-core/user/k1">>
            }
        }
    }] = decode(Body).


test_3() ->
    Body = <<"
        - a: 1
          b: 1

        - a: 2
          b:
            - c: 3
    ">>,
    [
        #{<<"a">> := 1,<<"b">> := 1},
        #{<<"a">> := 2,<<"b">> := [#{<<"c">> := 3}]}
    ] = decode(Body).



