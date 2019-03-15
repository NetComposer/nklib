%% -------------------------------------------------------------------
%%
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

%% @doc Amazon Web Services utilities
-module(nklib_aws).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([request_v4/1, request_v4_tmp/1]).

%% hex(crypto:hash(sha256, <<>>))
-define(EMPTY_HASH, <<"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855">>).
-define(DEFAULT_REGION, <<"eu-west-1">>).

%% ===================================================================
%% Types
%% ===================================================================


%% @doc Request configuration
-type request_v4_config() ::
#{
    method => binary(),                     %% <<"GET">> | <<"POST">> | <<"PUT">>
    service => s3 | sns | atom(),
    region => string()|binary()|atom(),     %% <<"eu-west-1">>
    key => string()|binary(),
    secret => string()|binary(),
    path => string() | binary(),            %% Uri-encoded (except for S3)
    scheme => http | https,                 %% Default https
    host => string() | binary(),            %% AWS used if not specified
    port => integer(),
    headers => [{string()|binary()|atom(), string()|binary()}],
    params => #{string()|binary()|atom() => string()|binary()},
    meta => #{string()|binary()|atom() => string()|binary()},
    hash => binary,                         %% crypto:hash(sha256, Body)
    ttl => integer(),                       %% Secs, for tmp version
    content_type => binary()                %% For tmp version
}.



%% ===================================================================
%% Public
%% ===================================================================


%% @doc AWS v4 signed request
-spec request_v4(request_v4_config()) ->
    {Uri::binary(), Headers::[{binary(), binary()}]} |
    {error, term()}.

request_v4(Config) ->
    case nklib_syntax:parse(Config, syntax()) of
        {ok, Config2, _} ->
            do_request_v4(Config2);
        {error, Error} ->
            {error, Error}
    end.


