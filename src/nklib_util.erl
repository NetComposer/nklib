%% -------------------------------------------------------------------
%%
%% Copyright (c) 2014 Carlos Gonzalez Florido.  All Rights Reserved.
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
-module(nklib_util).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([ensure_all_started/2, call/2, call/3, apply/3, safe_call/3]).
-export([luid/0, lhash/1, uid/0, uuid_4122/0, hash/1, hash36/1, sha/1]).
-export([timestamp/0, l_timestamp/0, l_timestamp_to_float/1]).
-export([timestamp_to_local/1, timestamp_to_gmt/1]).
-export([local_to_timestamp/1, gmt_to_timestamp/1]).
-export([get_value/2, get_value/3, get_binary/2, get_binary/3, get_list/2, get_list/3]).
-export([get_integer/2, get_integer/3, keys/1]).
-export([store_value/2, store_value/3, store_values/2, filter_values/2, remove_values/2]).
-export([filtermap/2]).
-export([to_binary/1, to_list/1, to_map/1, to_integer/1, to_boolean/1]).
-export([to_atom/1, to_existing_atom/1, to_ip/1, to_host/1, to_host/2]).
-export([to_lower/1, to_upper/1, to_binlist/1, strip/1, unquote/1, is_string/1]).
-export([bjoin/1, bjoin/2, words/1, capitalize/1, append_max/3, randomize/1]).
-export([hex/1, extract/2, delete/2, defaults/2, bin_last/2]).
-export([cancel_timer/1, demonitor/1, msg/2]).

-export_type([optslist/0, timestamp/0, l_timestamp/0]).
-include("nklib.hrl").


%% ===================================================================
%% Types
%% ===================================================================

%% Standard Proplist
-type optslist() :: [atom() | binary() | {atom()|binary(), term()}].

%% System timestamp
-type timestamp() :: non_neg_integer().

-type l_timestamp() :: non_neg_integer().


%% ===================================================================
%% Public
%% =================================================================


%% @doc Ensure that an application and all of its transitive
%% dependencies are started.
-spec ensure_all_started(atom(), permanent | transient | temporary) ->
    {ok, [atom()]} | {error, term()}.

ensure_all_started(Application, Type) ->
    case ensure_all_started(Application, Type, []) of
        {ok, Started} ->
            {ok, lists:reverse(Started)};
        {error, Reason, Started} ->
            [ application:stop(App) || App <- Started ],
            {error, Reason}
    end.


%% @private
ensure_all_started(Application, Type, Started) ->
    case application:start(Application, Type) of
        ok ->
            {ok, [Application | Started]};
        {error, {already_started, Application}} ->
            {ok, Started};
        {error, {not_started, Dependency}} ->
            case ensure_all_started(Dependency, Type, Started) of
                {ok, NewStarted} ->
                    ensure_all_started(Application, Type, NewStarted);
                Error ->
                    Error
            end;
        {error, Reason} ->
            {error, Reason, Started}
    end.


%% @doc See call/3
-spec call(atom()|pid(), term()) ->
    term() | {error, {exit|error|throw, {term(), list()}}}.

call(Dest, Msg) ->
    call(Dest, Msg, 5000).


%% @doc Like gen_server:call/3 but traps exceptions
%% For timeouts: {error, {exit, {{timeout, _}, _}}}
-spec call(atom()|pid(), term(), timeout() | infinity) ->
    term() | {error, {exit|error|throw, {term(), list()}}}.

call(Dest, Msg, Timeout) ->
    try
        gen_server:call(Dest, Msg, Timeout)
    catch
        Class:Error ->
            {error, {Class, {Error, erlang:get_stacktrace()}}}
    end.


%% @private
-spec apply(atom(), atom(), list()) ->
    term() | not_exported | {error, {exit|error|throw, {term(), list()}}}.

