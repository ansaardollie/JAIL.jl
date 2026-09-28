# Tool calling: definitions, session tools and the call loop

| Field | Value |
|-------|-------|
| Artifact | `11_TOOLS_tool_calling.md` |
| Category | work_history |
| Subject | `TOOLS` |
| Date | 2026-09-28 |
| Area/Purpose scope | core ontology, provider layer, public API, REPL surface, docs |
| Related | `design_decisions/17_TOOLS_definitions_and_registry.md`, `design_decisions/18_TOOLS_session_tools_and_call_loop.md`, `provider_reviews/4_TOOLS_function_calling.md`, `10_STREAMING_alternate_screen.md` |

## Scope of This Unit of Work

Next step 3 of `10_STREAMING_alternate_screen.md` (tools, redesign note #8). User requests:

1. "a `register_tool(f::Function)` function which ... reflect[s] on the function to extract the
   parameters ... as well the description from docs ... adds it to a central registry ... a
   `@tool` macro ... `@tool func_name1 func_name2 func_name3`".
2. "implementing the conversion to provider specific API shapes ... a way to view all tools in
   the model repl mode ... attach all tools to the session but add functionality to restrict to
   a subset (in both code and the model repl mode)". Scope question answered: full call loop.
3. Docs pass against the agent's design principles.

## What Changed

| File | Change |
|-------|--------|
| `src/ontology/tools.jl` | new: `ToolSpec` (name, description, parameters, f), `ToolParameter` (name, type, schema, description, required), `show` |
| `src/tools.jl` | new: registry `_TOOLS`, `register_tool!`, `@tool`, `tools()`, `unregister_tool!`; reflection (`_tool_method` longest method with prefix check on types and arg names, `_tool_name` `!`→`_bang` + Anthropic pattern), docstring parsing (`_raw_docstring` via `Docs.meta`, `_parse_docstring` drops signature block, extracts `# Arguments`), `_json_schema` (nullable as type array), `_parameters_schema`; execution: `_from_json`, `_call_args`, `_result_text` (string / JSON / repr), `_confirm_tools`, `_confirm`, `_run_tool` (errors become `is_error` results) |
| `src/ontology/messages.jl` | `ToolCall`, `ToolResult` content parts; `ToolResultMessage`; `_tool_calls`, `_role(::ToolResultMessage) = "tool"`, `_short`, `_call_signature`; shows list calls |
| `src/ontology/requests.jl` | `_Request.tools`; `_replayable` keeps call-only replies and results; `_stop_reason` (calls ⇒ `:tool_use`); `_arguments` (JSON string/object, bad JSON kept under `__invalid_json__`) |
| `src/providers/openai.jl` | Responses: `tools` (`_function_json`, no `strict`), `function_call` replay without `fc_` id, `function_call_output`, parse `function_call` items |
| `src/providers/openai_compatible.jl` | Chat Completions: `tools`, assistant `tool_calls`, `role: tool` messages, parse + stream `delta.tool_calls` by index |
| `src/providers/anthropic.jl` | `tools` (`input_schema`), `tool_use` / `tool_result` (+`is_error`) blocks, consecutive same-role turns merged, parse + stream `input_json_delta` |
| `src/providers/google.jl` | `tools`, `function_call` / `function_result` (+`is_error`) steps, parse + stream `arguments_delta`; removed `_step_type` |
| `src/session.jl` | `Session.tools::Union{Nothing,Vector{String}}` (nothing = all), `tools =` kwarg on `Session`/`new_session!`, `tools(s)`, `set_tools!(s, xs)` / `set_tools!(xs)`, `_tool_names`, `tools:` line in show |
| `src/chat.jl` | `_tool_loop!` (sequential, `max_tool_rounds` limit ⇒ "not run" error results, whole turn rolled back on failure), `on_step` hook, `_print_tool`, `_max_tool_rounds`, fingerprint covers tool parts, `chat!(...; max_tool_rounds)` |
| `src/repl/model_mode.jl` | `tools`, `tools show/use/add/drop/all/none`, completion, `Tools:` in `status` |
| `src/repl/chat_mode.jl` | `_render_text`, `_render_turn`; `_chat_send` renders replies and `→`/`←` lines live (non-stream) or the whole turn after the alternate screen (stream) |
| `src/JAIL.jl` | exports `ToolSpec, register_tool!, @tool, tools, unregister_tool!, set_tools!, ToolCall, ToolResult, ToolResultMessage`; includes |
| `docs/` | new `guide/tools.md`; `index`, `concepts`, `sessions`, `chat`, `providers` (Preferences table), `repl` (commands, transcript), `reference`; `make.jl` clears `max_tool_rounds`, `confirm_tools` |
| `examples/tools.jl` | new; `examples/chat.jl`, `examples/sessions.jl` headers updated |
| `artifacts/` | decisions 17, 18; provider review 4; decision 9 marked superseded in part |

## Decisions

- `design_decisions/17_TOOLS_definitions_and_registry.md`: standard docstring (rejected: in-body
  via source re-parse; both forms), `register_tool!` (rejected: `register_tool`), `ToolSpec`
  (rejected: `Tool`, `ToolDefinition`), `# Arguments` parsing, untyped ⇒ any JSON, kwargs ignored
  with warning, `!` ⇒ `_bang`, `tools()` + `unregister_tool!`.
- `design_decisions/18_TOOLS_session_tools_and_call_loop.md`: full loop now (rejected: conversion
  only; parse-only), `tools(s)` + `set_tools!` (rejected: `session_tools`, `restrict_tools!`),
  full `tools` REPL command set, `ToolCall` + `ToolResultMessage(results)` (rejected: results in
  `UserMessage`; one message per call), string/JSON/repr results, `max_tool_rounds` Preference
  default 10 + kwarg, `}` uses tools (rejected: text-only), tool lines only when `stream = true`,
  sequential + `confirm_tools` (rejected: concurrent).
- Docs follow the decisions where they diverge from the agent file's principles 8 (in-body
  docstring) and 10 (`}` text-only); the agent file was not edited.

