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
    Fun = fun() ->
        case yamerl:decode(Term, [{map_node_format, map}, str_node_as_binary]) of
            [[_|_]=Res|[]] ->
                % If the response is a list of a single list, then return the inner list
                Res;
            Res ->
                Res
        end
    end,
    case nklib_util:do_try(Fun) of
        {exception, {error, {Error, Trace}}} ->
           lager:debug("Error decoding YAML: ~p (~p) (~p)", [Error, Term, Trace]),
            error({yaml_decode_error, Error});
        {exception, {throw,
            {yamerl_exception, [
                {yamerl_parsing_error, error, Txt, Line, Col, _Code, _, _}
                |_]}}} ->
            error({yaml_decode_error, {list_to_binary(Txt), Line, Col}});
        {exception, {throw, {Error, Trace}}} ->
            lager:debug("Error decoding YAML: ~p (~p) (~p)", [Error, Term, Trace]),
            error({yaml_decode_error, Error});
        Other ->
            Other
    end.


%% ===================================================================
%% Tests
%% ===================================================================


test() ->
    test_1(),
    test_2(),
    test_3(),
    test_4(),
    test_5(),
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


test_4() ->
    Body1 = <<"list: [a, b, 2, true, null]">>,
    [#{<<"list">> := [<<"a">>,<<"b">>, 2, true, null]}] = Res1 = decode(Body1),
    Body2 = <<"
    list:
        - a
        - b
        - 2
        - true
        - null
    ">>,
    Res1 = decode(Body2),
    ok.


test_5() ->
    Body = <<"
    a: []
    b: \"\"
    ">>,
    [#{<<"a">> := [], <<"b">> := <<>>}] = decode(Body),
    ok.
