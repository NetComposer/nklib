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

%% @private NkLIB main supervisor
-module(nklib_sup).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(supervisor).

-export([init/1, start_link/0]).

%% @private
start_link() ->
    ChildsSpec = [
        {nklib_config,
            {nklib_config, start_link, []},
            permanent,
            5000,
            worker,
            [nklib_config]},
        {nklib_i18n,
            {nklib_i18n, start_link, []},
            permanent,
            5000,
            worker,
            [nklib_i18n]},
        {nklib_proc,
            {nklib_proc, start_link, []},
            permanent,
            5000,
            worker,
            [nklib_proc]},
        {nklib_counters,
            {nklib_counters, start_link, []},
            permanent,
            5000,
            worker,
            [nklib_counters]},
        {nklib_store,
            {nklib_store, start_link, []},
            permanent,
            5000,
            worker,
            [nklib_store]}
     ],
    supervisor:start_link({local, ?MODULE}, ?MODULE, {{one_for_one, 10, 60}, ChildsSpec}).


%% @private
init(ChildSpecs) ->
    {ok, ChildSpecs}.