apply(Mod, Fun, Args) ->
    try
        case erlang:function_exported(Mod, Fun, length(Args)) of
            false ->
                not_exported;
            true ->
                erlang:apply(Mod, Fun, Args)
        end
    catch
        Class:Error ->
            {error, {Class, {Error, erlang:get_stacktrace()}}}
    end.



%% @doc Safe gen_server:call/3
%% It will spawn helper process in order to be sure no spurious message arrives
-spec safe_call(atom()|pid(), term(), pos_integer()|infinity) ->
    term().

safe_call(Dest, Msg, Timeout) ->
    Master = self(),
    Slave = spawn(
        fun() ->
            Reply = try  
                {ok, gen_server:call(Dest, Msg, Timeout)}
            catch
                error:E -> {error, E};
                exit:E -> {exit, E}
            end,
            Master ! {self(), Reply}
        end
    ),
    receive 
        {Slave, {ok, Msg}} -> Msg;
        {Slave, {error, Error}} -> error(Error);
        {Slave, {exit, Exit}} -> exit(Exit)
    end.


%% @doc Generates a new printable random UUID.
-spec luid() -> 
    binary().

luid() ->
    lhash({make_ref(), os:timestamp()}).


%% @doc Generates a RFC4122 compatible uuid
-spec uuid_4122() ->
    binary().

uuid_4122() ->
    Rand = hex(crypto:rand_bytes(4)),
    <<A:16/bitstring, B:16/bitstring, C:16/bitstring>> = <<(nklib_util:l_timestamp()):48>>,
    Hw = get_hwaddr(),
    <<Rand/binary, $-, (hex(A))/binary, $-, (hex(B))/binary, $-, 
      (hex(C))/binary, $-, Hw/binary>>.


%% @doc Generates a new printable SHA hash binary over `Base' (using 160 bits, 27 chars).
-spec lhash(term()) -> 
    binary().

lhash(Base) -> 
    <<I:160/integer>> = sha(term_to_binary(Base)),
    case encode_integer(I) of
        Hash when byte_size(Hash) == 27 -> Hash;
        Hash -> <<(binary:copy(<<"a">>, 27-byte_size(Hash)))/binary, Hash/binary>>
    end.


%% @private
-ifdef(old_crypto_hash).
sha(Term) -> crypto:sha(Term).
-else.
sha(Term) -> crypto:hash(sha, Term).
-endif.


%% @doc Generates a new random tag of 6 chars
-spec uid() -> 
    binary().

uid() ->
    hash({make_ref(), os:timestamp()}).

%% @doc Generates a new tag of 6 chars based on a value.
-spec hash(term()) -> 
    binary().

hash(Base) ->
    case encode_integer(erlang:phash2([Base], 4294967296)) of
        Hash when byte_size(Hash)==6 -> Hash;
        Hash -> <<(binary:copy(<<"a">>, 6-byte_size(Hash)))/binary, Hash/binary>>
    end.


%% @doc Generates a new tag based on a value (only numbers and uppercase) of 7 chars
-spec hash36(term()) -> 
    binary().

hash36(Base) ->
    case encode_integer_36(erlang:phash2([Base], 4294967296)) of
        Hash when byte_size(Hash)==7 -> Hash;
        Hash -> <<(binary:copy(<<"A">>, 7-byte_size(Hash)))/binary, Hash/binary>>
    end.




%% @private Finds the MAC addr for enX or ethX, or a random one if none is found
get_hwaddr() ->
    {ok, Addrs} = inet:getifaddrs(),
    get_hwaddrs(Addrs).


%% @private
get_hwaddrs([{Name, Data}|Rest]) ->
    case Name of
        "en"++_ ->
            case nklib_util:get_value(hwaddr, Data) of
                Hw when is_list(Hw), length(Hw)==6 -> hex(Hw);
                _ -> get_hwaddrs(Rest)
            end;
        "eth"++_ ->
            case nklib_util:get_value(hwaddr, Data) of
                Hw when is_list(Hw), length(Hw)==6 -> hex(Hw);
                _ -> get_hwaddrs(Rest)
            end;
        _ ->
            get_hwaddrs(Rest)
    end;

get_hwaddrs([]) ->
    hex(crypto:rand_bytes(6)).




% calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}}).
-define(SECONDS_FROM_GREGORIAN_BASE_TO_EPOCH, (1970*365+478)*24*60*60).


%% @doc Gets an second-resolution timestamp
-spec timestamp() -> timestamp().

timestamp() ->
    {MegaSeconds, Seconds, _} = os:timestamp(),
    MegaSeconds*1000000 + Seconds.


%% @doc Gets an microsecond-resolution timestamp
-spec l_timestamp() -> l_timestamp().

l_timestamp() ->
    {N1, N2, N3} = os:timestamp(),
    (N1 * 1000000 + N2) * 1000000 + N3.


%% @doc Converts a `timestamp()' to a local `datetime()'.
-spec timestamp_to_local(timestamp()) -> 
    calendar:datetime().

