%% -------------------------------------------------------------------
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

-module(nklib_reloader).
-export([reload_app/1, remote_reload/2]).


%% @doc Reloads all beams on disk for an app(s)
-spec reload_app(atom()|[atom()]|list()|binary()) ->
    ok.

reload_app([]) ->
    ok;

reload_app([App|Rest]) when is_atom(App) ->
    App2 = nklib_util:to_binary(App),
    Dirs = lists:foldl(
        fun(Path, Acc) ->
            case re:run(Path, App2) of
                {match, _} -> [Path|Acc];
                nomatch -> Acc
            end
        end,
        [],
        code:get_path()),
    lists:foreach(
        fun(Dir) ->
            lists:foreach(
                fun(File) ->
                    Mod = list_to_atom(filename:basename(File, ".beam")),
                    io:format("Reloading ~s...", [Mod]),
                    code:purge(Mod),
                    {module, Mod} = code:load_file(Mod),
                    io:format("ok\n")

                end,
                filelib:wildcard(Dir++"/*.beam"))
        end,
        Dirs),
    reload_app(Rest);

reload_app(App) when is_atom(App) ->
    reload_app([App]);

reload_app(Apps) ->
    List = [nklib_util:to_atom(A) || {A, []} <- nklib_parse:tokens(Apps)],
    reload_app(List).


%% @doc Reloads all beams on disk for an app on a remote node
remote_reload(Node, Apps) ->
    Node2 = nklib_util:to_atom(Node),
    case net_adm:ping(Node2) of
        pong ->
            rpc:call(Node2, ?MODULE, reload_app, [Apps]);
        pang ->
            {error, not_connected}
    end.
