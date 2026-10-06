# TODO: Live-check parallel tool calls

| Field | Value |
|-------|-------|
| Artifact | `11_TOOLS_live_check_parallel_tool_calls.md` |
| Category | todos |
| Subject | `TOOLS` |
| Date created | 2026-10-06 |
| Area/Purpose scope | providers, tool loop, streaming display |
| Related | `work_history/39_TOOLS_parallel_tool_calls.md`, `design_decisions/45_TOOLS_parallel_tool_calls.md` |
| Priority | normal |
| Owner | any |

## What

With the owner's permission, ask each provider for two independent tool calls in one turn (e.g.
`read_file` on two files) in the `}` mode with `stream = true`, once with
`parallel_tool_calls = true` and once `false`. Also run once in a real terminal with
`julia -t 1` (the `@async` fallback) and with a confirmation-needing call in the batch.

## Why

Only a mock server verified the wire fields (`parallel_tool_calls: false`,
`tool_choice.disable_parallel_tool_use`) and the grouped `→` line; the alternate-screen display
and the single-thread path were not seen live.

## Acceptance Criteria

- [ ] OpenAI and Anthropic return several calls when on and one per reply when off
- [ ] Google with several calls runs them (concurrently when on)
- [ ] Grouped `→` line and confirmed-call lines look right on a real terminal
- [ ] `julia -t 1` run overlaps I/O-bound calls

## Notes

Live calls need owner approval each time.
