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

%% @doc General message generation functions
-module(nklib_unparse).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([uri/1, uri2/1, uri3/1, token/1, header/1, gen_opts/1]).

-include("nklib.hrl").


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Serializes an `uri()' or list of `uri()' into a `binary()'
-spec uri(nklib:uri() | [nklib:uri()]) ->
    binary().

uri(UriList) when is_list(UriList)->
    nklib_util:bjoin([uri(Uri) || Uri <- UriList]);

uri(#uri{}=Uri) ->
    list_to_binary(raw_uri(Uri)).


%% @doc Serializes an `uri()' or list of `uri()' into a `binary()', using "//" before 
%% the domain name
-spec uri2(nklib:uri() | [nklib:uri()]) ->
    binary().

uri2(UriList) when is_list(UriList) ->
    nklib_util:bjoin([uri2(Uri) || Uri <- UriList]);

uri2(#uri{domain=Domain}=Uri) ->
    list_to_binary(raw_uri(Uri#uri{domain= <<"//", Domain/binary>>})).


%% @private Serializes an `nksip:uri()'  without `<' and `>' as delimiters
%% and no disp, headers or external opts
uri3(UriList) when is_list(UriList) ->
    nklib_util:bjoin([uri3(Uri) || Uri <- UriList]);

uri3(#uri{}=Uri) ->
    list_to_binary(raw_uri3(Uri)).



%% @doc Serializes a list of `token()'
-spec token(nklib:token() | [nklib:token()] | undefined) ->
    binary().

token(undefined) ->
    <<>>;

token({Token, Opts}) ->
    token([{Token, Opts}]);

token(Tokens) when is_list(Tokens) ->
    list_to_binary(raw_tokens(Tokens)).


%% @doc
-spec header(nklib:header_value()) ->
    binary() | {unknown, term()}.

header(Value) ->
    case unparse_header(Value) of
        Binary when is_binary(Binary) -> Binary;
        IoList when is_list(IoList) -> list_to_binary(IoList)
    end.



%% ===================================================================
%% Private
%% ===================================================================


%% @private Serializes an `nklib:uri()', using `<' and `>' as delimiters
-spec raw_uri(nklib:uri()) -> 
    iolist().

raw_uri(#uri{domain=(<<"*">>)}) ->
    [<<"*">>];

raw_uri(#uri{}=Uri) ->
    [
        Uri#uri.disp, $<, nklib_util:to_binary(Uri#uri.scheme), $:,
        case Uri#uri.user of
            <<>> -> <<>>;
            User ->
                case Uri#uri.pass of
                    <<>> -> [User, $@];
                    Pass -> [User, $:, Pass, $@]
                end
        end,
        Uri#uri.domain, 
        case Uri#uri.port of
            0 -> [];
            Port -> [$:, integer_to_list(Port)]
        end,
        Uri#uri.path,
        gen_opts(Uri#uri.opts),
        gen_headers(Uri#uri.headers),
        $>,
        gen_opts(Uri#uri.ext_opts),
        gen_headers(Uri#uri.ext_headers)
    ].


%% @private Serializes an `nksip:uri()'  without `<' and `>' as delimiters
%% and no disp, headers or external opts
-spec raw_uri3(nksip:uri()) -> 
    iolist().

raw_uri3(#uri{}=Uri) ->
    [
        nklib_util:to_binary(Uri#uri.scheme), $:,
        case Uri#uri.user of
            <<>> -> <<>>;
            User ->
                case Uri#uri.pass of
                    <<>> -> [User, $@];
                    Pass -> [User, $:, Pass, $@]
                end
        end,
        Uri#uri.domain, 
        case Uri#uri.port of
            0 -> [];
            Port -> [$:, integer_to_list(Port)]
        end,
        gen_opts(Uri#uri.opts)
    ].


%% @private Serializes a list of `token()'
-spec raw_tokens(nklib:token() | [nklib:token()]) ->
    iolist().

raw_tokens([]) ->
    [];

raw_tokens({Name, Opts}) ->
    raw_tokens([{Name, Opts}]);

raw_tokens(Tokens) ->
    raw_tokens(Tokens, []).


%% @private
-spec raw_tokens([nklib:token()], iolist()) ->
    iolist().

raw_tokens([{Head, Opts}, Second | Rest], Acc) ->
    Head1 = nklib_util:to_binary(Head),
    raw_tokens([Second|Rest], [[Head1, gen_opts(Opts), $,]|Acc]);

raw_tokens([{Head, Opts}], Acc) ->
    Head1 = nklib_util:to_binary(Head),
    lists:reverse([[Head1, gen_opts(Opts)]|Acc]).


%% @private
unparse_header(Value) when is_binary(Value) ->
    Value;

unparse_header(#uri{}=Uri) ->
    raw_uri(Uri);

unparse_header({Name, Opts}) when is_list(Opts) ->
    raw_tokens({Name, Opts});

unparse_header([H|_]=String) when is_integer(H) ->
    String;

unparse_header(List) when is_list(List) ->
    join([unparse_header(Term) || Term <- List], []);

unparse_header(Value) when is_integer(Value); is_atom(Value) ->
    nklib_util:to_binary(Value).


%% @private
join([], Acc) ->
    Acc;

join([A, B | Rest], Acc) ->
    join([B|Rest], [$,, A | Acc]);

join([A], Acc) ->
    lists:reverse([A|Acc]).



%% @private
gen_opts(Opts) ->
    gen_opts(Opts, []).


%% @private
gen_opts([], Acc) ->
    lists:reverse(Acc);
gen_opts([{K, V}|Rest], Acc) ->
    gen_opts(Rest, [[$;, nklib_util:to_binary(K), 
                        $=, nklib_util:to_binary(V)] | Acc]);
gen_opts([K|Rest], Acc) ->
    gen_opts(Rest, [[$;, nklib_util:to_binary(K)] | Acc]).


%% @private
gen_headers(Hds) ->
    gen_headers(Hds, []).


%% @private
gen_headers([], []) ->
    [];
gen_headers([], Acc) ->
    [[_|R1]|R2] = lists:reverse(Acc),
    [$?, R1|R2];
gen_headers([{K, V}|Rest], Acc) ->
    gen_headers(Rest, [[$&, nklib_util:to_binary(K), 
                        $=, nklib_util:to_binary(V)] | Acc]);
gen_headers([K|Rest], Acc) ->
    gen_headers(Rest, [[$&, nklib_util:to_binary(K)] | Acc]).





