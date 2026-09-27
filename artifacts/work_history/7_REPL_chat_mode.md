# Built-in system instructions and the `}` chat REPL mode

| Field | Value |
|-------|-------|
| Artifact | `7_REPL_chat_mode.md` |
| Category | work_history |
| Subject | `REPL` |
| Date | 2026-09-28 |
| Area/Purpose scope | REPL surface, public API, Preferences, dependencies |
| Related | `6_MESSAGES_text_chat.md`, `design_decisions/13_SESSION_default_system_prompt.md`, `design_decisions/14_REPL_chat_mode.md` |

## Scope of This Unit of Work

Since `6_MESSAGES_text_chat.md` (whose next steps listed the `}` mode): default system
instructions for REPL use, then the `}` chat mode, then two rounds of user feedback on it
(multi-line input, prompt length, Shift/Ctrl/Cmd+Enter in VS Code).

## What Changed

| File | Change |
|-------|--------|
| `src/system_prompt.jl` | new: `_REPL_INSTRUCTIONS`, `_environment_line` (Julia version, OS/arch, `~`-shortened active project, packages bound in `Main`), `_main_packages`, `_default_system` (Preference `system_prompt` override, `""` = none) |
| `src/session.jl` | `Session(...; system = nothing)` and the startup session use `_default_system()`; `system = ""` → none; display shows `_system_preview` (first line, length) |
| `src/repl/chat_mode.jl` | new: `_CHAT_HELP`, `_CHAT_PROMPT = "chat> "`, `_NEWLINE_KEYS`, `_add_newline_keys!`, `_chat_slash` (`/clear`, `/help`), `_render_reply` (Markdown + stop-reason line), `_chat_send` (`thinking…` on TTY), `_chat_command`, `_complete_chat_mode`; `_session_label` shared with the model mode |
| `src/repl/install.jl` | installs `}` mode (`jail_chat`, cyan) after `|`, with ReplMaker's "'}' overwritten" warning silenced; adds newline keys to the returned mode |
| `src/repl/model_mode.jl` | `_model_prompt` uses `_session_label` |
| `src/JAIL.jl`, `Project.toml` | `using Markdown`; `Pkg.add("Markdown")` (compat `1.11.0` written by Pkg) |
| `docs/src/guide/{repl,sessions,providers,concepts}.md`, `docs/src/index.md`, `docs/make.jl` | REPL modes page (chat mode, multi-line keys, VS Code keybindings), system instructions section, `system_prompt` key |
| `examples/sessions.jl`, `examples/chat.jl` | system instructions section; `}` mode transcript |
| `artifacts/todos/pending/2_…`, `3_…` | chat-mode real-terminal checks; Markdown compat note |

## Decisions

- `13_SESSION_default_system_prompt.md`: every session created without `system`; Preference
  `system_prompt`; all four environment details; captured at creation (agent had recommended
  per-request rendering, rejected by the user).
- `14_REPL_chat_mode.md`: `}` key, Markdown rendering (new stdlib dep), stop-reason line only
  when not `:end_turn`, `/clear` + `/help`, `thinking…`. Amendment: prompt shortened to
  `chat> ` at the user's request (overrides note #11 for this mode); new-line keys Ctrl+J,
  Alt+Enter, Shift/Ctrl/Cmd+Enter as CSI u / modifyOtherKeys. Rejected: enabling the kitty
  keyboard protocol (changes all key encodings REPL-wide); the agent editing the owner's VS Code
  `keybindings.json` (owner declined).

## Verification

Fresh REPL, mock Anthropic server:

```
JAIL._chat_prompt() = "(stub: anthropic/claude-opus-5-5) chat> "     # before the prompt change
out:   Use push!:

  v = [1, 2]
  push!(v, 3)

    •  fast
  Once upon
[stop reason: max_tokens]
(empty reply)
[stop reason: max_tokens]
Cleared 8 messages from session "stub"
stderr: ERROR: unknown command `/nope`; type `/help`
ERROR: session "nomodel" has no model; choose one in the `|` mode with `use provider/model` or `select`
JAIL._complete_chat_mode("/") = (["/clear", "/help"], "/")
```

Key handling, driven through the chat mode's real keymap (`LineEdit.match_input`):

```
"\e\r"          ("a\nb", :done)
"\n"            ("a\nb", :done)
"\e[13;2u"      ("a\nb", :done)
"\e[13;5u"      ("a\nb", :done)
"\e[13;9u"      ("a\nb", :done)
"\e[27;2;13~"   ("a\nb", :done)
"\e[27;5;13~"   ("a\nb", :done)
Enter           ("ab", :done)
```

System instructions (fresh REPL):

```
system:   "You are an assistant inside an interactive Julia REPL sessi…" (619 chars)
Environment: Julia 1.13.0 on Darwin aarch64, active project ~/Workspaces/Julia/JAIL.jl/Project.toml, loaded packages: …
system_prompt = 3 → ERROR: ArgumentError: Preference `system_prompt` must be a string, got 3
```

Final load check: `JAIL._REPL_INSTALLED[] = true`, prompts
`["(default: openai/gpt-6-luna) model> ", "chat> "]`, no "'}' overwritten" warning. Both
examples ran; `docs/make.jl` built with no warnings.

User-verified in their terminal: the chat mode works; Alt+Enter inserts a new line;
Shift/Cmd/Ctrl+Enter still submitted in VS Code (diagnosed: VS Code sends `\r` for them, and the
owner's keybindings had not yet added the `sendSequence` entries). Not verified afterwards.

## Known Limitations

- In the VS Code terminal Shift/Ctrl/Cmd+Enter only work with the user-side `sendSequence`
  keybindings documented in `docs/src/guide/repl.md`.
- Environment line is captured at session creation; the `"default"` session lists only packages
  loaded before JAIL. Project path is sent to providers.
- Docs `@example` output embeds the builder's environment line (path, dev packages).
- A prompt starting with `/` can't be sent from the mode; replies don't land in `ans`.
- `Markdown = "1.11.0"` compat blocks Julia 1.10 (todo 3).
- Bracket auto-close with `}` in `julia>` not checked in a real terminal (todo 2).

## Todos

- Completed: none
- Created: none (items added to `2_REPL_real_terminal_check.md` and `3_DEPS_repl_compat_bound.md`)

## Next Steps

1. `4_MESSAGES_replay_reasoning.md` (Google thought steps MUST be replayed).
2. Streaming into the chat mode (renderer must work incrementally).
3. `1_TESTS_test_suite_setup.md`, reusing the stub-server and keymap-driving snippets above.
