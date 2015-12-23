# nklib_util



### append_max/3
### apply/3
### bin_last/2
### bjoin/1
### bjoin/2
### call/2
### call/3
### cancel_timer/1
### capitalize/1
### defaults/2
### delete/2
### demonitor/1
### ensure_all_started/2
### extract/2
### filter_values/2
### filtermap/2
### get_binary/2
### get_binary/3
### get_integer/2
### get_integer/3
### get_list/2
### get_list/3
### get_value/2
### get_value/3
### gmt_to_timestamp/1
### hash/1
### hash36/1
### hex/1
### is_string/1
### keys/1
### l_timestamp_to_float/1
### l_timestamp/0
### lhash/1
### local_to_timestamp/1
### luid/0
### msg/2
### randomize/1
### remove_values/2
### safe_call/3
### sha/1
### store_value/2
### store_value/3
### store_values/2

### strip/1
> Strips trailing white space  
  NOTE: Really strips leading spaces
  TODO: Should change this to strip leading and trailing



### timestamp_to_gmt/1
### timestamp_to_local/1
### timestamp/0
### to_atom/1
> Converts anything into a 'atom()'.  
  WARNING: Can create new atoms

### to_binary/1
> Converts anything into a 'binary()'. Can convert ip addresses also.

### to_binlist/1
> Converts a binary(), string() or list() to a list of binaries

### to_boolean/1
> Converts anything into a 'integer()' or 'error'.

### to_existing_atom/1
> Converts anything into an existing atom or throws an error

### to_host/1
> Converts an IP or host to a binary host value

### to_host/2
> Converts an IP or host to a binary host value.
  If 'IsUri' and it is an IPv6 address, it will be enclosed in '[' and ']'

### to_integer/1
> Converts anything into a 'integer()' or 'error'.

### to_ip/1
> Converts a 'list()' or 'binary()' into a 'inet:ip_address()' or 'error'.

### to_list/1
> Converts anything into a 'string()'.

### to_lower/1
> converts a 'string()' or 'binary()' to a lower 'binary()'.

### to_map/1
> If input is a map, return the map.  If it is a list, return a map from the list

### to_upper/1
> converts a 'string()' or 'binary()' to an upper 'binary()'.

### uid/0

### unquote/1
> Removes double quotes at the beginning and end.  For example: nklib_util:unquote(<<"\"JAMES\"">>) -> "JAMES"

### uuid_4122/0
### words/1
