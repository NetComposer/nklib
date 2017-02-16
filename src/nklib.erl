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

%% @doc NetComposer Standard Library
-module(nklib).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export_type([domain/0, domain_id/0]).
-export_type([optslist/0, uri/0, user_uri/0, token/0, user_token/0]).
% -export_type([header/0, header_name/0, header_value/0]).
-export_type([scheme/0, code/0]).
-export_type([link/0, lang/0]).

% -export([get_env/2, get_env/3, get_env/4]).

-include("nklib.hrl").



%% ===================================================================
%% Types
%% ===================================================================

%% Internal Name of each started Domain
-type domain() :: term().

%% Internal Name of each started Domain
-type domain_id() :: atom().

%% Generic options list
-type optslist() :: nklib_util:optslist().

%% Parsed SIP Uri
-type uri() :: #uri{}.

%% User specified uri
-type user_uri() :: string() | binary() | uri().

%% Token
-type token() :: {name(), [{name(), value()}]}.

%% User specified token
-type user_token() :: string() | binary() | token().

%% Generic Name
-type name() :: binary() | string() | atom().

% Generic Value
-type value() :: binary() | string() | atom() | integer().

% %% Sip Generic Header Name
% -type header_name() :: name().

% % Util types
% -type header_value() :: 
%     value() | uri() | token() | [value() | uri() | token()]. % Removed via()

% %% SIP Generic Header
% -type header() :: {header_name(), header_value()}.

%% Recognized schemes
-type scheme() :: http | https | ws | wss | sip | sips | tel | mailto | term().

%% HTTP/SIP Response's Code
-type code() :: 100..699.

%% See nklib_links. Last element of tuple may be a pid()
-type link() :: term() | pid() | tuple().

%% Languaje 
-type lang() :: atom().         % en | es ...


%% ===================================================================
%% Public
%% ===================================================================


% %% @doc Equivalent to get_env("NKLIB", App, Key, undefined)
% -spec get_env(atom(), term()) ->
%     term().

% get_env(App, Key) ->
%     get_env("NKLIB", App, Key, undefined).


% %% @doc Equivalent to get_env(Header, App, Key, undefined)
% -spec get_env(list(), atom(), term()) ->
% 	term().

% get_env(Header, App, Key) ->
%     get_env(Header, App, Key, undefined).


% %% @doc Gets a environment value from the applications config values,
% %% the init line or a OS environment.
% -spec get_env(list(), atom(), term(), term()) ->
% 	term().

% get_env(Header, App, Key, Default) ->
%     case application:get_env(App, Key) of
%         {ok, Val} -> 
%             Val; 
%         undefined -> 
%             case init:get_argument(Key) of
%                 {ok, [[Val]]} when is_atom(Default) -> 
%                     case catch list_to_existing_atom(Val) of
%                         {'EXIT', _} -> list_to_binary(Val);
%                         Atom -> Atom
%                     end;
%                 {ok, [[Val]]} when is_integer(Default) -> 
%                     case nklib_util:to_integer(Val) of
%                         error -> list_to_binary(Val);
%                         Int -> Int
%                     end;
%                 {ok, [[Val]]} -> 
%                     list_to_binary(Val);
%                 _ ->
%                     EnvKey = Header ++ "_" ++ 
%                              string:to_upper(nklib_util:to_list(Key)),
%                     case os:getenv(EnvKey) of
%                         false -> Default;
%                         Val -> list_to_binary(Val)
%                      end
%             end
%     end.
