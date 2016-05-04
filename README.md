# NkLIB: NetComposer's common Erlang library functions

NkLIB includes a serie of common utilities and services for NkCORE, but probably useful for other applications:

* [**nklib_code**](src/nklib_code.erl): Utilities for code generation.
* [**nklib_config**](src/nklib_config.erl): Generic configuration and syntax management.
* [**nklib_counters**](src/nklib_counters.erl): ETS-based process couters. Any process can register and update any number of counters, and they can be shared with other processes. When the process exists, all updates made from that process are reverted.
* [**nklib_exec**](src/nklib_exec.erl): Allows to start and manage external OS processes.
* [**nklib_headers**](src/nklib_headers.erl): General header (HTTP, SIP, etc.) manipulation functions.
* [**nklib_json**](src/nklib_json.erl): Wrappers for JSON processing.
* [**nklib_parse**](src/nklib_parse.erl) and [**nklib_unparse.erl**](src/nklib_unparse.erl): high perfomance parsers and unparsers for URIs, Schemes, Tokens, Integers and Dates.
* [**nklib_proc**](src/nklib_proc.erl): Yet another ETS-based process registry. It allows a process to register any `term()` as a process identification, and store any metadata with it. When the process exists, these terms are deleted. 
* [**nklib_reglist**](src/nklib_reglist.erl): Datatype and related functions useful for managing lists of processes registering for events.
* [**nklib_store**](src/nklib_store.erl): ETS-based database, with auto expiring of records, server-side update funs and calling an user fun on record expire.
* [**nklib_util**](src/nklib_util.erl): Over 50 generic functions for UIDs, type conversions, dates, hashes, timers, etc.
