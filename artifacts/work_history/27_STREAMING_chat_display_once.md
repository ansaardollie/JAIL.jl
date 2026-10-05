# `chat!(...; stream = true)` shares the `}` mode's display; text shown once

| Field | Value |
|-------|-------|
| Artifact | `27_STREAMING_chat_display_once.md` |
| Category | work_history |
| Subject | `STREAMING` |
| Date | 2026-10-05 |
| Area/Purpose scope | public behavior, REPL surface, docs |
| Related | `design_decisions/33_STREAMING_chat_uses_chat_mode_display.md`, `work_history/26_DOCS_builtin_tools_prompts_and_drift.md` |

## Scope of This Unit of Work

Follows `26_DOCS_builtin_tools_prompts_and_drift.md` (commit `2f519b3`). User reports while
running `examples/builtin_tools_prompts.jl` line by line:

1. `replace_in_file` "argument error" — diagnosed, no change: the model's `old` text was not in
   `scratch/hello.jl` (it had not read the file; only `replace_in_file` was registered). Full
   message: `` `scratch/hello.jl`: `old` was not found; it must match the file exactly,
   including whitespace``; the `←` line cuts at 70 characters. Owner confirmed it works with
   `read_file` registered too.
2. "When using the `chat!` function the output is displayed twice" → decision 33.

## What Changed

| File | Change |
|-------|--------|
| `src/repl/chat_mode.jl` | `_chat_send` body moved into `_display_turn(io, s, prompt; stream, tty, header, output = true, kwargs...)` (kwargs to `_chat!`); `output = false` prints only the `Tool calls` block on a terminal; `_chat_send` calls it with `header = "chat> " * line` and keeps `_render_stop` |
| `src/chat.jl` | `chat!(...; stream = true)` → `_display_turn(stdout, s, prompt; stream = _supports_streaming(p), output = Base.source_path(nothing) !== nothing, max_tokens, max_tool_rounds)`; own inline printer removed; docstring |
| `docs/src/guide/chat.md` | Streaming section rewritten |

An earlier attempt (alternate screen + replaying tool lines in `chat!`) was undone by the owner
before this change.

## Decisions

- `33_STREAMING_chat_uses_chat_mode_display.md`: reuse `}` display without `Output:` (rejected:
  exactly `}`, return `nothing`, tool-lines-only, header-only display); agent-decided script
  detection prints `Output:` under `include`.

## Verification

Non-terminal REPL (agent), scripted Responses server, one tool call:

```
Let me look.
→ echo_tool
← echo_tool: hi
FINAL **TEXT**
Tool calls (1):
  ✓ echo_tool  ~/Workspaces/Julia/JAIL.jl/.jail/tools/01a10ccb-.../01a10ccb-....json
[returned] "FINAL **TEXT**"
read("LocalPreferences.toml", String) == lp = true
```

Real REPL prompt on a pty: `SP=nothing TTY=true` (so a prompt-level call takes the terminal,
no-`Output:` path). Docs: `julia --project=docs docs/make.jl` exit 0, no warnings. Load check:
`hasmethod(JAIL._display_turn, Tuple{IO, Session, String}) = true`.

**Not verified:** the terminal (alternate screen) path of `chat!` — the pty run was skipped by
the owner; the `}` mode after the refactor in a real terminal.

## Known Limitations

- At the REPL, text before tool calls is not kept on the normal screen (as in `}`).
- A trailing `;` hides the reply text entirely.
- The script heuristic depends on `SOURCE_PATH`; editors that set it for inline execution get
  `Output:` plus the REPL display.

## Todos

- Completed: none
- Created: none
- Updated: `2_REPL_real_terminal_check.md` (item 12)

## Next Steps

1. Owner: at a terminal REPL, `chat!(s, "..."; stream = true)` with a tool call, and one `}`
   turn (todo 2 item 12).
2. Remaining from 25/26: `&` mode plan (todo 5), tests (todo 1).
