> **Superseded in part by:** `46_HARNESS_agent_mode_agents_and_skills.md` (only agent mode offers tools; `}`/`chat!` send none; the tool-search instruction line moves to the agent boilerplate)

# Decision: Tool search — registered vs loaded tools, hosted vs client search

| Field | Value |
|-------|-------|
| Artifact | `42_TOOLS_tool_search_and_loaded_tools.md` |
| Category | design_decisions |
| Subject | `TOOLS` |
| Date | 2026-10-06 |
| Area/Purpose scope | core ontology, public API, Preferences, providers (OpenAI, Anthropic, Google, compatible), REPL |
| Related | `17_TOOLS_definitions_and_registry.md`, `18_TOOLS_session_tools_and_call_loop.md`, `31_TOOLS_builtin_tools_policy.md`, `32_TOOLS_builtin_tools_groups_and_rules.md`, `24_SESSION_persistence.md`, `25_MESSAGES_reasoning_part.md` |
| Status | accepted |
| Decided by | user (request + two question rounds); agent (details listed) |

## Context

User: "We need to be able to support tool search ... registered will now mean put into the
request with deferred loading set to true. and there should also be a new status: `loaded` which
means the tool is added to available tools without deferred loading." Use
`tool_search_tool_bm25_20251119` for Anthropic and `tool_search` for OpenAI. "By default all
builtin tools should be registered with none loaded", with two array Preferences for registered
and loaded tools. Google has no native search, so JAIL provides `tool_search(keywords)` (case-
insensitive regex over registered tools' descriptions; no keywords = all) and `tool_load(names)`.
System instructions say tool search is available and to check for a relevant tool first.

## Questions and Answers

| Question | Options | Chosen |
|---|---|---|
| Where "loaded" lives | global + session tool_load; global only; per session only | **per session only** (Preference sets each new session's loads) |
| Preference keys | `registered_tools` + `loaded_tools`; keep `builtin_tools` + `loaded_tools` | **`registered_tools` + `loaded_tools`**; `builtin_tools` dropped with a warning |
| Julia API | `load_tools!`, `unload_tools!`, `tool_status`, `register_tool!(f; load)`, `@tool load=`, `|` `tools load/unload` | **as proposed** |
| OpenAICompatible | client-side; hosted on Responses | **client-side** (like Google) |
| Models without hosted search | always hosted; per-provider Preference; guess from model id | **Preference `providers.<name>.tool_search = "hosted" \| "client"`** |
| Storing hosted search steps | exported `ToolSearchPart(format, data)`; internal part | **exported `ToolSearchPart`** |
| `load = true` at registration | every session; active session only; drop kwarg | **active session only** |
| Session API | `Session(...; loaded_tools = nothing)` + session/session-less forms, saved with session | **as proposed** |

## Decision

```julia
Session(model; loaded_tools = nothing)     # nothing = Preference `loaded_tools`
new_session!(; loaded_tools = nothing)
load_tools!(s, xs...) / load_tools!(xs...)        -> Vector{ToolSpec} (session's loaded)
unload_tools!(s, xs...) / unload_tools!(xs...)
tool_status(s, x) / tool_status(x)                -> :unregistered | :registered | :loaded
register_tool!(f; load = false); @tool load=true f
struct ToolSearchPart <: AbstractContentPart; format::Symbol; data::Dict{String,Any}; end
```

Preferences: `registered_tools` (built-in groups/names, default all, `[]` none), `loaded_tools`
(tool/group names, default none), `providers.openai.tool_search` / `providers.anthropic.tool_search`
(`"hosted"` default, `"client"`).

Agent-decided:

- `Session.loaded_tools::Vector{String}`; names, not validated against the registry when they
  come from the Preference (a tool registered later still counts). `xs` are names, functions,
  ToolSpecs or groups (`"read"` or `"group:read"`; a tool name wins over a group name).
- Per request (`_request_tools`): loaded = session tools in `loaded_tools`; deferred = the rest.
  No deferred tools → plain tools, no search. Hosted → `_Request.deferred` sent with
  `defer_loading: true` + search tool. Client → loaded + JAIL's `tool_search`/`tool_load`
  (never registered, never confirmed, group `tool_search`). Recomputed each tool round so
  `tool_load` takes effect on the next request. Calls to any session tool still run (lenient).
- `tool_search` matches name **and** description (user said descriptions; name added since a
  keyword like "weather" for `get_weather` would otherwise miss). Only registered-not-loaded
  tools are listed. Invalid regex falls back to a substring match.
- `tool_load` loads only tools available to the calling session; unknown names listed in the
  result; all unknown → error result.
- Hosted search steps (`server_tool_use`/`tool_search_tool_result`; `tool_search_call`/
  `tool_search_output`) become `ToolSearchPart`s, replayed only to the same provider type and
  format, and only when the request carries hosted search (otherwise the API rejects them).
  Persisted as `{"type": "tool_search", format, data}`. Streamed turns show `⌕` lines.
- `_supports_hosted_tool_search(::Type{OpenAI|Anthropic}) = true`; others false.

## Rejected

- Global loaded status (one session's `tool_load` would leak into others).
- Hosted search for OpenAICompatible (most servers lack it).
- Guessing support from model ids (fragile).

## Consequences

- Supersedes decisions 31/32 "built-ins are never registered at load": every `}`/`chat!` session
  now offers all built-ins (deferred). Approval rules are unchanged.
- Anthropic `pause_turn` (server tool loop paused) still maps to `:other` and ends the turn.
- A `tool_search_tool_result` referencing a tool later unregistered makes Anthropic reject a full
  replay ("Tool reference ... not found").
- OpenAI/Anthropic models older than gpt-5.4 / Claude 4.5 fail until `tool_search = "client"`.

## Revisit Trigger

Anthropic `pause_turn` seen in practice; providers adding namespaces/MCP search the owner wants;
Google adding native search; owner wanting a global default for `load = true`.