%% @private
do_request_v4(Config) ->
    {Region, Service, Host, Url} = get_service(Config),
    Date = iso_8601_basic_time(),
    HexHash = case maps:find(hash, Config) of
        {ok, BodyHash} ->
            nklib_util:hex(BodyHash);
        error ->
            ?EMPTY_HASH
    end,
    Headers1 = maps:get(headers, Config, []),
    % Amazon aws-cli don't include x-amz-content-sha256 header (but it doesn't hurt)
    Headers2 = [
        {<<"x-amz-date">>, Date},
        {<<"x-amz-content-sha256">>, HexHash},
        {<<"host">>, Host}
        | Headers1
    ],
    Headers3 = case maps:find(meta, Config) of
        {ok, Meta} ->
            lists:foldl(
                fun({Key, Val}, Acc) ->
                    HeaderKey = <<"x-amz-meta-", (nklib_util:to_lower(Key))/binary>>,
                    [{HeaderKey, to_bin(Val)} | Acc]
                end,
                Headers2,
                maps:to_list(Meta));
        error ->
            Headers2
    end,
    NormHeaders = [
        {nklib_util:to_lower(Name), to_bin(Value)}
        || {Name, Value} <- Headers3
    ],
    SortedHeaders = lists:keysort(1, NormHeaders),
    CanonicalHeaders = [[Name, $:, Value, $\n] || {Name, Value} <- SortedHeaders],
    SignedHeaders = nklib_util:bjoin([Name || {Name, _} <- SortedHeaders], <<";">>),
    QueryParams = maps:get(params, Config, #{}),
    NormalizedQS = [
        <<(nklib_url:encode_utf8(Name))/binary, $=, (nklib_url:encode_utf8(value_to_string(Value)))/binary>>
        || {Name, Value} <- maps:to_list(QueryParams)
    ],
    CanonicalQueryString = nklib_util:bjoin(lists:sort(NormalizedQS), <<"&">>),
    Method = nklib_util:to_upper(maps:get(method, Config, <<"GET">>)),
    Path = maps:get(path, Config, <<"/">>),
    Request = [
        Method, $\n,
        Path, $\n,
        CanonicalQueryString, $\n,
        CanonicalHeaders, $\n,
        SignedHeaders, $\n,
        HexHash
    ],
    <<Date2:8/binary, _/binary>> = Date,
    CredentialScope = [Date2, $/, Region, $/, Service, "/aws4_request"],
    ToSign = [
        <<"AWS4-HMAC-SHA256\n">>,
        Date, $\n,
        CredentialScope, $\n,
        nklib_util:hex(crypto:hash(sha256, Request))
    ],
    #{key:=Key, secret:=Secret} = Config,
    KDate = crypto:hmac(sha256, <<"AWS4", Secret/binary>>, Date2),
    KRegion = crypto:hmac(sha256, KDate, Region),
    KService = crypto:hmac(sha256, KRegion, Service),
    SigningKey = crypto:hmac(sha256, KService, <<"aws4_request">>),
    Signature = nklib_util:hex(crypto:hmac(sha256, SigningKey, ToSign)),
    Auth = list_to_binary(lists:flatten([
        <<"AWS4-HMAC-SHA256">>,
        <<" Credential=">>, Key, $/, CredentialScope, $,,
        <<" SignedHeaders=">>, SignedHeaders, $,,
        <<" Signature=">>, Signature
    ])),
    ReqHeaders = [{<<"authorization">>, Auth} | NormHeaders],
    ReqUri1 = <<Url/binary, Path/binary>>,
    ReqUri2 = case CanonicalQueryString of
        <<>> ->
            ReqUri1;
        _ ->
            <<ReqUri1/binary, $?, CanonicalQueryString/binary>>
    end,
    {Method, ReqUri2, ReqHeaders}.



%% @doc Generates an URL-like temporary access
-spec request_v4_tmp(request_v4_config()) ->
    {Method::binary(), Url::binary()}.

request_v4_tmp(Config) ->
    case nklib_syntax:parse(Config, syntax()) of
        {ok, Config2, _} ->
            do_request_v4_tmp(Config2);
        {error, Error} ->
            {error, Error}
    end.


%% @private
do_request_v4_tmp(#{ttl:=Secs}=Config) ->
    Expires = to_bin(nklib_date:epoch(secs) + Secs),
    Method = nklib_util:to_upper(maps:get(method, Config, <<"GET">>)),
    Path = maps:get(path, Config, <<"/">>),
    CT = maps:get(content_type, Config, <<>>),
    ToSign = list_to_binary([Method, "\n\n", CT, "\n", Expires, $\n, Path]),
    #{key:=Key, secret:=Secret} = Config,
    Enc = base64:encode(crypto:hmac(sha, Secret, ToSign)),
    Qs = list_to_binary([
        "?AWSAccessKeyId=", nklib_url:encode_utf8(Key),
        "&Signature=", nklib_url:encode_utf8(Enc),
        "&Expires=", Expires
    ]),
    {_Region, _Service, _Host, Url} = get_service(Config),
    {Method, <<Url/binary, Path/binary, Qs/binary>>}.



%% ===================================================================
%% Internal
%% ===================================================================

get_service(Config) ->
    #{service:=Service, scheme:=Scheme} = Config,
    Region = maps:get(region, Config, ?DEFAULT_REGION),
    DefPort = case Scheme of <<"http">> -> 80; <<"https">> -> 443 end,
    Port = to_bin(maps:get(port, Config, DefPort)),
    Host = case maps:find(host, Config) of
        {ok, ConfigHost} ->
            ConfigHost;
        error ->
            <<Service/binary, $., Region/binary, ".amazonaws.com">>
    end,
    FullHost = case Port==<<"80">> orelse Port==<<"443">> of
        true ->
            Host;
        false ->
            <<Host/binary, $:, Port/binary>>
    end,
    Url = <<Scheme/binary, "://", FullHost/binary>>,
    {Region, Service, FullHost, Url}.


%% @private
syntax() ->
    #{
        method => upper,
        service => binary,
        region => binary,
        key => binary,
        secret => binary,
        path => binary,
        scheme => {binary, [<<"http">>, <<"https">>]},
        host => binary,
        port => integer,
        headers => any,
        params => map,
        meta => map,
        hash => binary,
        ttl => pos_integer,
        content_type => binary,
        '__defaults' => #{method => <<"GET">>, scheme => <<"https">>},
        '__mandatory' => [service, key, secret]
    }.



%% @private
iso_8601_basic_time() ->
    {{Year,Month,Day},{Hour,Min,Sec}} = calendar:now_to_universal_time(os:timestamp()),
    list_to_binary(io_lib:format(
        "~4.10.0B~2.10.0B~2.10.0BT~2.10.0B~2.10.0B~2.10.0BZ",
        [Year, Month, Day, Hour, Min, Sec])).


%% @private
value_to_string(Integer) when is_integer(Integer) ->
    integer_to_list(Integer);

value_to_string(Atom) when is_atom(Atom) ->
    atom_to_list(Atom);

value_to_string(Binary) when is_binary(Binary) ->
    Binary;

value_to_string(String) when is_list(String) ->
    unicode:characters_to_binary(String).


%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).