## Verification

Fresh REPL load check (this housekeeping):

```
isdefined(JAIL, :ToolResultMessage) = true
hasmethod(chat!, Tuple{Session, String}, (:max_tool_rounds,)) = true
JAIL._load_pref("stream") = true
fieldnames(Session) = (:name, :model, :system, :tools, :messages)
```

Mock server (`HTTP.serve!`, response queue, doc-shaped fixtures), one tool round per provider,
default `store_requests = true`:

```
== openai: 2nd request {"input":[{"call_id":"call_1","output":"Sunny for 3 days in Paris","type":"function_call_output"}],"previous_response_id":"resp_1"}
== anthropic: 2nd request messages [..., {"content":[{"text":"Checking."},{"id":"toolu_1","input":{"city":"Paris"},"name":"get_weather","type":"tool_use"}],"role":"assistant"},{"content":[{"content":"Sunny for 3 days in Paris","tool_use_id":"toolu_1","type":"tool_result"}],"role":"user"}]
== google: {"input":[{"call_id":"fc1","name":"get_weather","result":"Sunny for 3 days in Paris","type":"function_result"}],"previous_interaction_id":"v1_1"}
== chat: {"content":null,"role":"assistant","tool_calls":[...]},{"content":"Sunny for 3 days in Paris","role":"tool","tool_call_id":"call_1"}
```

Other checks in the REPL:

```
openai full replay: [{"content":"Weather in Paris?","role":"user"},{"arguments":"{\"city\":\"Paris\"}","call_id":"call_1","name":"get_weather","type":"function_call"},{"call_id":"call_1","output":"Sunny for 3 days in Paris","type":"function_call_output"},...]
r.stop_reason = :tool_use            # max_tool_rounds = 0
merged: {"content":[{"content":"Not run: the limit of 0 tool rounds for this turn was reached.","is_error":true,"tool_use_id":"toolu_1","type":"tool_result"},{"text":"Never mind","type":"text"}],"role":"user"}
error: JAIL._APIError   length(f.messages) = 0     # rollback mid-loop
haskey((LOG[end])[2], "tools") = false             # tools = []
== anthropic (stream): "Let me check.\n→ get_weather(city = \"Rome\", days = 2)\n← Sunny for 2 days in Rome\nSunny in Rome.\n"
```

Streaming verified for all four wires; `}` mode rendered for `stream` true and false (Preference
snapshotted and restored, `JAIL._load_pref("stream") = true` afterwards); `_confirm` with
`"y\n"` ⇒ true, `"\n"` ⇒ false; model-mode commands, errors and completion; zero-argument
`list_directory()` registers with `{"properties":{},"required":[],"type":"object"}`.
`examples/tools.jl` offline sections ran; its `LIVE` section was **not run**. Docs built with no
warnings. **No live provider calls were made.**

## Known Limitations

- Google full-history replays drop `thought` steps (todo 4); thinking models may reject them.
- Google's function-parameter schema subset is UNVERIFIED for `{}` (untyped) and
  `additionalProperties` (dicts).
- OpenAI full replays re-send `function_call` without the `fc_` id or reasoning items (UNVERIFIED
  that the API accepts this for reasoning models).
- No `tool_choice`, `strict`, parallel execution, `name =` override, or built-in tools.
- A session with no tools registered shows `tools: all (none)`.
- `examples/tool_ex1.jl` (owner's scratch file) has a docstring with no function under it and
  fails to load; left untracked.

## Todos

- Completed: none
- Created: `5_TOOLS_builtin_tools.md`

## Next Steps

1. Live-check one tool round per provider (owner runs `examples/tools.jl` with `LIVE = true`).
2. `4_MESSAGES_replay_reasoning.md` (now also affects Google stateless tool turns).
3. `5_TOOLS_builtin_tools.md`: `execute_julia_code` and source lookup, then the `&` mode.
4. `1_TESTS_test_suite_setup.md`: port the tool mock-server checks above.
5. Owner: decide whether `.github/agents/jail-developer.agent.md` principles 8 and 10 should be
   updated to match decisions 17 and 18.
