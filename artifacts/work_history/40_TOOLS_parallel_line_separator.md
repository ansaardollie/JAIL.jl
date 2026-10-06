# Grouped parallel-call line separated by `|`

| Field | Value |
|-------|-------|
| Artifact | `40_TOOLS_parallel_line_separator.md` |
| Category | work_history |
| Subject | `TOOLS` — streaming/status display of parallel calls |
| Date | 2026-10-06 |
| Area/Purpose scope | streaming display, docs, example |
| Related | `39_TOOLS_parallel_tool_calls.md`, `design_decisions/45_TOOLS_parallel_tool_calls.md` |

## Scope of This Unit of Work

Follows `39_...` (commit `e6f51cb`). The owner saw parallel calls working live and asked for the
grouped line to read `→ call1 | call2 | call3`, and for the non-streaming status line to use `|`
too.

## What Changed

| File | Change |
|-------|--------|
| `src/chat.jl` | `_print_tool(io, ::_RunningTogether)`: one leading `→ `, items joined by ` \| ` (was `→` per item joined by two spaces) |
| `src/repl/chat_mode.jl` | `_RunningTogether` status line joins labels with ` \| ` (was `, `) |
| `docs/src/guide/{tools,repl,chat}.md` | describe the `\|`-separated line and the status line |
| `examples/parallel_tool_calls.jl` | streaming comment shows the new line |

## Design Decisions Made

Owner-specified format. This supersedes the "joined by two spaces" detail in
`design_decisions/45_TOOLS_parallel_tool_calls.md` (artifact left unedited per the no-rewrite rule).

## Verification

REPL (after restart), mock Responses server:
```
--- stream=true tty=false
→ weather (Paris) | weather (Rome) | clock
--- stream=false tty=true
→ weather | weather | clock…
```
Example `examples/parallel_tool_calls.jl` streaming section:
```
→ append_log
→ weather (Paris) | weather (Rome)
```
Docs build: no warnings. Owner confirmed the grouped line live (before the separator change);
the new separator not seen on a real terminal by the agent.

## Known Limitations

Unchanged from `39_...`.

## Todos

- Completed: none
- Created: none (`todos/pending/11_TOOLS_live_check_parallel_tool_calls.md` still open)

## Next Steps

- `todos/pending/11_TOOLS_live_check_parallel_tool_calls.md`.
