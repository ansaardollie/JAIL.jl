# Saving HTTP requests and responses under JULIA_DEBUG

| Field | Value |
|-------|-------|
| Artifact | `38_DEBUG_save_http_exchanges.md` |
| Category | work_history |
| Subject | `DEBUG` — request/response files per session |
| Date | 2026-10-06 |
| Area/Purpose scope | HTTP layer, chat loop, token counting, persistence, docs |
| Related | `design_decisions/44_DEBUG_save_http_exchanges.md`, `37_MESSAGES_anthropic_prompt_cache.md` |

## Scope of This Unit of Work

Previous artifact (`37_...`) ended with a live caching check (untouched). The owner asked that,
with `JAIL` in `JULIA_DEBUG`, each HTTP request/response be saved under
`<storage_dir>/debug/<session_id>/<turn_id>/{request,response}.json` with url/headers/body and no
authorisation header.

## What Changed

| File | Change |
|-------|--------|
| `src/http.jl` | `_post_json`/`_post_sse` call `_debug_exchange` (request) and `_debug_response`; `_DEBUG_SESSION` ScopedValue, `_debug_enabled`, `_SECRET_HEADERS`, `_debug_headers`, `_maybe_json`, `_debug_write`; SSE events collected while debugging |
| `src/chat.jl` | `_chat!` runs the tool loop inside `with(_DEBUG_SESSION => s)` |
| `src/tokens.jl` | `count_tokens` likewise |
| `src/persistence.jl` | `_delete_files!` removes `debug/<session id>` |
| `src/JAIL.jl` | `using Base.ScopedValues: ScopedValue, with` |
| `docs/src/guide/chat.md` | Troubleshooting: the saved files |
| `examples/chat.jl` | comments mention the saved files |

## Design Decisions Made

`design_decisions/44_DEBUG_save_http_exchanges.md`: per-request folder id (rejected: per-turn
with numbered files); also strip `x-api-key`/`x-goog-api-key` (rejected: Authorization only).

## Verification

REPL, local `HTTP.serve!` Anthropic stand-in, temp `storage_dir` (Preference removed after):
```
2 turns: ["01a10f79-0568-711f-a618-05e2becbea7c", "01a10f79-0f0a-7142-84a3-01a8a5600948"]
request keys: ["url", "headers", "body"]
headers: JSON.Object{String, Any}("anthropic-version" => "2023-06-01", "Content-Type" => "application/json")
body model: claude-x
response: status=200 body text=hello
stream events: ["message_start", "content_block_start", "content_block_delta", "message_delta"]
secret in files: false
after delete: false
```
(The third turn, with `JULIA_DEBUG` cleared, wrote no folder.) Docs build: no warnings.

Not verified: live providers; GoogleEnterprise bearer header removal (same `authorization` rule).

## Known Limitations

- Files grow without bound while debugging; no cleanup other than deleting the session's files.
- Request bodies contain the full prompt and tool results (may include sensitive content).
- Model listing requests aren't saved.

## Todos

- Completed: none
- Created: none

## Next Steps

- Live checks: `todos/pending/10_TOOLS_live_check_tool_search.md` (debug files now make wire
  inspection easier), Anthropic `prompt_cache` hit counts.
