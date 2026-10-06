# TODO: Live-check tool search per provider

| Field | Value |
|-------|-------|
| Artifact | `10_TOOLS_live_check_tool_search.md` |
| Category | todos |
| Subject | `TOOLS` |
| Date created | 2026-10-06 |
| Area/Purpose scope | providers, tool loop |
| Related | `work_history/36_TOOLS_tool_search_and_loaded_tools.md`, `design_decisions/42_TOOLS_tool_search_and_loaded_tools.md` |
| Priority | normal |
| Owner | any |

## What

With the owner's permission, run one `chat!(s, "What files are in src/?"; stream = true)` on a
fresh session (no loaded tools) per provider: OpenAI (gpt-5.4+, hosted), Anthropic (Claude 4.5+,
hosted BM25), Google and GoogleEnterprise (client `tool_search`/`tool_load`), and OpenAI with
`providers.openai.tool_search = "client"`. Then a second turn so the history (with
`ToolSearchPart`s) is replayed, with `store_requests = false` once for a full replay.

## Why

Only mock servers verified the wire shapes; `defer_loading`, the search tool entries, replay of
search blocks/items and Anthropic `pause_turn` are untested live.

## Acceptance Criteria

- [ ] Each provider finds and calls a deferred tool (or the error is recorded)
- [ ] Full-history replay accepted by OpenAI and Anthropic
- [ ] Results in a work_history artifact; fixes for any mismatch

## Notes

Live calls need owner approval each time.
