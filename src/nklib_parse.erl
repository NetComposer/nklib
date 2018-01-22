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

%% @doc Generic parsing functions
%%
%% This module implements several functions to parse sip requests, responses
%% headers, uris, etc.

-module(nklib_parse).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([uris/1, ruris/1, tokens/1, integers/1, dates/1, scheme/1, name/1]).
-export([unquote/1, path/1, basepath/1, fullpath/1]).
-export([normalize/1, normalize/2, normalize_words/1, normalize_words/2]).

-include("nklib.hrl").


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Parses all URIs found in `Term'.
-spec uris(Term :: nklib:user_uri() | [nklib:user_uri()]) -> 
    [nklib:uri()] | error.
                
uris(#uri{}=Uri) -> [Uri];
uris([#uri{}=Uri]) -> [Uri];
uris(<<>>) -> [];
uris([]) -> [];
uris([First|_]=String) when is_integer(First) -> uris([String]);    % It's a string
uris(List) when is_list(List) -> parse_uris(List, []);
uris(Term) -> uris([Term]).



%% @doc Parses all URIs found in `Term' as Request-URIs
-spec ruris(Term :: nklib:user_uri() | [nklib:user_uri()]) -> 
    [nklib:uri()] | error.
                
ruris(RUris) -> 
    case uris(RUris) of
        error -> error;
        Uris -> parse_ruris(Uris, [])
    end.


%% @doc Gets a list of `tokens()' from `Term'
-spec tokens(Term :: binary() | string() | [binary() | string()]) -> 
    [nklib:token()] | error.

tokens(<<>>) -> [];
tokens([<<>>]) -> [];
tokens([]) -> [];
tokens([First|_]=String) when is_integer(First) -> tokens([String]);  
tokens(List) when is_list(List) -> parse_tokens(List, []);
tokens(Term) -> tokens([Term]).


%% @doc Gets a list of `integer()' from `Term'
-spec integers(Term :: binary() | string() | [binary() | string()]) -> 
    [integer()] | error.

integers([]) -> [];
integers([First|_]=String) when is_integer(First) -> integers([String]);  
integers(List) when is_list(List) -> parse_integers(List, []);
integers(Term) -> integers([Term]).


%% @doc Gets a list of `calendar:datetime()' from `Term'
-spec dates(Term :: binary() | string() | [binary() | string()]) -> 
    [calendar:datetime()] | error.

dates([]) -> [];
dates([First|_]=String) when is_integer(First) -> dates([String]);  
dates(List) when is_list(List) -> parse_dates(List, []);
dates(Term) -> dates([Term]).


%% @private
-spec scheme(term()) ->
    nklib:scheme().

scheme(Atom) when is_atom(Atom) -> 
    Atom;
scheme(Other) ->
    Lower = string:to_lower(nklib_util:to_list(Other)),
    case catch list_to_existing_atom(Lower) of
        Atom when is_atom(Atom) -> Atom;
        _ -> list_to_binary(Other)
    end.


%% @doc Converts anything to a valid header name (lowercase, no $_)
-spec name(atom()|list()|binary()) ->
    binary().

name(Name) when is_binary(Name) ->
    << 
        << (case Ch>=$A andalso Ch=<$Z of true -> Ch+32; false -> Ch end) >> 
        || << Ch >> <= Name 
    >>;

name(Name) when is_atom(Name) ->
    List = [
        case Ch of 
            $_ -> $-; 
            _ when Ch>=$A, Ch=<$Z -> Ch+32;
            _ -> Ch 
        end 
        || Ch <- atom_to_list(Name)
    ],
    list_to_binary(List);

name(Name) when is_list(Name) ->
    name(list_to_binary(Name)).


%% @doc Removes leading and trailing \" if present
-spec unquote(list()|binary()) ->
    binary() | error.

unquote(List) when is_list(List) ->
    unquote(list_to_binary(List));

