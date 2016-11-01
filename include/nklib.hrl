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

-ifndef(NKLIB_HRL_).
-define(NKLIB_HRL_, 1).

%% ===================================================================
%% Defines
%% ===================================================================


-define(I(T), lager:notice(T)).
-define(I(T,P), lager:notice(T,P)).
-define(N(T), lager:notice(T)).
-define(N(T,P), lager:notice(T,P)).
-define(W(T), lager:warning(T)).
-define(W(T,P), lager:warning(T,P)).
-define(E(T), lager:error(T)).
-define(E(T,P), lager:error(T,P)).
-define(PR(T), lager:pr(T, ?MODULE)).



%% ===================================================================
%% Records
%% ===================================================================



-record(uri, {
    scheme :: nklib:scheme(),
    user = <<>> :: binary(), 
    pass = <<>> :: binary(), 
    domain = <<"invalid.invalid">> :: binary(), 
    port = 0 :: inet:port_number(),             % 0 means "no port in message"
    path = <<>> :: binary(),
    opts = [] :: list(),
    headers = [] :: list(),
    ext_opts = [] :: list(),
    ext_headers = [] :: list(),
    disp = <<>> :: binary()
}).


-endif.