timestamp_to_local(Secs) ->
    calendar:now_to_local_time({0, Secs, 0}).


%% @doc Converts a `timestamp()' to a gmt `datetime()'.
-spec timestamp_to_gmt(timestamp()) -> 
    calendar:datetime().

timestamp_to_gmt(Secs) ->
    calendar:now_to_universal_time({0, Secs, 0}).

%% @doc Generates a float representing `HHMMSS.MicroSecs' for a high resolution timer.
-spec l_timestamp_to_float(l_timestamp()) -> 
    float().

l_timestamp_to_float(LStamp) ->
    Timestamp = trunc(LStamp/1000000),
    {_, {H,Mi,S}} = nklib_util:timestamp_to_local(Timestamp),
    Micro = LStamp-Timestamp*1000000,
    H*10000+Mi*100+S+(Micro/1000000).


%% @doc Converts a local `datetime()' to a `timestamp()',
-spec gmt_to_timestamp(calendar:datetime()) -> 
    timestamp().

gmt_to_timestamp(DateTime) ->
    calendar:datetime_to_gregorian_seconds(DateTime) - 62167219200.


%% @doc Converts a gmt `datetime()' to a `timestamp()'.
-spec local_to_timestamp(calendar:datetime()) -> 
    timestamp().

local_to_timestamp(DateTime) ->
    case calendar:local_time_to_universal_time_dst(DateTime) of
        [First, _] -> gmt_to_timestamp(First);
        [Time] -> gmt_to_timestamp(Time);
        [] -> 0
    end.



%% @doc Equivalent to `proplists:get_value/2' but faster.
-spec get_value(term(), list()) -> 
    term().

get_value(Key, List) ->
    get_value(Key, List, undefined).


%% @doc Requivalent to `proplists:get_value/3' but faster.
-spec get_value(term(), list(), term()) -> 
    term().

get_value(Key, List, Default) ->
    case lists:keyfind(Key, 1, List) of
        {_, Value} -> Value;
        _ -> Default
    end.


%% @doc Similar to `get_value(Key, List, <<>>)' but converting the result into
%% a `binary()'.
-spec get_binary(term(), list()) -> 
    binary().

get_binary(Key, List) ->
    to_binary(get_value(Key, List, <<>>)).


%% @doc Similar to `get_value(Key, List, Default)' but converting the result into
%% a `binary()'.
-spec get_binary(term(), list(), term()) -> 
    binary().

get_binary(Key, List, Default) ->
    to_binary(get_value(Key, List, Default)).


%% @doc Similar to `get_value(Key, List, [])' but converting the result into a `list()'.
-spec get_list(term(), list()) -> 
    list().

get_list(Key, List) ->
    to_list(get_value(Key, List, [])).


%% @doc Similar to `get_value(Key, List, Default)' but converting the result
%% into a `list()'.
-spec get_list(term(), list(), term()) -> 
    list().

