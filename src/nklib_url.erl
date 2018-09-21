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

%% @doc Amazon Web Services utilities
-module(nklib_url).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([encode_utf8/1, encode/1, norm/1]).


%% @private
encode_utf8(Binary) when is_binary(Binary) ->
    encode_utf8(unicode:characters_to_list(Binary));

encode_utf8(Atom) when is_atom(Atom) ->
    encode_utf8(atom_to_binary(Atom, utf8));

encode_utf8(String) ->
    url_encode(String, []).

url_encode([], Acc) ->
    list_to_binary(lists:reverse(Acc));

url_encode([Char|String], Acc)
    when Char >= $A, Char =< $Z;
    Char >= $a, Char =< $z;
    Char >= $0, Char =< $9;
    Char =:= $-; Char =:= $_;
    Char =:= $.; Char =:= $~ ->
    url_encode(String, [Char|Acc]);

url_encode([Char|String], Acc) ->
    url_encode(String, utf8_encode_char(Char) ++ Acc).


%% @private
encode(Binary) when is_binary(Binary) ->
    encode(binary_to_list(Binary));

encode(Atom) when is_atom(Atom) ->
    encode(atom_to_binary(Atom, utf8));

encode(String) ->
    encode(String, []).

encode([], Acc) ->
    list_to_binary(lists:reverse(Acc));

encode([Char|String], Acc)
    when Char >= $A, Char =< $Z;
    Char >= $a, Char =< $z;
    Char >= $0, Char =< $9;
    Char =:= $-; Char =:= $_;
    Char =:= $.; Char =:= $~;
    Char =:= $/ ->
    encode(String, [Char|Acc]);

encode([Char|String], Acc)
    when Char >=0, Char =< 255 ->
    encode(String, [hex_char(Char rem 16), hex_char(Char div 16), $% | Acc]).


%% @private
utf8_encode_char(Char) when Char > 16#FFFF, Char =< 16#10FFFF ->
    encode_char(Char band 16#3F + 16#80)
    ++ encode_char((16#3F band (Char bsr 6)) + 16#80)
        ++ encode_char((16#3F band (Char bsr 12)) + 16#80)
        ++ encode_char((Char bsr 18) + 16#F0);

utf8_encode_char(Char) when Char > 16#7FF, Char =< 16#FFFF ->
    encode_char(Char band 16#3F + 16#80)
    ++ encode_char((16#3F band (Char bsr 6)) + 16#80)
        ++ encode_char((Char bsr 12) + 16#E0);

utf8_encode_char(Char) when Char > 16#7F, Char =< 16#7FF ->
    encode_char(Char band 16#3F + 16#80)
    ++ encode_char((Char bsr 6) + 16#C0);

utf8_encode_char(Char) when Char =< 16#7F ->
    encode_char(Char).

encode_char(Char) ->
    [hex_char(Char rem 16), hex_char(Char div 16), $%].


%% @private
hex_char(C) when C < 10 -> $0 + C;
hex_char(C) when C < 16 -> $A + C - 10.


%% @doc Removes final / if present
norm(Host) ->
    Bin = nklib_util:to_binary(Host),
    case byte_size(Bin)-1 of
        Size when Size =< 1 ->
            Bin;
        Size ->
            case Bin of
                <<Base:Size/binary, "/">> -> Base;
                _ -> Bin
            end
    end.
