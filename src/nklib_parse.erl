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
%% headers, uris, vias, etc.

-module(nklib_parse).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([uris/1, ruris/1, tokens/1, integers/1, dates/1, scheme/1, name/1]).
-export([unquote/1, path/1, fullpath/1]).

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


%% @doc Adds starting "/" and removes ending "/"
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





