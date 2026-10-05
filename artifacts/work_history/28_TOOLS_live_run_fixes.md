# Markdown reply display, raw `fetch_url` content, stale-input guard for prompts

| Field | Value |
|-------|-------|
| Artifact | `28_TOOLS_live_run_fixes.md` |
| Category | work_history |
| Subject | `TOOLS` |
| Date | 2026-10-05 |
| Area/Purpose scope | public behavior, tools, dependencies, docs |
| Related | `design_decisions/32_TOOLS_builtin_tools_groups_and_rules.md` (amendment 2), `design_decisions/33_STREAMING_chat_uses_chat_mode_display.md` (amendment), `work_history/27_STREAMING_chat_display_once.md` |

## Scope of This Unit of Work

Follows `27_STREAMING_chat_display_once.md` (commit `b9305e6`). After running every tool in
`examples/builtin_tools_prompts.jl` live, the owner asked:

1. "the final output from the AssistantMessage should also be a markdown display"
2. `fetch_url` "should be the actual html content. Without the additional `Untrusted content from ..`"
3. `ask_user` choices "immediately selected" in `chat!` — owner found the cause on their side
  (an editor selection sent the `chat!` line plus the next line); asked to fix "the issue that
  newlines are read immediately".

## What Changed

| File | Change |
|-------|--------|
| `src/ontology/messages.jl` | `show(::IO, ::MIME"text/plain", ::AssistantMessage)` renders the text with `Markdown.parse` (blank text: header only) |
| `src/builtin_tools/web.jl` | Gumbo HTML → text walker and the "Untrusted content" prefix removed; `fetch_url` returns the body as served; docstring |
| `Project.toml`, `Manifest.toml` | `Pkg.rm("Gumbo")` |
| `src/tools.jl` | `_discard_pending_input(io)`: on a `Base.TTY`, `start_reading`, 20 ms, drop `bytesavailable` bytes; called in `_confirm` before `readline` |
| `src/builtin_tools/repl.jl` | `ask_user` calls `_discard_pending_input(stdin)` before asking |
| `docs/src/guide/tools.md`, `docs/src/guide/chat.md` | `fetch_url` row and Web pages section; Markdown display note |
| `examples/builtin_tools_prompts.jl` | owner's addition (a multiple-choice `ask_user` prompt) |

## Decisions

- Decision 32 amendment 2: raw `fetch_url` content, no prefix; Gumbo dependency removed
  (supersedes the G7 Gumbo pick). Rejected: keeping the HTML → text conversion.
- Decision 33 amendment: `AssistantMessage` text/plain display renders Markdown everywhere.
- Agent-decided (internal): discard pending terminal input before confirmation and `ask_user`
  prompts; a line sent by mistake is dropped, not run later.

## Verification

```
"<html><head><title>D</title></head><body><h2>Hi</h2></body></html>"     # fetch_url via a 302, local server
http://127.0.0.1:62017/bin is not text (Content-Type: image/png)
AssistantMessage
  Here is bold and a list:

    •  one
    •  two

  x = 1
ask_user => b                      # piped stdin "2" (non-TTY: nothing discarded)
```

On a pty (`script -q /dev/null julia --project -e ...`), `stale line` sent before the prompt and
`y` after: `answer: y` / `"y"` — the stale line was discarded. Docs build: exit 0, no warnings.
Load check: `isdefined(JAIL, :_discard_pending_input) = true`, `length(builtin_tools()) = 25`,
`Base.find_package("Gumbo") = nothing`.

**Not verified:** the owner's VS Code Shift+Enter scenario with the menu itself.

## Known Limitations

- `_discard_pending_input` waits 20 ms per prompt and drops everything typed ahead.
- Markdown rendering of `AssistantMessage` indents text (REPL Markdown style); `repr`/`print`
  are unchanged.
- Not committed: `scratch/` and `test/runtests.jl` (created while running the prompts example).

## Todos

- Completed: none
- Created: none
- Updated: none

## Next Steps

1. Owner: delete or keep `scratch/` and `test/` (left untracked).
2. `&` mode plan (todo 5), tests (todo 1), terminal checks (todo 2 items 11–12).
