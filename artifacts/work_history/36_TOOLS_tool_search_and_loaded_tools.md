# Tool search: registered vs loaded tools, hosted and client-side search

| Field | Value |
|-------|-------|
| Artifact | `36_TOOLS_tool_search_and_loaded_tools.md` |
| Category | work_history |
| Subject | `TOOLS` — tool search, session tool status, built-ins registered by default |
| Date | 2026-10-06 |
| Area/Purpose scope | ontology, providers (OpenAI, Anthropic, Google, compatible), sessions, persistence, REPL, docs |
| Related | `design_decisions/42_TOOLS_tool_search_and_loaded_tools.md`, `35_TOOLS_http_request_memory_tool_restore.md` |

## Scope of This Unit of Work

Previous artifact (`35_...`) ended with live-check todos (untouched). The owner asked for tool
search: "registered" = sent with deferred loading, new status "loaded" = sent in full; OpenAI
hosted `tool_search`, Anthropic `tool_search_tool_bm25_20251119`; Google (no native search) gets
JAIL tools `tool_search(keywords)` / `tool_load(names)`; every built-in registered by default
with none loaded; two array Preferences; system instructions mention tool search. Then a
documentation pass (julia-documenter mode).

## What Changed

| File | Change |
|-------|--------|
| `src/ontology/messages.jl` | `ToolSearchPart(format, data)` (exported); `_search_kind`; `_replays` covers it |
| `src/ontology/requests.jl` | `_Request.deferred` (12th field); `_supports_hosted_tool_search` (false by default); `_tool_search_mode(p)` reads `providers.<name>.tool_search` |
| `src/session.jl` | `Session.loaded_tools`; `Session`/`new_session!` kwarg `loaded_tools`; `_load_names`, `_default_loaded` (Preference `loaded_tools`), `_loaded_specs`; `load_tools!`, `unload_tools!`, `tool_status` (+ session-less forms); `loaded` row in `show` |
| `src/tools.jl` | `register_tool!(f; load = false)`; `@tool load=` option |
| `src/builtin_tools/common.jl` | `_register_builtin_prefs!`: Preference `registered_tools` (default all groups); warns if old `builtin_tools` set; docstrings |
| `src/builtin_tools/tool_search.jl` (new) | `tool_search`, `tool_load`, `_client_search_specs` (never registered) |
| `src/builtin_tools/repl.jl` | `_never_confirm` covers `tool_search`/`tool_load` |
| `src/chat.jl` | `_request_tools(s, p)` → (loaded, deferred, runnable), recomputed each tool round; `_complete(...; deferred)`; `_fp_part(::ToolSearchPart)`; `_search_line` |
| `src/tokens.jl` | counts with the same loaded/deferred split |
| `src/providers/openai.jl` | deferred tools with `defer_loading` + `{"type":"tool_search"}`; parses/replays `tool_search_call`/`tool_search_output`; `_deferred` helper; hosted support |
| `src/providers/anthropic.jl` | BM25 search tool + deferred tools; parses/streams/replays `server_tool_use`/`tool_search_tool_result`; hosted support |
| `src/persistence.jl` | `tool_search` part encode/decode; session JSON `loaded_tools`, restored (old files → Preference) |
| `src/system_prompt.jl` | tool-search bullet in `_REPL_INSTRUCTIONS` |
| `src/repl/model_mode.jl`, `chat_mode.jl` | `tools load/unload`, `L` marker, `status:` in `tools show`; `⌕` lines for hosted search when streaming |
| `src/JAIL.jl` | exports `ToolSearchPart`, `load_tools!`, `unload_tools!`, `tool_status`; include |
| docs (`tools.md` Tool search section, `providers.md`, `sessions.md`, `repl.md`, `concepts.md`, `chat.md`, `index.md`, `reference.md`, `builtin_tools.md`), `docs/make.jl` `__clear__` | documented; repl transcripts regenerated |
| `examples/tool_search.jl` (new), `examples/builtin_tools.jl`, `examples/LocalPreferences.toml` | example; header update; `registered_tools`, `loaded_tools`, per-provider `tool_search` |
| `design_decisions/31`, `32` | "Superseded in part by 42" lines |

## Design Decisions Made

`design_decisions/42_TOOLS_tool_search_and_loaded_tools.md`: per-session loaded status (rejected:
global, global + session); `registered_tools`/`loaded_tools` (rejected: keep `builtin_tools`);
OpenAICompatible client-side (rejected: hosted on Responses); per-provider `tool_search`
Preference (rejected: always hosted, guessing from model id); exported `ToolSearchPart`;
`load = true` → active session only (rejected: every session, dropping the kwarg).

## Verification

Mock Google Interactions server, `_tool_loop!(s, 10, "yolo")`:
```
1: tools=["tool_search", "tool_load"]
2: tools=["tool_search", "tool_load"]
3: tools=["get_weather", "tool_search", "tool_load"]
← tool_load "Loaded get_weather. You can now call it. Not found (search with `tool_search`): bogus."
loaded: ["get_weather"] status: loaded
```
Request bodies: Google `["read_file", "tool_search", "tool_load"]`; OpenAI
`("read_file", 0), ("add_memory", 1), …, ("tool_search", 0)` n=32; Anthropic
`("read_file", "", 0), ("tool_search_tool_bm25", "tool_search_tool_bm25_20251119", 0), ("add_memory", "", 1)`.
Anthropic SSE → `[ToolSearchPart(:anthropic, "server_tool_use"), ToolSearchPart(:anthropic, "tool_search_tool_result"), ToolCall(get_weather(city = "Paris"))]`;
replay hosted `["server_tool_use", "tool_search_tool_result", "tool_use"]`, without search `["tool_use"]`.
OpenAI: `["user", "tool_search_call", "tool_search_output", "function_call", "function_call_output"]` / `["user", "function_call", "function_call_output"]`.
Preferences: `registered_tools = ["read","ask_user"]` → read group + ask_user; `[]` → none;
`loaded_tools = ["read","later_tool"]` expanded; `providers.anthropic.tool_search = "client"` →
`["tool_search","tool_load"]`; `"bogus"` → ArgumentError. Persisted session restored
`["read_file"]` and its `ToolSearchPart`. `examples/tool_search.jl` ran offline (output in
chat). Owner's `LocalPreferences.toml` unchanged afterwards. Docs build: 0 warnings.

Not verified: any live OpenAI/Anthropic/Google call with tool search.

## Known Limitations

- Anthropic `pause_turn` maps to `:other` and ends the turn.
- Replaying a `tool_search_tool_result` that references a since-unregistered tool → Anthropic 400.
- Hosted search needs gpt-5.4+ / Claude 4.5+; older models fail until `tool_search = "client"`.
- `tool_search` matches names as well as descriptions (agent addition).
- The `loaded` label always says "(others found with …)", even with no other tools.
- `register_tool!(f; load = true)` doesn't affect sessions created later.
- No automated tests.

## Todos

- Completed: none (`5_TOOLS_builtin_tools.md` updated: Google mock tool round done; `&` mode remains)
- Created: `10_TOOLS_live_check_tool_search.md`

## Next Steps

- `todos/pending/10_TOOLS_live_check_tool_search.md` (needs owner approval for live calls).
- Decide whether `pause_turn` should re-send to continue.
- `todos/pending/5_TOOLS_builtin_tools.md` item 4: the `&` mode.