get_list(Key, List, Default) ->
    to_list(get_value(Key, List, Default)).


%% @doc Similar to `get_value(Key, List, 0)' but converting the result into 
%% an `integer()' or `error'.
-spec get_integer(term(), list()) -> 
    integer() | error. 

get_integer(Key, List) ->
    to_integer(get_value(Key, List, 0)).


%% @doc Similar to `get_value(Key, List, Default)' but converting the result into
%% a `integer()' or `error'.
-spec get_integer(term(), list(), term()) -> 
    integer() | error.

get_integer(Key, List, Default) ->
    to_integer(get_value(Key, List, Default)).


%% @doc Get the keys of a map or list (the first element of any tuple, 
%% or the element itself)
-spec keys(map()|list()) ->
    [term()].

keys(Map) when is_map(Map) ->
    maps:keys(Map);

keys(List) when is_list(List) ->
    lists:map(
        fun(Term) ->
            case is_tuple(Term) of
                true -> element(1, Term);
                false -> Term
            end
        end,
        List).


%% @doc Stores a value in a list
-spec store_value(term(), list()) ->
    list().
 
store_value(Term, List) ->
    case lists:member(Term, List) of
        true -> List;
        false -> [Term|List]
    end.

    
%% @doc Stores a value in a proplist
-spec store_value(term(), term(), nklib:optslist()) ->
    nklib:optslist().
 
store_value(Key, Val, List) ->
    lists:keystore(Key, 1, List, {Key, Val}).


%% @doc Stores a set of values in a proplist
-spec store_values(list(), nklib:optslist()) ->
    nklib:optslist().
 
store_values([{Key, Val}|Rest], List) ->
    store_values(Rest, store_value(Key, Val, List));
store_values([Val|Rest], List) ->
    store_values(Rest, store_value(Val, List));
store_values([], List) ->
    List.


%% @doc Removes values from a list
-spec filter_values(list(), nklib:optslist()) ->
    nklib:optslist().

filter_values(Values, List) ->
    lists:filter(
        fun(Term) ->
            case is_tuple(Term) of
                true -> lists:member(element(1, Term), Values);
                false -> lists:member(Term, Values)
            end
        end,
        List).


%% @doc Removes values from a list
-spec remove_values(list(), nklib:optslist()) ->
    nklib:optslist().

remove_values(Values, List) ->
    lists:filter(
        fun(Term) ->
            not case is_tuple(Term) of
                true -> lists:member(element(1, Term), Values);
                false -> lists:member(Term, Values)
            end
        end,
        List).


-spec filtermap(Fun, List1) -> List2 when
      Fun :: fun((Elem) -> boolean() | {'true', Value}),
      List1 :: [Elem],
      List2 :: [Elem | Value],
      Elem :: term(),
      Value :: term().

filtermap(F, [Hd|Tail]) ->
    case F(Hd) of
        true ->
            [Hd|filtermap(F, Tail)];
        {true,Val} ->
            [Val|filtermap(F, Tail)];
        false ->
            filtermap(F, Tail)
    end;
filtermap(F, []) when is_function(F, 1) -> 
    [].


%% @doc Converts anything into a `binary()'. Can convert ip addresses also.
-spec to_binary(term()) -> 
    binary().

to_binary(B) when is_binary(B) -> B;
to_binary(L) when is_list(L) -> list_to_binary(L);
to_binary(undefined) -> <<>>;
to_binary(A) when is_atom(A) -> atom_to_binary(A, latin1);
to_binary(I) when is_integer(I) -> list_to_binary(erlang:integer_to_list(I));
to_binary(#uri{}=Uri) -> nklib_unparse:uri(Uri);
to_binary(P) when is_pid(P) -> to_binary(to_list(P));
to_binary(N) -> msg("~p", [N]).


%% @doc Converts anything into a `string()'.
-spec to_list(string()|binary()|atom()|integer()) -> 
    string().

