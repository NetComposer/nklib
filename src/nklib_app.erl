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

%% @doc NkLIB OTP Application Module
-module(nklib_app).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(application).

-export([start/0, start/2, stop/1]).

-define(APP, nklib).

%% ===================================================================
%% Private
%% ===================================================================



%% @doc Starts NkLIB stand alone.
-spec start() -> 
    ok | {error, Reason::term()}.

start() ->
    case nklib_util:ensure_all_started(?APP, permanent) of
        {ok, _Started} ->
            ok;
        Error ->
            Error
    end.

%% @private OTP standard start callback
start(_Type, _Args) ->
	code:ensure_loaded(jsx),
	code:ensure_loaded(jiffy),     % We can work without it
    HwAddr = nklib_util:get_hwaddr(),
    application:set_env(?APP, hw_addr, HwAddr),
    spawn(fun() -> maybe_start_reloader() end),
    nklib_sup:start_link().


%% @private OTP standard stop callback
stop(_) ->
    ok.


%% @private
maybe_start_reloader() ->
    timer:sleep(1000),
    case application:get_env(?APP, rebar_reloader_dirs) of
        {ok, Dirs} when is_list(Dirs) ->
            nklib_rebar_reloader:start(Dirs);
        undefined ->
            ok
    end.
