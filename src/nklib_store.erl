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

%% @doc Nekso In-Memory Database.
%%
%% This module implements an ETS-based database used for registrations
%% and caches.
%% It is capable of timed auto expiring of records, server-side update funs 
%% and calling an user fun on record expire.

-module(nklib_store).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([put/2, put/3, put_dirty/2, put_dirty_new/2, update/2, update/3]).
-export([get/1, get/2, del/1, del_dirty/1]).
-export([pending/0, fold/2]).
-export([start_link/0, stop/0]).
-export([init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).
-export([update_timer/1]).

-define(STORE_TIMER, 5000).


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Equivalent to `get(Key, not_found)'.
-spec get(term()) -> term() | not_found.
get(Key) -> get(Key, not_found).


%% @doc Gets a record from database using `Default' if not found
-spec get(term(), term()) -> term().
get(Key, Default) ->
    case ets:lookup(nklib_store, Key) of
        [] -> Default;
        [{_, Value, _Expire, _Fun}] -> Value
    end.


%% @doc Equivalent to `put(Key, Value, [])'.
-spec put(term(), term()) -> ok.
put(Key, Value) -> put(Key, Value, []).


%% @doc Inserts a `Value' in database under `Key'.
%% If `ttl' option is used (seconds), record will be deleted after this time.
%% If `notify' options is used, function will be called on record's delete.
-spec put(term(), term(), [Opt]) -> ok
    when Opt :: {ttl, integer()} | {notify, function()}.
put(Key, Value, Opts) when is_list(Opts) ->
    gen_server:call(?MODULE, {put, Key, Value, Opts}).


%% @private
-spec put_dirty(term(), term()) -> true.
put_dirty(Key, Value) ->
    ets:insert(nklib_store, {Key, Value, 0, none}).


%% @private
-spec put_dirty_new(term(), term()) -> boolean().
put_dirty_new(Key, Value) ->
    ets:insert_new(nklib_store, {Key, Value, 0, none}).


%% @doc Equivalent to `update(Key, Fun, [])'.
-spec update(term(), function()) -> 
    {ok, FunResult::term()} | {error, Error::term()}.
update(Key, Fun) ->
    update(Key, Fun, []).


%% @doc Updates a record in database, applying `Fun' to the old record 
%% to get the new value. 
%% If no record is found, old value would be `[]'. 
%% If the new generated value is `[]' record will be deleted.
%% See {@link put/3} for options.
-spec update(term(), function(), nklib:optslist()) -> 
    {ok, FunResult::term()} | {error, Error::term()}.
update(Key, Fun, Opts) when is_function(Fun, 1), is_list(Opts) ->
    gen_server:call(?MODULE, {update, Key, Fun, Opts}).


%% @doc Deletes a record from database.
-spec del(term()) -> ok | not_found.
del(Key) -> gen_server:call(?MODULE, {del, Key}).


%% @private 
-spec del_dirty(term()) -> ok.
del_dirty(Key) -> 
    true = ets:delete(nklib_store, Key),
    ok.


%% @doc Folds over all records in database like `lists:foldl/3'.
%% UserFun will be called as `UserFun(Key, Value, Acc)' for each record.
-spec fold(function(), term()) -> term().
fold(UserFun, Acc0) when is_function(UserFun, 3) ->
    Fun = fun({Key, Value, _Exp, _ExpFun}, Acc) -> UserFun(Key, Value, Acc) end,
    ets:foldl(Fun, Acc0, nklib_store).


%% @private Gets all records with pending expiration
pending() ->
    gen_server:call(?MODULE, get_pending).


%% @private
update_timer(Time) ->
    gen_server:cast(?MODULE, {update_timer, Time}).


%% ===================================================================
%% gen_server
%% ===================================================================


-record(state, {
    time,
    timer
}).


%% @private
start_link() ->
    start_link(?STORE_TIMER).


%% @private
start_link(Time) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Time], []).


%% @private
stop() ->
    gen_server:call(?MODULE, stop).