to_list(L) when is_list(L) -> L;
to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(A) when is_atom(A) -> atom_to_list(A);
to_list(I) when is_integer(I) -> erlang:integer_to_list(I);
to_list(M) when is_map(M) -> maps:to_list(M);
to_list(P) when is_pid(P) -> pid_to_list(P).


%% @doc Converts anything into a `atom()'.
%% WARNING: Can create new atoms
-spec to_atom(string()|binary()|atom()|integer()) -> 
    string().

to_atom(A) when is_atom(A) -> A;
to_atom(B) when is_binary(B) -> binary_to_atom(B, utf8);
to_atom(L) when is_list(L) -> list_to_atom(L);
to_atom(I) when is_integer(I) -> list_to_atom(integer_to_list(I)).


%% @doc Converts anything into an existing atom or throws an error
-spec to_existing_atom(string()|binary()|atom()|integer()) -> 
    string().

to_existing_atom(A) when is_atom(A) -> A;
to_existing_atom(B) when is_binary(B) -> binary_to_existing_atom(B, utf8);
to_existing_atom(L) when is_list(L) -> list_to_existing_atom(L);
to_existing_atom(I) when is_integer(I) -> to_existing_atom(integer_to_list(I)).


-spec to_map(list()|map()) -> 
    map().

to_map(M) when is_map(M) -> 
    M;
to_map(L) when is_list(L) -> 
    L1 = lists:map(
        fun(T) ->
            case T of
                {K, V} -> {K, V};
                K -> {K, true}
            end
        end,
        L),
    maps:from_list(L1).


%% @doc Converts anything into a `integer()' or `error'.
-spec to_integer(integer()|binary()|string()) ->
    integer() | error.

to_integer(I) when is_integer(I) -> 
    I;
to_integer(B) when is_binary(B) -> 
    to_integer(binary_to_list(B));
to_integer(L) when is_list(L) -> 
    case catch list_to_integer(L) of
        I when is_integer(I) -> I;
        _ -> error
    end;
to_integer(_) ->
    error.


%% @doc Converts anything into a `integer()' or `error'.
-spec to_boolean(integer()|binary()|string()|atom()) ->
    true | false | error.

to_boolean(true) ->
    true;
to_boolean(false) ->
    false;
to_boolean(Term) ->
    case to_lower(Term) of
        <<"true">> -> true;
        <<"false">> -> false;
        _ -> error
    end.



