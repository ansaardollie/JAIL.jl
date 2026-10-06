# Anthropic automatic prompt caching (Preference, off by default)

| Field | Value |
|-------|-------|
| Artifact | `37_MESSAGES_anthropic_prompt_cache.md` |
| Category | work_history |
| Subject | `MESSAGES` — Anthropic request caching and usage totals |
| Date | 2026-10-06 |
| Area/Purpose scope | Anthropic provider, Preferences, docs |
| Related | `design_decisions/43_MESSAGES_anthropic_prompt_cache.md`, `36_TOOLS_tool_search_and_loaded_tools.md` |

## Scope of This Unit of Work

Previous artifact (`36_...`) ended with the tool-search live-check todo (untouched). The owner
asked for top-level `"cache_control": {"type": "ephemeral"}` on Anthropic requests ("not on each
message but the whole chain"), then Preferences to turn it off or use the 1-hour TTL, then "the
default should be off".

## What Changed

| File | Change |
|-------|--------|
| `src/providers/anthropic.jl` | `_anthropic_cache(p)` reads `providers.anthropic.prompt_cache` (`"off"` default, `"5m"`, `"1h"`, else ArgumentError); `_request_body` adds top-level `cache_control` when set; `_anthropic_usage` sums `input_tokens + cache_read_input_tokens + cache_creation_input_tokens` (non-stream and `message_start`) |
| `src/ontology/messages.jl` | `Usage` docstring: input includes cached tokens |
| `docs/src/guide/chat.md`, `docs/src/guide/providers.md` | caching paragraph; Preferences row |
| `examples/LocalPreferences.toml` | `prompt_cache = "off"` with comment |

## Design Decisions Made

`design_decisions/43_MESSAGES_anthropic_prompt_cache.md`: one key with `"off"/"5m"/"1h"`
(rejected: Bool + TTL key; per-block breakpoints); `Usage.input_tokens` stays a total (rejected:
uncached-only).

## Verification

REPL (prefs snapshot and restored):
```
5m => Dict{String, Any}("type" => "ephemeral")
1h => Dict{String, Any}("type" => "ephemeral", "ttl" => "1h")
off => (none)
1d => ArgumentError: Preference `providers.anthropic.prompt_cache` must be "5m", "1h" or "off", got "1d"
```
After the default change: `(JAIL._anthropic_cache(Anthropic()), haskey(body, "cache_control"))` →
`(nothing, false)`. Usage from `input 50, cache_read 100000, cache_creation 248, output 503` →
`Usage(100298 in, 503 out)`. `count_tokens` body keys `["messages", "model", "system"]`.
Docs build: no warnings.

Not verified: a live Anthropic request with caching on (cache hit counts).

## Known Limitations

- Cache read/write counts are folded into `input_tokens`, not exposed separately.
- Setting is per provider, not per session.

## Todos

- Completed: none
- Created: none

## Next Steps

- With owner approval, live-check `prompt_cache = "5m"` on a two-turn Anthropic session (second
  reply should report `cache_read_input_tokens`); can join `todos/pending/10_TOOLS_live_check_tool_search.md`.
