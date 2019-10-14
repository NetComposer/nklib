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

%% @doc NkLIB i18n Server.
-module(nklib_i18n).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(gen_server).

-export([get_all_locales/0, get_locales/1, syntax_locale/1, store_locales/1]).
-export([get/2, get/3, get/4, insert/2, insert/3, load/2]).
-export([start_link/0, init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2, 
         handle_info/2]).

-compile({no_auto_import,[get/1]}).

%% ===================================================================
%% Types
%% ===================================================================

-type srv_id() :: term().
-type key() :: binary().
-type text() :: string() | binary().

-type lang() :: nklib:lang().

-callback i18n() ->
    #{ lang() => #{ key() => text() }}.


%% ===================================================================
%% Public
%% ===================================================================

%% @doc
-spec get_all_locales() -> [binary()].
get_all_locales() ->
    nklib_util:do_config_get(nklib_all_locales).


-spec get_locales(atom()) -> #{binary() => binary()}.
get_locales(Lang) ->
    nklib_util:do_config_get({nklib_locales, Lang}).


%% @doc
syntax_locale(Val) ->
    lists:member(nklib_util:to_binary(Val), get_all_locales()).


%% @doc Gets a string for english
-spec get(srv_id(), key()) ->
    binary().

get(SrvId, Key) ->
    get(SrvId, Key, <<"en">>).


%% @doc Gets a string for any language, or use english default
-spec get(srv_id(), key(), lang()) ->
    binary().

get(SrvId, Key, Lang) ->
    Lang2 = to_bin(Lang),
    case ets:lookup(?MODULE, {SrvId, to_bin(Key), Lang2}) of
        [] when Lang2 == <<"en">> ->
            <<>>;
        [] ->
            get(SrvId, Key, <<"en">>);
        [{_, Msg}] ->
            Msg
    end.


%% @doc Gets a string an expands parameters
-spec get(srv_id(), key(), list(), lang()) ->
    binary().

get(SrvId, Key, List, Lang) when is_list(List) ->
    case get(SrvId, Key, Lang) of
        <<>> ->
            <<>>;
        Msg ->
            case catch io_lib:format(nklib_util:to_list(Msg), List) of
                {'EXIT', _} ->
                    lager:notice("Invalid format in i18n: ~s, ~p", [Msg, List]),
                    <<>>;
                Val ->
                    list_to_binary(Val)
            end
    end.


%% @doc Inserts a key or keys for english
-spec insert(srv_id(), {key(), text()}|[{key(), text()}]) ->
    ok.

insert(SrvId, Keys) ->
    insert(SrvId, Keys, <<"en">>).


%% @doc Inserts a key or keys for any language
-spec insert(srv_id(), {key(), text()}|[{key(), text()}], lang()) ->
    ok.

insert(_SrvId, [], _Lang) ->
    ok;

insert(SrvId, [{_, _}|_]=Keys, Lang) ->
    gen_server:cast(?MODULE, {insert, SrvId, Keys, to_bin(Lang)});

insert(SrvId, {Key, Txt}, Lang) ->
    insert(SrvId, [{Key, Txt}], Lang);

insert(SrvId, Map, Lang) when is_map(Map) ->
    insert(SrvId, maps:to_list(Map), Lang).


%% @doc Bulk loading for modules implementing this behaviour
-spec load(srv_id(), module()) ->
    ok.

load(SrvId, Module) ->
    Data = Module:i18n(),
    lists:foreach(
        fun({Lang, Keys}) -> insert(SrvId, Keys, Lang) end,
        maps:to_list(Data)).



%% ===================================================================
%% gen_server
%% ===================================================================


-record(state, {
}).


%% @private
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
        