%% @doc Converts a `list()' or `binary()' into a `inet:ip_address()' or `error'.
-spec to_ip(string() | binary() | inet:ip_address()) ->
    {ok, inet:ip_address()} | error.

to_ip({A, B, C, D}) when is_integer(A), is_integer(B), is_integer(C), is_integer(D) ->
    {ok, {A, B, C, D}};

to_ip({A, B, C, D, E, F, G, H}) when is_integer(A), is_integer(B), is_integer(C), 
                                     is_integer(D), is_integer(E), is_integer(F),
                                     is_integer(G), is_integer(H) ->
    {ok, {A, B, C, D, E, F, G, H}};

to_ip(Address) when is_binary(Address) ->
    to_ip(binary_to_list(Address));

% For IPv6
to_ip([$[ | Address1]) ->
    case lists:reverse(Address1) of
        [$] | Address2] -> to_ip(lists:reverse(Address2));
        _ -> error
    end;

to_ip(Address) when is_list(Address) ->
    case inet_parse:address(Address) of
        {ok, Ip} -> {ok, Ip};
        _ -> error
    end.


%% @doc Converts an IP or host to a binary host value
-spec to_host(inet:ip_address() | string() | binary()) ->
    binary().

to_host(IpOrHost) ->
    to_host(IpOrHost, false).


%% @doc Converts an IP or host to a binary host value. 
% If `IsUri' and it is an IPv6 address, it will be enclosed in `[' and `]'
-spec to_host(inet:ip_address() | string() | binary(), boolean()) ->
    binary().

to_host({A,B,C,D}=Address, _IsUri) 
    when is_integer(A), is_integer(B), is_integer(C), is_integer(D) ->
    list_to_binary(inet_parse:ntoa(Address));
to_host({A,B,C,D,E,F,G,H}=Address, IsUri) 
    when is_integer(A), is_integer(B), is_integer(C), is_integer(D),
    is_integer(E), is_integer(F), is_integer(G), is_integer(H) ->
    case IsUri of
        true -> list_to_binary([$[, inet_parse:ntoa(Address), $]]);
        false -> list_to_binary(inet_parse:ntoa(Address))
    end;
to_host(Host, _IsUri) ->
    to_binary(Host).


%% @doc converts a `string()' or `binary()' to a lower `binary()'.
-spec to_lower(string()|binary()|atom()) ->
    binary().

to_lower(List) when is_list(List) -> 
    list_to_binary(string:to_lower(List));
to_lower(Other) -> 
    to_lower(to_list(Other)).


%% @doc converts a `string()' or `binary()' to an upper `binary()'.
-spec to_upper(string()|binary()|atom()) ->
    binary().
    
to_upper(List) when is_list(List) -> 
    list_to_binary(string:to_upper(List));
to_upper(Other) -> 
    to_upper(to_list(Other)).


%% @doc Converts a binary(), string() or list() to a list of binaries
-spec to_binlist(term()|[term()]) ->
    [binary()].

to_binlist([I|_]=String) when is_integer(I) -> [list_to_binary(String)];
to_binlist(List) when is_list(List) -> [to_binary(T) || T <- List];
to_binlist(Bin) when is_binary(Bin) -> [Bin];
to_binlist(Term) -> [to_binary(Term)].


%% @doc URI Strips trailing white space
-spec strip(list()|binary()) ->
    list().

strip(Bin) when is_binary(Bin) -> strip(binary_to_list(Bin));
strip([32|Rest]) -> strip(Rest);
strip([13|Rest]) -> strip(Rest);
strip([10|Rest]) -> strip(Rest);
strip([9|Rest]) -> strip(Rest);
strip(Rest) -> Rest.


%% @doc Removes doble quotes
-spec unquote(list()|binary()) ->
    list().

unquote(Bin) when is_binary(Bin) -> 
    unquote(binary_to_list(Bin));

unquote(List) -> 
    case strip(List) of
        [$"|Rest] -> 
            case strip(lists:reverse(Rest)) of
                [$"|Rest1] -> strip(lists:reverse(Rest1));
                _ -> []
            end;
        Other -> 
            Other
    end.


%% @doc Generates a printable string from a big number using base 62.
-spec encode_integer(integer()) ->
    binary().

encode_integer(Int) ->
    list_to_binary(integer_to_list(Int, 62, [])).



%% @doc Generates a printable string from a big number using base 36
%% (only numbers and uppercase)
-spec encode_integer_36(integer()) ->
    binary().

encode_integer_36(Int) ->
    list_to_binary(integer_to_list(Int, 36, [])).



%% @private
-spec integer_to_list(integer(), integer(), string()) -> 
    string().

integer_to_list(I0, Base, R0) ->
    D = I0 rem Base,
    I1 = I0 div Base,
    R1 = if 
        D >= 36 -> [D-36+$a|R0];
        D >= 10 -> [D-10+$A|R0];
        true -> [D+$0|R0]
    end,
    if 
        I1 == 0 -> R1;
       true -> integer_to_list(I1, Base, R1)
    end.


%% @doc Extracts all elements in `Proplist' having key `KeyOrKeys' or having key in 
%% `KeyOrKeys' if `KeyOrKeys' is a list.
-spec extract([term()], term() | [term()]) ->
    [term()].

