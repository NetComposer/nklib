REPO ?= nklib

.PHONY: deps

all: deps compile

compile:
	./rebar compile

deps:
	./rebar get-deps

clean: 
	./rebar clean

distclean: clean
	./rebar delete-deps

tests: compile eunit

eunit:
	./rebar eunit skip_deps=true

shell:
	erl -pa deps/lager/ebin -pa deps/goldrush/ebin -pa deps/jsx/ebin -pa deps/jiffy/ebin \
	    -pa ebin -s nklib_app


docs:
	./rebar skip_deps=true doc

EDOC_OPTS = '[{source_path,["./src"]},\
 			{dir,"./edocs"}, \
			{private,true}, \
			{todo,true} \
			]'

edocs: edocsclean
	erl -noshell -run edoc_run packages '[""]' $(EDOC_OPTS)

edocsclean:
	rm -Rf edocs

APPS = kernel stdlib sasl erts ssl tools os_mon runtime_tools crypto inets \
	xmerl webtool snmp public_key mnesia eunit syntax_tools compiler
COMBO_PLT = $(HOME)/.$(REPO)_combo_dialyzer_plt

check_plt: 
	dialyzer --check_plt --plt $(COMBO_PLT) --apps $(APPS)

build_plt: 
	dialyzer --build_plt --output_plt $(COMBO_PLT) --apps $(APPS) 

dialyzer:
	dialyzer -Wno_return --plt $(COMBO_PLT) ebin/nklib*.beam

cleanplt:
	@echo 
	@echo "Are you sure?  It takes about 1/2 hour to re-build."
	@echo Deleting $(COMBO_PLT) in 5 seconds.
	@echo 
	sleep 5
	rm $(COMBO_PLT)
