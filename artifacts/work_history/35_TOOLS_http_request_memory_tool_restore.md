# http_request tool, session memory tools, restoring a session's tools

| Field | Value |
|-------|-------|
| Artifact | `35_TOOLS_http_request_memory_tool_restore.md` |
| Category | work_history |
| Subject | `TOOLS` — built-in tools and session persistence |
| Date | 2026-10-06 |
| Area/Purpose scope | built-in tools, persistence, docs |
| Related | `design_decisions/41_TOOLS_http_request_memory_tool_restore.md`, `34_MESSAGES_thinking_effort_temperature_reasoning.md` |

## Scope of This Unit of Work

Previous artifact (`34_...`) ended with live-check and reasoning-data todos (untouched here).
This unit: (1) a built-in `http_request` tool, `:high` unless its URL is in the new Preference
`url_allow_list`; (2) per-session memory tools; (3) fix: restored sessions didn't get their
tools back (owner's `memtesting` session got "Unknown tool `read_memory`. Available tools: none"
after a restart, because `"tools": null` doesn't record what was registered).

## What Changed

| File | Change |
|-------|--------|
| `src/builtin_tools/web.jl` | `http_request(url, method, query_params, body, headers)`; `_HTTP_METHODS`, `_url_allow_listed` (Preference `url_allow_list`, boundary match, rejects userinfo/backslash/dot segments), `_http_level`, `_http_url`, `_http_preview`; registered in group `web` |
| `src/builtin_tools/memory.jl` (new) | `read_memory`, `add_memory`, `remove_memory`; `_memory_path()` / `_memory_path(dir, id)` = `<dir>/memory/sessions/<id>.md`; `_read_memories`, `_write_memories`; group `memory`, all `:low` |
| `src/builtin_tools/common.jl` | `_BUILTIN_GROUPS` adds `"memory"`; `builtin_tools`/`register_builtin_tools!` docstrings list new tools/group |
| `src/JAIL.jl` | `include("builtin_tools/memory.jl")` |
| `src/persistence.jl` | `_session_json` writes `available_tools`; `_restore_tools!(names, session_name)` called from `_load_session` (registers missing built-ins, warns about others); `_delete_files!` removes the memory file; `restore_session!` docstring |
| `docs/src/guide/tools.md` | table rows, "HTTP requests" and "Memory" sections, `url_allow_list` in Preferences |
| `docs/src/guide/sessions.md` | `available_tools` field; restore re-registers built-ins |
| `docs/src/guide/providers.md` | `url_allow_list` row; `storage_dir` also holds memories |
| `docs/src/builtin_tools.md` | `http_request`; new `memory` section |
| `docs/make.jl` | `url_allow_list` in `__clear__` |
| `examples/LocalPreferences.toml` | commented `url_allow_list` |

## Design Decisions Made

See `design_decisions/41_TOOLS_http_request_memory_tool_restore.md` (no redirects/retry/cookies;
boundary prefix match; stable memory numbers; `available_tools` + re-register built-ins only).

## Verification

REPL, temp `storage_dir`, local `HTTP.serve!` on 127.0.0.1:18733 (prefs restored afterwards):

```
http://127.0.0.1:18732/api                   low
http://127.0.0.1:18732/api/x?y=1             low
http://127.0.0.1:18732/apix                  high
http://127.0.0.1:18732/api@evil.com          high
http://127.0.0.1:18732/api/../admin          high
http://127.0.0.1:18732/api/%2e%2e/admin      high
https://api.example.com/v1                   low
https://api.example.com.evil.org/            high
https://evil.org/                            high
```
`http_request("$B/api/x?a=1", "post", Dict("q"=>"a b&c"), "{\"k\":1}", Dict("X-Test"=>"hi",...))`
→ `HTTP 200` … `{"method":"POST","target":"/api/x?a=1&q=a%20b%26c","body":"{\"k\":1}","x":"hi"}`;
redirect → `HTTP 302` / `Location: https://evil.org/` / `(empty body)`; binary →
`(binary body: 4 bytes, application/octet-stream)`; `"ftp://x/"` and `"TRACE"` → ArgumentErrors;
`security_level` of allow-listed call `low`, `https://example.com/` `high`.

Memory: `(no memories yet)`; adds 1–3; `remove_memory(2)` → `removed: 2. Project uses Julia 1.13`;
next add → `4. fourth`; file `1. User prefers tabs` / `3. third` / `4. fourth`;
`remove_memory(2)` again → `ArgumentError: there is no memory number 2`; inside a `ToolContext`
the file is named by that session's id; `_delete_files!` removes it.

Restore: session with memory tools + custom `hi_tool` saved
`"available_tools": ["add_memory","hi_tool","read_memory","remove_memory"]`; after unregistering
all, `_load_session` → tools `["add_memory","read_memory","remove_memory"]` plus
`Warning: session "rt" could use tools that are not registered; ... hi_tool`; restricted session
`tools = ["read_memory"]` → registry `["read_memory"]`.

`julia --project=docs docs/make.jl`: first run failed with 4 `missing docs` (new tools), after
adding them: exit 0, no warnings.

Not verified: a live model calling these tools end to end; `restore_session!` via the menu.

## Known Limitations

- Sessions saved before this change have no `available_tools`; with `"tools": null` their
  built-ins are not re-registered until the next message rewrites the file.
- Restore registers built-ins globally (affects every `tools = nothing` session).
- User-defined tools can't be restored, only warned about.
- `url_allow_list` compare is case-sensitive text; no DNS/private-address check when allow-listed.
- `http_request` bodies are unbounded in size.
- No automated tests (`todos/pending/1_TESTS_test_suite_setup.md`).

## Todos

- Completed: none
- Created: none

## Next Steps

- Owner: `register_builtin_tools!("memory")` once (or Preference `builtin_tools`) so `memtesting` records `available_tools`.
- `todos/pending/9_MESSAGES_live_check_effort_reasoning.md`; live-check `http_request`/memory with a real model.
- Consider a response size cap for `http_request`.