extract(PropList, KeyOrKeys) ->
    Fun = fun(Term) ->
        if
            is_tuple(Term), is_list(KeyOrKeys) -> 
                lists:member(element(1, Term), KeyOrKeys);
            is_tuple(Term) ->
                element(1, Term) == KeyOrKeys;
            is_list(KeyOrKeys) -> 
                lists:member(Term, KeyOrKeys);
            Term == KeyOrKeys ->
                true;
            true ->
                false
        end
    end,
    lists:filter(Fun, PropList).


%% @doc Deletes all elements in `Proplist' having key `KeyOrKeys' or having key in 
%% `KeyOrKeys' if `KeyOrKeys' is a list.
-spec delete([term()], term() | [term()]) ->
    [term()].

delete(PropList, KeyOrKeys) ->
    Fun = fun(Term) ->
        if
            is_tuple(Term), is_list(KeyOrKeys) -> 
                not lists:member(element(1, Term), KeyOrKeys);
            is_tuple(Term) ->
                element(1, Term) /= KeyOrKeys;
            is_list(KeyOrKeys) -> 
                not lists:member(Term, KeyOrKeys);
            Term /= KeyOrKeys ->
                true;
            true ->
                false
        end
    end,
    lists:filter(Fun, PropList).

%% @doc Inserts defaults in a proplist
-spec defaults(List::[{term(), term()}], Defaults::[{term(), term()}]) ->
    [{term(), term()}].

defaults(List, []) ->
    List;

defaults(List, [{Key, Val}|Rest]) ->
    case lists:keymember(Key, 1, List) of
        true -> defaults(List, Rest);
        false -> defaults([{Key, Val}|List], Rest)
    end.


%% @doc Checks if `Term' is a `string()' or `[]'.
-spec is_string(Term::term()) -> 
    boolean().

is_string([]) -> true;
is_string([F|R]) when is_integer(F) -> is_string(R);
is_string(_) -> false.


%% @doc Joins each element in `List' into a `binary()' using `<<",">>' as separator.
-spec bjoin(List::[term()]) ->
    binary().

bjoin(List) ->
    bjoin(List, <<",">>).

%% @doc Join each element in `List' into a `binary()', using the indicated `Separator'.
-spec bjoin(List::[term()], Separator::binary()) -> 
    binary().

bjoin([], _J) ->
    <<>>;
bjoin([Term], _J) ->
    to_binary(Term);
bjoin([First|Rest], J) ->
    bjoin2(Rest, to_binary(First), J).

bjoin2([[]|Rest], Acc, J) ->
    bjoin2(Rest, Acc, J);
bjoin2([Next|Rest], Acc, J) ->
    bjoin2(Rest, <<Acc/binary, J/binary, (to_binary(Next))/binary>>, J);
bjoin2([], Acc, _J) ->
    Acc.


%% @doc Splits a `string()' or `binary()' into a list of words
-spec words(string() | binary()) ->
    [string()] | error.

words(Bin) when is_binary(Bin) ->
    words(binary_to_list(Bin));
words(List) when is_list(List) ->
    words(List, [], []);
words(_) ->
    error.


%% @private
words([], [], Tokens) ->
    lists:reverse(Tokens);
words([], Chs, Tokens) ->
    lists:reverse([lists:reverse(Chs)|Tokens]);
words([Ch|Rest], Chs, Tokens) when Ch==32; Ch==9; Ch==13; Ch==10 ->
    case Chs of
        [] -> words(Rest, [], Tokens);
        _ -> words(Rest, [], [lists:reverse(Chs)|Tokens])
    end;
words([Ch|Rest], Chs, Tokens) ->
    words(Rest, [Ch|Chs], Tokens).



% @dod
capitalize(Name) ->
    capitalize(nklib_util:to_binary(Name), true, <<>>).


% @private 
capitalize(<<>>, _, Acc) ->
    Acc;

capitalize(<<$-, Rest/bits >>, _, Acc) ->
    capitalize(Rest, true, <<Acc/binary, $->>);

