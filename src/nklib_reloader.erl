%% -------------------------------------------------------------------
%% Copyright (c) 2019 Carlos Gonzalez Florido.  All Rights Reserved.
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
-export([reload_app/1, remote_reload/2, remote_reload/1, remote_reload_ide/2]).
-export([get_beams/1]).

%% @doc Reloads all beams on disk for an app(s)
-spec reload_app(atom()|[atom()]|list()|binary()) ->
    ok.

reload_app([]) ->
    ok;

reload_app([App|Rest]) when is_atom(App) ->
    Beams = get_beams(App),
    lists:foreach(
        fun({Mod, File, Bin}) ->
            io:format("Reloading ~s...", [Mod]),
            code:purge(Mod),
            {module, Mod} = code:load_binary(Mod, File, Bin),
            io:format("ok\n")
        end,
        Beams),
    reload_app(Rest);

reload_app(App) when is_atom(App) ->
    reload_app([App]);

reload_app(Apps) ->
    List = [nklib_util:to_atom(A) || {A, []} <- nklib_parse:tokens(Apps)],
    reload_app(List).


%% @doc Reloads all beams on disk for an app on a remote node
%% Remote node does not need to have beams on disk. We must.
remote_reload(Node, Apps) ->
    Node2 = nklib_util:to_atom(Node),
    case net_adm:ping(Node2) of
        pong ->
            Beams = get_beams(Apps),
            Mods1 = [Mod || {Mod, _F, _B} <- Beams],
            Mods2 = nklib_util:bjoin(Mods1, <<", ">>),
            io:format("Reloading at ~s: ~s\n\n", [Node, Mods2]),
            spawn_link(
                fun() ->
                    lists:foreach(
                        fun({Mod, File, Bin}) ->
                            rpc:call(Node2, code, purge, [Mod]),
                            {module, Mod} = rpc:call(Node2, code, load_binary, [Mod, File, Bin])
                        end,
                        Beams)
                end);
        pang ->
            {error, not_connected}
    end.


%% @doc Reloads all beams on disk for an app on a remote node
%% supposing the remote node has the beams on disk
remote_reload_ide(Node, Apps) ->
    Node2 = nklib_util:to_atom(Node),
    case net_adm:ping(Node2) of
        pong ->
            rpc:call(Node2, nklib_reloader, reload_app, [Apps]);
        pang ->
            {error, not_connected}
    end.



%% @doc Reloads all beams on disk for an app on a remote node
remote_reload(Apps) ->
    lists:foreach(
        fun(Node) -> {Node, remote_reload(Node, Apps)} end,
        [node()|nodes()]
    ).


get_beams(App) ->
    App2 = nklib_util:to_binary(App),
    Dirs = lists:foldl(
        fun(Path, Acc) ->
            Path2 = nklib_util:to_binary(Path),
            case binary:split(Path2, <<App2/binary, "/ebin">>) of
                [_, <<>>] ->
                    [Path|Acc];
                _ ->
                    Acc
            end
        end,
        [],
        code:get_path()),
    io:format("NKLOG DIRS ~p\n", [Dirs]),
    lists:flatten(lists:foldl(
        fun(Dir, Acc) ->
            Mods = lists:foldl(
                fun(File, Acc2) ->
                    Mod = list_to_atom(filename:basename(File, ".beam")),
                    {ok, Bin} = file:read_file(File),
                    [{Mod, File, Bin}|Acc2]
                end,
                Acc,
                filelib:wildcard(Dir++"/*.beam")),
            [Mods|Acc]
        end,
        [],
        Dirs)).
