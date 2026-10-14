%% @doc The JSON view of a read-model row: what the read API
%% (GET /api/tube/...) answers.
%%
%% The read model holds an MCID as the raw bytes the mesh carries --
%% `<<2, 16#55, SHA-384(Bytes):48>>', the one id shape `tube_content_store'
%% accepts -- and OTP's `json:encode/1' refuses the bytes that are not
%% valid UTF-8. So the channels page answered HTTP 500 for any channel that
%% had a logo (#15), and the clips pages did the same for any clip whose
%% thumbnail had been scanned.
%%
%% Every id therefore goes out in its documented text form, the lowercase
%% hex `/owner/content/:mcid_hex' takes, never as raw bytes.
%%
%% The check is on the VALUE, not on a list of field names: a byte id that
%% reaches a row by a path this module has never heard of is still an id,
%% and `json:encode/1' must not be the thing that discovers it. The id shape
%% itself is `tube_content_store''s to define, so it is asked, not restated
%% here (one module that knows the shape is the whole point of #16).
-module(tube_json_view).

-export([row/1]).

-spec row(map()) -> map().
row(Row) when is_map(Row) ->
    maps:map(fun(_Field, Value) -> view(Value) end, Row).

%% `tags' is a list, and a nested map is a row too: neither carries an id
%% today, and walking them costs nothing next to a 500.
view(Value) when is_map(Value) -> row(Value);
view(Value) when is_list(Value) -> [view(Element) || Element <- Value];
view(Value) when is_binary(Value) -> hex_if_mcid(Value);
view(Value) -> Value.

hex_if_mcid(Value) ->
    case tube_content_store:is_mcid(Value) of
        true  -> binary:encode_hex(Value, lowercase);
        false -> Value
    end.