capitalize(<<Ch, Rest/bits>>, true, Acc) when Ch>=$a, Ch=<$z ->
    capitalize(Rest, false, <<Acc/binary, (Ch-32)>>);

capitalize(<<Ch, Rest/bits>>, true, Acc) ->
    capitalize(Rest, false, <<Acc/binary, Ch>>);

capitalize(<<Ch, Rest/bits>>, false, Acc) ->
    capitalize(Rest, false, <<Acc/binary, Ch>>).


%% @doc Appends to a list with a maximum length (not efficient for large lists!!)
-spec append_max(term(), list(), pos_integer()) ->
    list().

append_max(Term, List, Max) when length(List) < Max ->
    List ++ [Term];
append_max(Term, [_|Rest], _) ->
    Rest ++ [Term].


%% @private
-spec randomize(list()) ->
    list().

randomize([]) ->
    [];
randomize([A]) ->
    [A];
randomize([A, B]) ->
    case crypto:rand_uniform(0, 2) of
        0 -> [A, B];
        1 -> [B, A]
    end;
randomize([A, B, C]) ->
    case crypto:rand_uniform(0, 3) of
        0 -> [A, B, C];
        1 -> [B, C, A];
        2 -> [C, A, B]
    end;
randomize(List) when is_list(List) ->
    Size = length(List),
    List1 = [{crypto:rand_uniform(0, Size), Term} || Term <- List],
    [Term || {_, Term} <- lists:sort(List1)].


%% @private
-spec hex(binary()|string()) -> 
    binary().

hex(B) when is_binary(B) -> hex(binary_to_list(B), []);
hex(S) -> hex(S, []).


%% @private
hex([], Res) -> list_to_binary(lists:reverse(Res));
hex([N|Ns], Acc) -> hex(Ns, [digit(N rem 16), digit(N div 16)|Acc]).


%% @private
digit(D) when (D >= 0) and (D < 10) -> D + 48;
digit(D) -> D + 87.


%% @doc Gets the sub-binary after `Char'.
-spec bin_last(char(), binary()) ->
    binary().

bin_last(Char, Bin) ->
    case binary:match(Bin, <<Char>>) of
        {First, 1} -> binary:part(Bin, First+1, byte_size(Bin)-First-1);
        _ -> <<>>
    end.



%% @doc Cancels and existig timer.
-spec cancel_timer(reference()|undefined) ->
    false | integer().

cancel_timer(Ref) when is_reference(Ref) ->
    case erlang:cancel_timer(Ref) of
        false ->
            receive {timeout, Ref, _} -> 0
            after 0 -> false 
            end;
        RemainingTime ->
            RemainingTime
    end;

cancel_timer(_) ->
    false.


%% @doc Cancels and existig timer.
-spec demonitor(reference()|undefined) ->
    boolean().

demonitor(Ref) when is_reference(Ref) ->
    erlang:demonitor(Ref, [flush]);

demonitor(_) ->
    false.


%% @private
-spec msg(string(), [term()]) -> 
    binary().

msg(Msg, Vars) ->
    case catch list_to_binary(io_lib:format(Msg, Vars)) of
        {'EXIT', _} -> 
            lager:warning("MSG PARSE ERROR: ~p, ~p", [Msg, Vars]),
            <<"Msg parser error">>;
        Result -> 
            Result
    end.


%% ===================================================================
%% EUnit tests
%% ===================================================================


-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

bjoin_test() ->
    ?assertMatch(<<"hi">>, bjoin([<<"hi">>], <<"any">>)),
    ?assertMatch(<<"hianyhi">>, bjoin([<<"hi">>, <<"hi">>], <<"any">>)),
    ?assertMatch(<<"hi1_hi2_hi3">>, bjoin([<<"hi1">>, <<"hi2">>, <<"hi3">>], <<"_">>)).

-endif.