unquote(<<$", Rest1/binary>>) ->
    L = (byte_size(Rest1)-1),
    case Rest1 of
        <<Rest2:L/binary, $">> -> Rest2;
        _ -> error
    end;

unquote(Bin) when is_binary(Bin) ->
    Bin;

unquote(_) ->
    error.


%% @doc Adds starting "/" and removes ending "/". If empty, stays empty
-spec path(string()|binary()|iolist()) ->
    binary().

path(List) when is_list(List) ->
    path(list_to_binary(List));
path(<<>>) ->
    <<>>;
path(Bin) when is_binary(Bin) ->
    Bin1 = case Bin of
        <<"/", _/binary>> -> Bin;
        _ -> <<"/", Bin/binary>>
    end,
    case byte_size(Bin1)-1 of
        0 ->
            Bin1;
        Size ->
            case Bin1 of
                <<Base:Size/binary, "/">> -> Base;
                _ -> Bin1
            end
    end.


%% @doc Like path but will never end in /, even if "/" or empty
-spec basepath(string()|binary()|iolist()) ->
    binary().

basepath(List) when is_list(List) ->
    basepath(list_to_binary(List));
basepath(<<>>) ->
    <<>>;
basepath(<<"/">>) ->
    <<>>;
basepath(Other) ->
    path(Other).



%% @doc Processes full path with "." and ".."
-spec fullpath(string()|binary()) ->
    binary().

fullpath(Path) ->
    fullpath(filename:split(nklib_util:to_binary(Path)), []).

%% @private
fullpath([], Acc) ->
    filename:join(lists:reverse(Acc));
fullpath([<<".">>|Tail], Acc) ->
    fullpath(Tail, Acc);
fullpath([<<"..">>|Tail], [_]=Acc) ->
    fullpath(Tail, Acc);
fullpath([<<"..">>|Tail], [_|Acc]) ->
    fullpath(Tail, Acc);
fullpath([Segment|Tail], Acc) ->
    fullpath(Tail, [Segment|Acc]).


%% ===================================================================
%% Internal
%% ===================================================================

%% @private
-spec parse_uris([#uri{}|binary()|string()], [#uri{}]) ->
    [#uri{}] | error.

parse_uris([], Acc) ->
    Acc;

parse_uris([Next|Rest], Acc) ->
    case nklib_parse_uri:uris(Next) of
        error -> error;
        UriList -> parse_uris(Rest, Acc++UriList)
    end.


%% @private
-spec parse_ruris([#uri{}], [#uri{}]) ->
    [#uri{}] | error.

parse_ruris([], Acc) ->
    lists:reverse(Acc);

parse_ruris([#uri{opts=[], headers=[], ext_opts=Opts}=Uri|Rest], Acc) ->
    parse_uris(Rest, [Uri#uri{opts=Opts, ext_opts=[], ext_headers=[]}|Acc]);

parse_ruris(_, _) ->
    error.


%% @private
-spec parse_tokens([binary()|string()], [nklib:token()]) ->
    [nklib:token()] | error.

parse_tokens([], Acc) ->
    Acc;

parse_tokens([Next|Rest], Acc) ->
    case nklib_parse_tokens:tokens(Next) of
        error -> error;
        TokenList -> parse_tokens(Rest, Acc++TokenList)
    end.


%% @private
-spec parse_integers([binary()|string()], [integer()]) ->
    [integer()] | error.

parse_integers([], Acc) ->
    Acc;

parse_integers([Next|Rest], Acc) ->
    case catch list_to_integer(string:strip(nklib_util:to_list(Next))) of
        {'EXIT', _} -> error;
        Integer -> parse_integers(Rest, Acc++[Integer])
    end.


%% @private
-spec parse_dates([binary()|string()], [calendar:datetime()]) ->
    [calendar:datetime()] | error.

parse_dates([], Acc) ->
    Acc;

parse_dates([Next|Rest], Acc) ->
    Base = string:strip(nklib_util:to_list(Next)),
    case lists:reverse(Base) of
        "TMG " ++ _ ->               % Should be in "GMT"
            case catch httpd_util:convert_request_date(Base) of
                {_, _} = Date -> parse_dates(Rest, Acc++[Date]);
                _ -> error
            end;
        _ ->
            error
    end.


-type norm_opts() ::
    #{
        space => allowed | skip | integer(),
        unrecognized => skip | keep | integer(),
        allowed => [integer()]
    }.


%% @doc Normalizes a value into a lower-case, using only a-z, 0-9 and spaces
%% All other values are converted into these if possible (Ä->a, é->e, etc.)
%% Utf8 and Latin-1 encodings are supported
%% Unrecognized values are skipped or converted into something else
%% See Options
-spec normalize(string()|binary()) ->
    binary().

normalize(Text) ->
    normalize(Text, #{}).


%% @doc
-spec normalize(string()|binary(), norm_opts()) ->
    binary().

normalize(Text, Opts) ->
    String = norm(nklib_util:to_list(Text), Opts, []),
    list_to_binary(String).


%% @private
norm([], _Opts, Acc) ->
    lists:reverse(string:strip(Acc));

norm([32|T], Opts, Acc) ->
    case maps:get(space, Opts, allowed) of
        allowed ->
            norm(T, Opts, [32|Acc]);
        skip ->
            norm(T, Opts, Acc);
        Char when is_integer(Char) ->
            norm(T, Opts, [Char|Acc])
    end;

%%norm([$_|T], Opts, Acc) ->
%%    case maps:get(underscore, Opts, $-) of
%%        allowed ->
%%            norm(T, Opts, [$_|Acc]);
%%        skip ->
%%            norm(T, Opts, Acc);
%%        Char when is_integer(Char) ->
%%            norm(T, Opts, [Char|Acc])
%%    end;

norm([H|T], Opts, Acc) when H >= $0, H =< $9 ->
    norm(T, Opts, [H|Acc]);

norm([H|T], Opts, Acc) when H >= $a, H =< $z ->
    norm(T, Opts, [H|Acc]);

norm([H|T], Opts, Acc) when H >= $A, H =< $Z ->
    norm(T, Opts, [H+32|Acc]);

%% UTF-8
norm([16#c3, U|T], Opts, Acc) when U >= 16#80, U =< 16#bc->
    L = if
        U >= 16#80, U =< 16#86 -> $a;
        U == 16#87 -> $c;
        U >= 16#88, U =< 16#8b -> $e;
        U >= 16#8c, U =< 16#8f -> $i;
        U == 16#90 -> $d;
        U == 16#91 -> $n;
        U >= 16#92, U =< 16#96 -> $o;
        U == 16#98 -> $o;
        U >= 16#99, U =< 16#9c -> $u;
        U == 16#9D -> $y;
        U == 16#9F -> $b;
        U >= 16#a0, U =< 16#a6 -> $a;
        U == 16#a7 -> $c;
        U >= 16#a8, U =< 16#ab -> $e;
        U >= 16#ac, U =< 16#af -> $i;
        U == 16#b0 -> $d;
        U == 16#b1 -> $n;
        U >= 16#b2, U =< 16#b6 -> $o;
        U == 16#b8 -> $o;
        U >= 16#b9, U =< 16#bc -> $u;
        U == 16#bd -> $y;
        U == 16#bf -> $y;
        true -> norm_unrecognized(Opts)
    end,
    case L of
        skip ->
            norm(T, Opts, Acc);
        keep ->
            norm(T, Opts, [U, 16#c3|Acc]);
        _ ->
            norm(T, Opts, [L|Acc])
    end;

%% Latin-1
%% (16#c3 is Atilde in latin-1, it could be confused as such)
norm([H|T], Opts, Acc) when H >= 16#c0 ->
    L = if
        H >= 16#c0, H =< 16#c6 -> $a;
        H == 16#c7 -> $c;
        H >= 16#c8, H =< 16#cb -> $e;
        H >= 16#cc, H =< 16#cf -> $i;
        H == 16#d0 -> $d;
        H == 16#d1 -> $n;
        H >= 16#d2, H =< 16#d6 -> $o;
        H == 16#d8-> $o;
        H >= 16#d9, H =< 16#dc -> $u;
        H == 16#dd-> $y;
        H == 16#df-> $b;
        H >= 16#e0, H =< 16#e6 -> $a;
        H == 16#e7 -> $c;
        H >= 16#e8, H =< 16#eb -> $e;
        H >= 16#ec, H =< 16#ef -> $i;
        H == 16#f0 -> $d;
        H == 16#f1 -> $n;
        H >= 16#f2, H =< 16#f6 -> $o;
        H == 16#f8-> $o;
        H >= 16#f9, H =< 16#fc -> $u;
        H == 16#fd -> $y;
        H == 16#ff -> $y;
        true -> norm_unrecognized(Opts)
    end,
    case L of
        skip ->
            norm(T, Opts, Acc);
        keep ->
            norm(T, Opts, [H|Acc]);
        _ ->
            norm(T, Opts, [L|Acc])
    end;

norm([Char|T], Opts, Acc) ->
    Allowed = maps:get(allowed, Opts, []),
    case lists:member(Char, Allowed) of
        true ->
            norm(T, Opts, [Char|Acc]);
        false ->
            case norm_unrecognized(Opts) of
                skip ->
                    norm(T, Opts, Acc);
                keep ->
                    norm(T, Opts, [Char|Acc]);
                New ->
                    norm(T, Opts, [New|Acc])
            end
    end.


%% @private
norm_unrecognized(Opts) ->
    case maps:get(unrecognized, Opts, skip) of
        skip ->
            skip;
        keep ->
            keep;
        Char when is_integer(Char) ->
            Char
    end.


-type norm_words_opts() ::
    norm_opts() | #{split => binary()}.


%% @doc
-spec normalize_words(string()|binary()) ->
    [binary()].

normalize_words(Text) ->
    normalize_words(Text, #{}).


%% @doc
-spec normalize_words(string()|binary(), norm_words_opts()) ->
    [binary()].

normalize_words(Text, Opts) ->
    String = norm(nklib_util:to_list(Text), Opts, []),
    Chars = maps:get(split, Opts, [32, $., $/, $-, $_, $,, $;, $:]),
    norm_split(String, Chars, false, [], []).

norm_split([], _Chars, _Skipping, [], Acc2) ->
    lists:reverse(Acc2);

norm_split([], _Chars, _Skipping, Acc1, Acc2) ->
    Word = list_to_binary(lists:reverse(Acc1)),
    lists:reverse([Word|Acc2]);

norm_split([Char|Rest], Chars, false, Acc1, Acc2) ->
    case lists:member(Char, Chars) of
        true when Acc1==[] ->
            norm_split(Rest, Chars, true, [], Acc2);
        true ->
            Word = list_to_binary(lists:reverse(Acc1)),
            norm_split(Rest, Chars, true, [], [Word|Acc2]);
        false ->
            norm_split(Rest, Chars, false, [Char|Acc1], Acc2)
    end;

norm_split([Char|Rest], Chars, true, [], Acc2) ->
    case lists:member(Char, Chars) of
        true ->
            norm_split(Rest, Chars, true, [], Acc2);
        false ->
            norm_split(Rest, Chars, false, [Char], Acc2)
    end.






%% ===================================================================
%% EUnit tests
%% ===================================================================

%-define(TEST, true).
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").


norm_test() ->
    S1 = <<"aáàäâeéèëêiíìïîoòóöôuúùüûñçAÁÀÄÂEÉÈËÊIÍÌÏÎOÒÓÖÔUÚÙÜÛÑÇ">>,
    <<"aaaaaeeeeeiiiiiooooouuuuuncaaaaaeeeeeiiiiiooooouuuuunc">> = normalize(S1),

    S2 = <<"aáàäâeéèëêiíìïîoòóöôuúùüûñçAÁÀÄÂEÉÈËÊIÍÌÏÎOÒÓÖÔUÚÙÜÛÑÇ"/utf8>>,
    <<"aaaaaeeeeeiiiiiooooouuuuuncaaaaaeeeeeiiiiiooooouuuuunc">> = normalize(S2),

    S3 = "a  b",
    <<"a  b">> = normalize(S3),
    <<"ab">> = normalize(S3, #{space=>skip}),
    <<"a__b">> = normalize(S3, #{space=>$_}),
    S4 = "-!",
    <<>> = normalize(S4),
    <<"!">> = normalize(S4, #{allowed=>[$!]}),
    <<"-!">> = normalize(S4, #{allowed=>[$!], unrecognized=>keep}),
    <<"+!">> = normalize(S4, #{allowed=>[$!], unrecognized=>$+}),

    [<<"a">>,<<"bcd">>,<<"ef">>] = normalize_words(".  á //   bcd e.f ;;"),
    [<<"a">>,<<"bcd">>,<<"e">>,<<"f">>] = normalize_words(".  á //   bcd e.f ;;", #{allowed=>[$.]}),



    ok.



-endif.



