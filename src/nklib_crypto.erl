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

%% @doc Common library utility funcions
-module(nklib_crypto).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([crypt_password/1, check_password/2]).

-define(SALT, <<"9nk1">>).

%% ===================================================================
%% Types
%% ===================================================================



%% ===================================================================
%% Public
%% =================================================================



%% @doc
crypt_password(#{password:=<<"!!", _/binary>>}=Obj) ->
    Obj;
crypt_password(#{password:=Plain}=Obj) ->
    Pass = nklib_util:lhash(list_to_binary([?SALT, Plain])),
    Obj#{password:=<<"!!", Pass/binary>>};
crypt_password(Obj) ->
    Obj.


%% @doc
check_password(Pass, #{password:=<<"!!", Hash/binary>>}) ->
    Hash == nklib_util:lhash(list_to_binary([?SALT, Pass]));
check_password(_Pass, _Obj) ->
    false.
