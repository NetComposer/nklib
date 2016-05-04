%% -------------------------------------------------------------------
%%
%% Copyright (c) 2016 Carlos Gonzalez Florido.  All Rights Reserved.
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

%% @doc Common library utility funcions
-module(nklib_log).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([console_loglevel/1]).
-export([debug/0, info/0, notice/0, warning/0, error/0]).


%% @doc Changes log level for console
debug() -> console_loglevel(debug).
info() -> console_loglevel(info).
notice() -> console_loglevel(notice).
warning() -> console_loglevel(warning).
error() -> console_loglevel(error).


%% @doc Changes log level for console
-spec console_loglevel(debug|info|notice|warning|error) ->
    ok.

console_loglevel(Level) -> 
    lager:set_loglevel(lager_console_backend, Level).


