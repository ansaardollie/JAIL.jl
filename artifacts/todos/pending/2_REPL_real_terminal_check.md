# TODO: Verify `|` mode and menus in a real terminal, plus live listing

| Field | Value |
|-------|-------|
| Artifact | `2_REPL_real_terminal_check.md` |
| Category | todos |
| Subject | `REPL` |
| Date created | 2026-09-27 |
| Area/Purpose scope | REPL surface, providers |
| Related | `work_history/2_REPL_model_selection_mode.md`, `work_history/4_SESSION_registry_and_default_session.md` |
| Priority | normal |
| Owner | any (needs the owner at a keyboard) |

## What

In a plain terminal `julia` (not the agent's tool REPL):

1. `using JAIL`, press `|` at an empty prompt, and check that the prompt shows `(default: <model>) model> `.
2. Run `sessions`, `session new x`, `session use default`, `use …`, `default …`, and `select`
   (arrow keys, Enter, `q`), then use Tab completion and exit with backspace.
3. `select_model!()` and `select_model!(Anthropic())` from `julia>`.
4. With the owner's approval, set `LIVE = true` in `examples/providers_and_models.jl` and run it.
5. `}` chat mode (see `design_decisions/14_REPL_chat_mode.md`): prompt shows
   `chat> `; a question renders as Markdown; the dim `thinking…` line is
   erased; Ctrl-C mid-request prints "Interrupted…" and leaves `length(active_session().messages)`
   unchanged; `/clear`, `/help`, Tab on `/`; Ctrl+J / Alt+Enter / Shift+Enter (with the VS Code
   keybinding from `docs/src/guide/repl.md`) insert a new line and Enter sends it all.
7. With `stream = true` (see `design_decisions/16_STREAMING_repl_and_chat.md`): the reply
   streams on the alternate screen under the prompt, then the normal screen returns with only
   the Markdown rendering (nothing raw in the scrollback, including for replies taller than the
   screen); Ctrl-C mid-stream returns to the normal screen.
6. Julia 1.13 bracket auto-close still works in `julia>` with `}` bound to the chat mode: type
   `Dict{` then `}` and check no doubled `}` (ReplMaker keeps the original binding for
   non-empty lines; not verified).
8. Tools (see `design_decisions/18_TOOLS_session_tools_and_call_loop.md`): in `|`, `tools`,
   `tools show/use/add/drop/all/none` and Tab completion; in `}` with a registered tool, the
   `→`/`←` lines appear (streamed and not); with `confirm_tools = true` the `[y/N]` prompt reads
   input correctly inside the chat mode.
9. Tool display (see `design_decisions/27_TOOLS_call_records_and_display.md`, amendment): the
   finished turn shows `Tool calls (n):`, then `Output:`; `View` alone is underlined and opens the
   JSON file (OSC 8) in VS Code's terminal and iTerm2; without streaming the `→ label…` line is
   erased; with `confirm_tools = true` and no streaming the prompt is not overwritten;
   `tools use group:<g>` and its Tab completion.
10. Tool approval (see `design_decisions/29_TOOLS_security_approval_preview.md`,
    `30_TOOLS_auto_approvals.md`): run `examples/tool_security.jl` in a terminal REPL with each
    `MODE`; prompts read `y`/`n`/`a` correctly in `}` (streamed and not); a streamed preview is
    not repeated in the prompt; `a` writes `[JAIL.tool_auto_approvals]`; `tools approve` /
    `unapprove` and the `[auto-approved]` / `[always asks]` marks.
11. Built-in tools (see `work_history/25_TOOLS_builtin_tools.md`): run `examples/builtin_tools.jl`
    and, with the owner's approval (live calls), `examples/builtin_tools_prompts.jl`; `ask_user`
    with options shows the arrow-key menu; in `}` the status line is cleared before `ask_user`
    asks; `execute_julia_code` / `run_shell` prompts read `y`/`n`/`a`.
12. `chat!(s, "..."; stream = true)` at the prompt (see `design_decisions/33_STREAMING_chat_uses_chat_mode_display.md`):
    streams on the alternate screen, then only the `Tool calls` block, then the REPL's
    `AssistantMessage (...)` display with the text once; a `}` turn still looks as before.

## Why

The agent could only drive menus with a fake terminal, and has never made a live provider call.
The Google `generateContent` filter and the model-list shapes are unconfirmed against real APIs.

## Acceptance Criteria

- [ ] All commands behave as in `work_history/4_SESSION_registry_and_default_session.md`
- [ ] Menus render, scroll (pagesize 15) and cancel cleanly
- [ ] `list_models` returns non-empty lists for OpenAI, Anthropic and Google

## Notes

API keys are already set in the owner's ENV (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`).