%% @private 
-spec init(term()) ->
    {ok, #state{}}.

init([Time]) ->
    ets:new(nklib_store, [public, named_table]),
    ets:new(nklib_store_ord, [protected, ordered_set, named_table]),
    Timer = erlang:start_timer(Time, self(), timer),
    {ok, #state{time=Time, timer=Timer}}.


%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {reply, term(), #state{}} | {noreply, #state{}} | {stop, normal, ok, #state{}}.

handle_call({put, Key, Value, Opts}, _From, State) ->
    case ets:lookup(nklib_store, Key) of
        [{_, _OldValue, OldExpire, _Fun}] when OldExpire > 0 ->
            ets:delete(nklib_store_ord, {ttl, OldExpire, Key});
        _ -> 
            ok
    end,
    case lists:keyfind(notify, 1, Opts) of
        {notify, ExpFun} when is_function(ExpFun, 1) -> ok;
        _ -> ExpFun = none
    end,
    case lists:keyfind(ttl, 1, Opts) of
        {ttl, TTL} when is_integer(TTL), TTL > 0 ->
            Expire = nklib_util:timestamp() + TTL,
            ets:insert(nklib_store, {Key, Value, Expire, ExpFun}),
            ets:insert(nklib_store_ord, {{ttl, Expire, Key}, none});
        _ ->
            ets:insert(nklib_store, {Key, Value, 0, ExpFun})
    end,
    {reply, ok, State};

handle_call({update, Key, UpdateFun, Opts}, From, State) ->
    case ets:lookup(nklib_store, Key) of
        [] -> OldValue = [], OldExpire = 0;
        [{_, OldValue, OldExpire, _Fun}] -> ok
    end,
    case catch UpdateFun(OldValue) of
        {'EXIT', Error} -> 
            {reply, {error, Error}, State};
        Value ->
            case OldExpire of
                0 -> ok;
                _ -> ets:delete(nklib_store_ord, {ttl, OldExpire, Key})
            end,
            case Value of
                [] ->
                    {reply, _, _ } = handle_call({del, Key}, From, State);
                _ ->
                    case lists:keyfind(notify, 1, Opts) of
                        {notify, ExpFun} when is_function(ExpFun, 1) -> ok;
                        _ -> ExpFun = none
                    end,
                    case lists:keyfind(ttl, 1, Opts) of
                        {ttl, TTL} when is_integer(TTL), TTL > 0 ->
                            Expire = nklib_util:timestamp() + TTL,
                            ets:insert(nklib_store, {Key, Value, Expire, ExpFun}),
                            ets:insert(nklib_store_ord, {{ttl, Expire, Key}, none});
                        _ ->
                            ets:insert(nklib_store, {Key, Value, 0, ExpFun})
                    end
            end,
            {reply, {ok, Value}, State}
    end;

handle_call({del, Key}, _From, State) ->
    case ets:lookup(nklib_store, Key) of
        [] ->
            {reply, not_found, State};
        [{_, _, Expire, ExpFun}] ->
            case is_function(ExpFun, 1) of
                true -> proc_lib:spawn(fun() -> ExpFun(Key) end);
                _ -> ok
            end,
            ets:delete(nklib_store, Key),
            case Expire of
                0 -> ok;
                _ -> ets:delete(nklib_store_ord, {ttl, Expire, Key})
            end,
            {reply, ok, State}
    end;

handle_call(get_pending, _From, State) ->
    Now = nklib_util:timestamp(),
    Pending = pending_iter(ets:first(nklib_store_ord), Now, []),
    {reply, Pending, State};

handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

handle_call(Msg, _From, State) -> 
    lager:error("Module ~p received unexpected call ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_cast(term(), #state{}) ->
    {noreply, #state{}}.

handle_cast({update_timer, Time}, #state{timer=Timer}=State) ->
    nklib_util:cancel_timer(Timer),
    handle_info({timeout, none, timer}, State#state{time=Time});

handle_cast(Msg, State) -> 
    lager:error("Module ~p received unexpected cast ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_info(term(), #state{}) ->
    {noreply, #state{}}.

handle_info({timeout, _, timer}, #state{time=Time}=State) -> 
    proc_lib:spawn(
        fun() -> 
            Now = nklib_util:timestamp(),
            Last = ets:prev(nklib_store_ord, {ttl, Now, 0}),
            delete_expired_iter(Last)
        end),
    Timer = erlang:start_timer(Time, self(), timer),
    {noreply, State#state{timer=Timer}};

handle_info(Info, State) -> 
    lager:warning("Module ~p received unexpected info: ~p", [?MODULE, Info]),
    {noreply, State}.


%% @private
-spec code_change(term(), #state{}, term()) ->
    {ok, #state{}}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% @private
-spec terminate(term(), #state{}) ->
    ok.
    
terminate(_Reason, _State) ->  
    ok.


%% ===================================================================
%% Internal
%% ===================================================================


%% @private
delete_expired_iter('$end_of_table') ->
    ok;
delete_expired_iter({ttl, _Time, Key}=Last) ->
    del(Key),
    delete_expired_iter(ets:prev(nklib_store_ord, Last)).

%% @private
pending_iter('$end_of_table', _Now, Acc) ->
    Acc;
pending_iter({ttl, Time, Key}=Current, Now, Acc) ->
    Next = ets:next(nklib_store_ord, Current),
    pending_iter(Next, Now, [{Key, Time-Now}|Acc]).



%% ===================================================================
%% EUnit tests
%% ===================================================================

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-compile({no_auto_import, [get/1, put/2]}).

basic_test_() ->
    {setup, 
        fun() -> 
            ?debugFmt("Starting ~p", [?MODULE]),
            case start_link() of
                {error, {already_started, _}} ->
                    ok;
                {ok, _} ->
                    do_stop
            end
        end,
        fun(Stop) -> 
            case Stop of 
                do_stop -> stop();
                ok -> ok 
            end
        end,
        [
            {timeout, 60, fun normal_insert/0},
            {timeout, 60, fun ttl_insert/0}
        ]
    }.

normal_insert() ->
    ok = put(k1, v11),
    ok = put("k2", "v12"),
    ok = put(<<"k3">>, <<"v13">>),
    ?assertMatch(v11, get(k1)),
    ?assertMatch("v12", get("k2")),
    ?assertMatch(<<"v13">>, get(<<"k3">>)),
    ?assertMatch(not_found, get(k2)),
    ?assertMatch(not_found, get(k3)),
    ok = put(k1, "v11b"),
    ?assertMatch("v11b", get(k1)),
    ok = del("k2"),
    ?assertMatch(not_found, get("k2")),
    Self = self(),
    Fun = fun(k4) -> Self ! k4 end,
    ok = put(k4, v4, [{notify, Fun}]),
    ?assertMatch(v4, get(k4)),
    ok = del(k4),
    ?assertMatch(not_found, get(k4)),
    ok = receive k4 -> ok after 500 -> error end,
    not_found = del(non_existent),
    ok.

ttl_insert() ->
    ok = put(k1, v21a),
    ?assertMatch(v21a, get(k1)),
    ?assertMatch(false, is_pending(k1)),
    ok = put(k1, v21b, [{ttl, 2}]),
    ?assertMatch(v21b, get(k1)),
    ?assertMatch(true, is_pending(k1)),
    ok = put(k1, v21c, [{ttl, 3}]),
    ?assertMatch(v21c, get(k1)),
    ?assertMatch(true, is_pending(k1)),
    ok = put(k1, v21d, [{ttl, 3}]),
    ?assertMatch(v21d, get(k1)),
    ?assertMatch(true, is_pending(k1)),
    ok = put(k1, v21e),
    ?assertMatch(v21e, get(k1)),
    ?assertMatch(false, is_pending(k1)),
    ok = put(k1, v21f, [{ttl, 10}]),
    ?assertMatch(v21f, get(k1)),
    ?assertMatch(true, is_pending(k1)),
    ok = del(k1),
    ?assertMatch(not_found, get(k1)),
    ?assertMatch(false, is_pending(k1)),
    Self = self(),
    Fun = fun(k1) -> Self ! k1 end,
    ok = put(k1, v21g, [{ttl, 1}, {notify, Fun}]),
    ?assertMatch(v21g, get(k1)),
    ?assertMatch(true, is_pending(k1)),
    ?debugMsg("Waiting store timeout"),
    ok = receive k1 -> ok after 10000 -> error end,
    ?assertMatch(not_found, get(k1)),
    ?assertMatch(false, is_pending(k1)),
    ok.

is_pending(Key) ->
    lists:keymember(Key, 1, pending()).




-endif.









