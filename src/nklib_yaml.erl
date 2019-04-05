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

%% @doc YAML Processing
-module(nklib_yaml).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([decode/1]).


%% ===================================================================
%% Types
%% ===================================================================




%% ===================================================================
%% Public
%% ===================================================================


%% @doc Encodes a term() to YAML
%%-spec encode(term()) ->
%%    binary() | error.

%% TODO
%%encode(Term) ->


%% @doc Decodes a YAML as a map
-spec decode(binary()|iolist()) ->
    term() | error.

decode(Term) when is_binary(Term) ->
    decode(unicode:characters_to_list(Term));

decode(Term) when is_list(Term) ->
    try
        case yamerl:decode(Term, [{map_node_format, map}, str_node_as_binary]) of
            [_|_]=Docs ->
                {ok, Docs};
            Other ->
                {error, Other}
        end
    catch
        _:Error ->
            {error, Error}
    end.