%% @private 
-spec init(term()) ->
    {ok, #state{}}.

init([]) ->
    ets:new(?MODULE, [named_table, protected, {read_concurrency, true}]),
    {ok, #state{}}.
    

%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {noreply, #state{}}.

handle_call(Msg, _From, State) ->
    lager:error("Module ~p received unexpected call ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_cast(term(), #state{}) ->
    {noreply, #state{}}.

handle_cast({insert, SrvId, Keys, Lang}, State) ->
    Values = [{{SrvId, to_bin(Key), Lang}, to_bin(Txt)} || {Key, Txt} <- Keys],
    ets:insert(?MODULE, Values),
    {noreply, State};

handle_cast(Msg, State) ->
    lager:error("Module ~p received unexpected cast ~p", [?MODULE, Msg]),
    {noreply, State}.


%% @private
-spec handle_info(term(), #state{}) ->
    {noreply, #state{}}.

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
%% Private
%% ===================================================================

%% @private
store_locales(Langs) ->
    Locales = locales_5646(),
    nklib_util:do_config_put(nklib_all_locales, lists:usort(maps:keys(Locales))),
    do_store_locales(Langs).


%% @private
do_store_locales([]) ->
    ok;

do_store_locales([Lang|Rest]) ->
    Locales2 = maps:fold(
        fun(Locale, Data, Acc) ->
            Value = case maps:find(Lang, Data) of
                {ok, Txt} ->
                    Txt;
                error ->
                    maps:get(en, Data)
            end,
            Acc#{Locale => Value}
        end,
        #{},
        locales_5646()
    ),
    nklib_util:do_config_put({nklib_locales, Lang}, Locales2),
    do_store_locales(Rest).


%% @private
locales_5646() ->
    #{
        <<"af">> => #{
            en => <<"Afrikaans">>
        },
        <<"af-ZA">> =>  #{
            en => <<"Afrikaans (South Africa)">>
        },
        <<"ar">> => #{
            en => <<"Arabic">>
        },
        <<"ar-AE">> => #{
            en => <<"Arabic (U.A.E.)">>
        },
        <<"ar-BH">> => #{
            en => <<"Arabic (Bahrain)">>
        },
        <<"ar-DZ">> => #{
            en => <<"Arabic (Algeria)">>
        },
        <<"ar-EG">> => #{
            en => <<"Arabic (Egypt)">>
        },
        <<"ar-IQ">> => #{
            en => <<"Arabic (Iraq)">>
        },
        <<"ar-JO">> => #{
            en => <<"Arabic (Jordan)">>
        },
        <<"ar-KW">> => #{
            en => <<"Arabic (Kuwait)">>
        },
        <<"ar-LB">> => #{
            en => <<"Arabic (Lebanon)">>
        },
        <<"ar-LY">> => #{
            en => <<"Arabic (Libya)">>
        },
        <<"ar-MA">> => #{
            en => <<"Arabic (Morocco)">>
        },
        <<"ar-OM">> => #{
            en => <<"Arabic (Oman)">>
        },
        <<"ar-QA">> => #{
            en => <<"Arabic (Qatar)">>
        },
        <<"ar-SA">> => #{
            en => <<"Arabic (Saudi Arabia)">>
        },
        <<"ar-SY">> => #{
            en => <<"Arabic (Syria)">>
        },
        <<"ar-TN">> => #{
            en => <<"Arabic (Tunisia)">>
        },
        <<"ar-YE">> => #{
            en => <<"Arabic (Yemen)">>
        },
        <<"az">> => #{
            en => <<"Azeri (Latin)">>
        },
        <<"az-AZ">> => #{
            en => <<"Azeri (Latin) (Azerbaijan)">>
        },
        <<"az-Cyrl-AZ">> => #{
            en => <<"Azeri (Cyrillic) (Azerbaijan)">>
        },
        <<"be">> => #{
            en => <<"Belarusian">>
        },
        <<"be-BY">> => #{
            en => <<"Belarusian (Belarus)">>
        },
        <<"bg">> => #{
            en => <<"Bulgarian">>
        },
        <<"bg-BG">> => #{
            en => <<"Bulgarian (Bulgaria)">>
        },
        <<"bs-BA">> => #{
            en => <<"Bosnian (Bosnia and Herzegovina)">>
        },
        <<"ca">> => #{
            en => <<"Catalan">>
        },
        <<"ca-ES">> => #{
            en => <<"Catalan (Spain)">>
        },
        <<"cs">> => #{
            en => <<"Czech">>
        },
        <<"cs-CZ">> => #{
            en => <<"Czech (Czech Republic)">>
        },
        <<"cy">> => #{
            en => <<"Welsh">>
        },
        <<"cy-GB">> => #{
            en => <<"Welsh (United Kingdom)">>
        },
        <<"da">> => #{
            en => <<"Danish">>
        },
        <<"da-DK">> => #{
            en => <<"Danish (Denmark)">>
        },
        <<"de">> => #{
            en => <<"German">>
        },
        <<"de-AT">> => #{
            en => <<"German (Austria)">>
        },
        <<"de-CH">> => #{
            en => <<"German (Switzerland)">>
        },
        <<"de-DE">> => #{
            en => <<"German (Germany)">>
        },
        <<"de-LI">> => #{
            en => <<"German (Liechtenstein)">>
        },
        <<"de-LU">> => #{
            en => <<"German (Luxembourg)">>
        },
        <<"dv">> => #{
            en => <<"Divehi">>
        },
        <<"dv-MV">> => #{
            en => <<"Divehi (Maldives)">>
        },
        <<"el">> => #{
            en => <<"Greek">>
        },
        <<"el-GR">> => #{
            en => <<"Greek (Greece)">>
        },
        <<"en">> => #{
            en => <<"English">>
        },
        <<"en-AU">> => #{
            en => <<"English (Australia)">>
        },
        <<"en-BZ">> => #{
            en => <<"English (Belize)">>
        },
        <<"en-CA">> => #{
            en => <<"English (Canada)">>
        },
        <<"en-CB">> => #{
            en => <<"English (Caribbean)">>
        },
        <<"en-GB">> => #{
            en => <<"English (United Kingdom)">>
        },
        <<"en-IE">> => #{
            en => <<"English (Ireland)">>
        },
        <<"en-JM">> => #{
            en => <<"English (Jamaica)">>
        },
        <<"en-NZ">> => #{
            en => <<"English (New Zealand)">>
        },
        <<"en-PH">> => #{
            en => <<"English (Republic of the Philippines)">>
        },
        <<"en-TT">> => #{
            en => <<"English (Trinidad and Tobago)">>
        },
        <<"en-US">> => #{
            en => <<"English (United States)">>
        },
        <<"en-ZA">> => #{
            en => <<"English (South Africa)">>
        },
        <<"en-ZW">> => #{
            en => <<"English (Zimbabwe)">>
        },
        <<"eo">> => #{
            en => <<"Esperanto">>
        },
        <<"es">> => #{
            en => <<"Spanish">>
        },
        <<"es-AR">> => #{
            en => <<"Spanish (Argentina)">>
        },
        <<"es-BO">> => #{
            en => <<"Spanish (Bolivia)">>
        },
        <<"es-CL">> => #{
            en => <<"Spanish (Chile)">>
        },
        <<"es-CO">> => #{
            en => <<"Spanish (Colombia)">>
        },
        <<"es-CR">> => #{
            en => <<"Spanish (Costa Rica)">>
        },
        <<"es-DO">> => #{
            en => <<"Spanish (Dominican Republic)">>
        },
        <<"es-EC">> => #{
            en => <<"Spanish (Ecuador)">>
        },
        <<"es-ES">> => #{
            en => <<"Spanish (Spain)">>
        },
        <<"es-GT">> => #{
            en => <<"Spanish (Guatemala)">>
        },
        <<"es-HN">> => #{
            en => <<"Spanish (Honduras)">>
        },
        <<"es-MX">> => #{
            en => <<"Spanish (Mexico)">>
        },
        <<"es-NI">> => #{
            en => <<"Spanish (Nicaragua)">>
        },
        <<"es-PA">> => #{
            en => <<"Spanish (Panama)">>
        },
        <<"es-PE">> => #{
            en => <<"Spanish (Peru)">>
        },
        <<"es-PR">> => #{
            en => <<"Spanish (Puerto Rico)">>
        },
        <<"es-PY">> => #{
            en => <<"Spanish (Paraguay)">>
        },
        <<"es-SV">> => #{
            en => <<"Spanish (El Salvador)">>
        },
        <<"es-UY">> => #{
            en => <<"Spanish (Uruguay)">>
        },
        <<"es-VE">> => #{
            en => <<"Spanish (Venezuela)">>
        },
        <<"et">> => #{
            en => <<"Estonian">>
        },
        <<"et-EE">> => #{
            en => <<"Estonian (Estonia)">>
        },
        <<"eu">> => #{
            en => <<"Basque">>
        },
        <<"eu-ES">> => #{
            en => <<"Basque (Spain)">>
        },
        <<"fa">> => #{
            en => <<"Farsi">>
        },
        <<"fa-IR">> => #{
            en => <<"Farsi (Iran)">>
        },
        <<"fi">> => #{
            en => <<"Finnish">>
        },
        <<"fi-FI">> => #{
            en => <<"Finnish (Finland)">>
        },
        <<"fo">> => #{
            en => <<"Faroese">>
        },
        <<"fo-FO">> => #{
            en => <<"Faroese (Faroe Islands)">>
        },
        <<"fr">> => #{
            en => <<"French">>
        },
        <<"fr-BE">> => #{
            en => <<"French (Belgium)">>
        },
        <<"fr-CA">> => #{
            en => <<"French (Canada)">>
        },
        <<"fr-CH">> => #{
            en => <<"French (Switzerland)">>
        },
        <<"fr-FR">> => #{
            en => <<"French (France)">>
        },
        <<"fr-LU">> => #{
            en => <<"French (Luxembourg)">>
        },
        <<"fr-MC">> => #{
            en => <<"French (Principality of Monaco)">>
        },
        <<"gl">> => #{
            en => <<"Galician">>
        },
        <<"gl-ES">> => #{
            en => <<"Galician (Spain)">>
        },
        <<"gu">> => #{
            en => <<"Gujarati">>
        },
        <<"gu-IN">> => #{
            en => <<"Gujarati (India)">>
        },
        <<"he">> => #{
            en => <<"Hebrew">>
        },
        <<"he-IL">> => #{
            en => <<"Hebrew (Israel)">>
        },
        <<"hi">> => #{
            en => <<"Hindi">>
        },
        <<"hi-IN">> => #{
            en => <<"Hindi (India)">>
        },
        <<"hr">> => #{
            en => <<"Croatian">>
        },
        <<"hr-BA">> => #{
            en => <<"Croatian (Bosnia and Herzegovina)">>
        },
        <<"hr-HR">> => #{
            en => <<"Croatian (Croatia)">>
        },
        <<"hu">> => #{
            en => <<"Hungarian">>
        },
        <<"hu-HU">> => #{
            en => <<"Hungarian (Hungary)">>
        },
        <<"hy">> => #{
            en => <<"Armenian">>
        },
        <<"hy-AM">> => #{
            en => <<"Armenian (Armenia)">>
        },
        <<"id">> => #{
            en => <<"Indonesian">>
        },
        <<"id-ID">> => #{
            en => <<"Indonesian (Indonesia)">>
        },
        <<"is">> => #{
            en => <<"Icelandic">>
        },
        <<"is-IS">> => #{
            en => <<"Icelandic (Iceland)">>
        },
        <<"it">> => #{
            en => <<"Italian">>
        },
        <<"it-CH">> => #{
            en => <<"Italian (Switzerland)">>
        },
        <<"it-IT">> => #{
            en => <<"Italian (Italy)">>
        },
        <<"ja">> => #{
            en => <<"Japanese">>
        },
        <<"ja-JP">> => #{
            en => <<"Japanese (Japan)">>
        },
        <<"ka">> => #{
            en => <<"Georgian">>
        },
        <<"ka-GE">> => #{
            en => <<"Georgian (Georgia)">>
        },
        <<"kk">> => #{
            en => <<"Kazakh">>
        },
        <<"kk-KZ">> => #{
            en => <<"Kazakh (Kazakhstan)">>
        },
        <<"kn">> => #{
            en => <<"Kannada">>
        },
        <<"kn-IN">> => #{
            en => <<"Kannada (India)">>
        },
        <<"ko">> => #{
            en => <<"Korean">>
        },
        <<"ko-KR">> => #{
            en => <<"Korean (Korea)">>
        },
        <<"kok">> => #{
            en => <<"Konkani">>
        },
        <<"kok-IN">> => #{
            en => <<"Konkani (India)">>
        },
        <<"ky">> => #{
            en => <<"Kyrgyz">>
        },
        <<"ky-KG">> => #{
            en => <<"Kyrgyz (Kyrgyzstan)">>
        },
        <<"lt">> => #{
            en => <<"Lithuanian">>
        },
        <<"lt-LT">> => #{
            en => <<"Lithuanian (Lithuania)">>
        },
        <<"lv">> => #{
            en => <<"Latvian">>
        },
        <<"lv-LV">> => #{
            en => <<"Latvian (Latvia)">>
        },
        <<"mi">> => #{
            en => <<"Maori">>
        },
        <<"mi-NZ">> => #{
            en => <<"Maori (New Zealand)">>
        },
        <<"mk">> => #{
            en => <<"FYRO Macedonian">>
        },
        <<"mk-MK">> => #{
            en => <<"FYRO Macedonian (Former Yugoslav Republic of Macedonia)">>
        },
        <<"mn">> => #{
            en => <<"Mongolian">>
        },
        <<"mn-MN">> => #{
            en => <<"Mongolian (Mongolia)">>
        },
        <<"mr">> => #{
            en => <<"Marathi">>
        },
        <<"mr-IN">> => #{
            en => <<"Marathi (India)">>
        },
        <<"ms">> => #{
            en => <<"Malay">>
        },
        <<"ms-BN">> => #{
            en => <<"Malay (Brunei Darussalam)">>
        },
        <<"ms-MY">> => #{
            en => <<"Malay (Malaysia)">>
        },
        <<"mt">> => #{
            en => <<"Maltese">>
        },
        <<"mt-MT">> => #{
            en => <<"Maltese (Malta)">>
        },
        <<"nb">> => #{
            en => <<"Norwegian (Bokm?l)">>
        },
        <<"nb-NO">> => #{
            en => <<"Norwegian (Bokm?l) (Norway)">>
        },
        <<"nl">> => #{
            en => <<"Dutch">>
        },
        <<"nl-BE">> => #{
            en => <<"Dutch (Belgium)">>
        },
        <<"nl-NL">> => #{
            en => <<"Dutch (Netherlands)">>
        },
        <<"nn-NO">> => #{
            en => <<"Norwegian (Nynorsk) (Norway)">>
        },
        <<"ns">> => #{
            en => <<"Northern Sotho">>
        },
        <<"ns-ZA">> => #{
            en => <<"Northern Sotho (South Africa)">>
        },
        <<"pa">> => #{
            en => <<"Punjabi">>
        },
        <<"pa-IN">> => #{
            en => <<"Punjabi (India)">>
        },
        <<"pl">> => #{
            en => <<"Polish">>
        },
        <<"pl-PL">> => #{
            en => <<"Polish (Poland)">>
        },
        <<"ps">> => #{
            en => <<"Pashto">>
        },
        <<"ps-AR">> => #{
            en => <<"Pashto (Afghanistan)">>
        },
        <<"pt">> => #{
            en => <<"Portuguese">>
        },
        <<"pt-BR">> => #{
            en => <<"Portuguese (Brazil)">>
        },
        <<"pt-PT">> => #{
            en => <<"Portuguese (Portugal)">>
        },
        <<"qu">> => #{
            en => <<"Quechua">>
        },
        <<"qu-BO">> => #{
            en => <<"Quechua (Bolivia)">>
        },
        <<"qu-EC">> => #{
            en => <<"Quechua (Ecuador)">>
        },
        <<"qu-PE">> => #{
            en => <<"Quechua (Peru)">>
        },
        <<"ro">> => #{
            en => <<"Romanian">>
        },
        <<"ro-RO">> => #{
            en => <<"Romanian (Romania)">>
        },
        <<"ru">> => #{
            en => <<"Russian">>
        },
        <<"ru-RU">> => #{
            en => <<"Russian (Russia)">>
        },
        <<"sa">> => #{
            en => <<"Sanskrit">>
        },
        <<"sa-IN">> => #{
            en => <<"Sanskrit (India)">>
        },
        <<"se">> => #{
            en => <<"Sami">>
        },
        <<"se-FI">> => #{
            en => <<"Sami (Finland)">>
        },
        <<"se-NO">> => #{
            en => <<"Sami (Norway)">>
        },
        <<"se-SE">> => #{
            en => <<"Sami (Sweden)">>
        },
        <<"sk">> => #{
            en => <<"Slovak">>
        },
        <<"sk-SK">> => #{
            en => <<"Slovak (Slovakia)">>
        },
        <<"sl">> => #{
            en => <<"Slovenian">>
        },
        <<"sl-SI">> => #{
            en => <<"Slovenian (Slovenia)">>
        },
        <<"sq">> => #{
            en => <<"Albanian">>
        },
        <<"sq-AL">> => #{
            en => <<"Albanian (Albania)">>
        },
        <<"sr-BA">> => #{
            en => <<"Serbian (Latin) (Bosnia and Herzegovina)">>
        },
        <<"sr-Cyrl-BA">> => #{
            en => <<"Serbian (Cyrillic) (Bosnia and Herzegovina)">>
        },
        <<"sr-SP">> => #{
            en => <<"Serbian (Latin) (Serbia and Montenegro)">>
        },
        <<"sr-Cyrl-SP">> => #{
            en => <<"Serbian (Cyrillic) (Serbia and Montenegro)">>
        },
        <<"sv">> => #{
            en => <<"Swedish">>
        },
        <<"sv-FI">> => #{
            en => <<"Swedish (Finland)">>
        },
        <<"sv-SE">> => #{
            en => <<"Swedish (Sweden)">>
        },
        <<"sw">> => #{
            en => <<"Swahili">>
        },
        <<"sw-KE">> => #{
            en => <<"Swahili (Kenya)">>
        },
        <<"syr">> => #{
            en => <<"Syriac">>
        },
        <<"syr-SY">> => #{
            en => <<"Syriac (Syria)">>
        },
        <<"ta">> => #{
            en => <<"Tamil">>
        },
        <<"ta-IN">> => #{
            en => <<"Tamil (India)">>
        },
        <<"te">> => #{
            en => <<"Telugu">>
        },
        <<"te-IN">> => #{
            en => <<"Telugu (India)">>
        },
        <<"th">> => #{
            en => <<"Thai">>
        },
        <<"th-TH">> => #{
            en => <<"Thai (Thailand)">>
        },
        <<"tl">> => #{
            en => <<"Tagalog">>
        },
        <<"tl-PH">> => #{
            en => <<"Tagalog (Philippines)">>
        },
        <<"tn">> => #{
            en => <<"Tswana">>
        },
        <<"tn-ZA">> => #{
            en => <<"Tswana (South Africa)">>
        },
        <<"tr">> => #{
            en => <<"Turkish">>
        },
        <<"tr-TR">> => #{
            en => <<"Turkish (Turkey)">>
        },
        <<"tt">> => #{
            en => <<"Tatar">>
        },
        <<"tt-RU">> => #{
            en => <<"Tatar (Russia)">>
        },
        <<"ts">> => #{
            en => <<"Tsonga">>
        },
        <<"uk">> => #{
            en => <<"Ukrainian">>
        },
        <<"uk-UA">> => #{
            en => <<"Ukrainian (Ukraine)">>
        },
        <<"ur">> => #{
            en => <<"Urdu">>
        },
        <<"ur-PK">> => #{
            en => <<"Urdu (Islamic Republic of Pakistan)">>
        },
        <<"uz">> => #{
            en => <<"Uzbek (Latin)">>
        },
        <<"uz-UZ">> => #{
            en => <<"Uzbek (Latin) (Uzbekistan)">>
        },
        <<"uz-Cyrl-UZ">> => #{
            en => <<"Uzbek (Cyrillic) (Uzbekistan)">>
        },
        <<"vi">> => #{
            en => <<"Vietnamese">>
        },
        <<"vi-VN">> => #{
            en => <<"Vietnamese (Viet Nam)">>
        },
        <<"xh">> => #{
            en => <<"Xhosa">>
        },
        <<"xh-ZA">> => #{
            en => <<"Xhosa (South Africa)">>
        },
        <<"zh">> => #{
            en => <<"Chinese">>
        },
        <<"zh-CN">> => #{
            en => <<"Chinese (S)">>
        },
        <<"zh-HK">> => #{
            en => <<"Chinese (Hong Kong)">>
        },
        <<"zh-MO">> => #{
            en => <<"Chinese (Macau)">>
        },
        <<"zh-SG">> => #{
            en => <<"Chinese (Singapore)">>
        },
        <<"zh-TW">> => #{
            en => <<"Chinese (T)">>
        },
        <<"zu">> => #{
            en => <<"Zulu">>
        },
        <<"zu-ZA">> => #{
            en => <<"Zulu (South Africa)">>
        }
    }.

%% @private
to_bin(K) when is_binary(K) -> K;
to_bin(K) -> nklib_util:to_binary(K).


