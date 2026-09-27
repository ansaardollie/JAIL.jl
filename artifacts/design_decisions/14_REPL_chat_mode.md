# Decision: The `}` chat REPL mode

| Field | Value |
|-------|-------|
| Artifact | `14_REPL_chat_mode.md` |
| Category | design_decisions |
| Subject | `REPL` |
| Date | 2026-09-27 |
| Area/Purpose scope | REPL surface, dependencies |
| Related | `8_REPL_model_mode.md`, `12_MESSAGES_types_and_chat.md`, `13_SESSION_default_system_prompt.md` |
| Status | accepted |
| Decided by | user (key/prompt, rendering + Markdown dep, footer, commands, waiting indicator); agent (details below) |

## Context

User: "implement the `chat` AI repl mode". Design principle 10 reserves `}` for asking (text)
and `&` for agentic; both must call the same core as the imperative API (`chat!`).

## The Questions and Answers

| Question | Options | Chosen |
|---|---|---|
| Key and prompt | `}` + `(s: model) chat> `; `}` + `ask> ` | **`}`, `chat> `** |
| Rendering | Markdown stdlib (new `[deps]` entry); raw text | **Markdown** |
| Footer | only if stop_reason ≠ `:end_turn`; always model + tokens; never | **only when not `:end_turn`** |
| In-mode commands | none; `/clear`, `/help` | **`/clear`, `/help`** |
| Waiting indicator | transient `thinking…`; nothing | **`thinking…`** |

## Decision

```text
chat> How do I append?            # was `(default: anthropic/claude-opus-5-5) chat> `, see Amendment
  <reply rendered with Markdown>
[stop reason: max_tokens]          # yellow, only when not :end_turn
chat> /clear
Cleared 4 messages from session "default"
```

- Each non-empty line → `chat!(active_session(), line)`; `/clear` → `empty!(active_session())`.
- `Pkg.add("Markdown")`; replies shown with `show(io, MIME"text/plain"(), Markdown.parse(text))`.

Agent-decided:

- Prompt color `:cyan`; mode name `jail_chat`; installed alongside `|` by `_install_repl_modes`,
  covered by the existing `repl_modes = false` opt-out.
- `thinking…` only when `stdout isa Base.TTY`, erased with `\r\e[2K` in a `finally`.
- Ctrl-C prints "Interrupted; nothing was added to the history." (no stack trace); other
  errors via `_print_error` like the model mode. A missing model gets a hint pointing at `|`.
- Empty reply text prints dim `(empty reply)`.
- Tab completes `/` commands only.
- ReplMaker warns "REPL key '}' overwritten" because Julia 1.13 binds `}` for bracket
  auto-close; ReplMaker keeps that binding for non-empty lines, so the warning is suppressed
  with a `NullLogger` around that one `initrepl` call.
- The reply is printed, not returned, so it doesn't land in `ans`.

## Consequences

- A prompt that genuinely starts with `/` can't be sent from the mode (use `chat!`).
- `Markdown = "1.11.0"` compat has the same julia-1.10 problem as REPL (todo 3).

## Amendment (2026-09-27, user feedback after first use)

1. "Multiline prompts do not work. As soon I press enter the prompt submits … (maybe a
   SHIFT+ENTER)". Terminals send the same `\r` for Enter and Shift+Enter unless they implement
   an extended key protocol, so agent-decided: in the chat mode only, a new line is inserted by
   Ctrl+J (`\n`, every terminal), Alt+Enter (`\e\r`, already in LineEdit's default keymap), and
   Shift+Enter as CSI u `\e[13;2u` or xterm modifyOtherKeys `\e[27;2;13~`. Enabling the kitty
   keyboard protocol was rejected (it changes every key's encoding for the whole REPL). The
   VS Code terminal needs a user keybinding (`sendSequence` `"\u001b\r"` on `shift+enter`),
   documented in `docs/src/guide/repl.md`; JAIL does not edit user settings. Bracketed paste
   already inserts multi-line text without sending. Code: `_NEWLINE_KEYS`, `_add_newline_keys!`
   in `src/repl/chat_mode.jl`, applied to the mode returned by `initrepl`.
   Follow-up: user reported Shift+Enter still failing in VS Code (Alt+Enter works) and asked for
   Ctrl/Cmd+Enter too. Cause: VS Code sends `\r` for all of them, and the owner's
   `keybindings.json` binds `shift+enter` (Julia extension, no `when`) and `cmd+enter`
   (`terminal.runSelectedText`). Added CSI u / modifyOtherKeys forms of Ctrl+Enter
   (`\e[13;5u`, `\e[27;5;13~`) and Cmd/Super+Enter (`\e[13;9u`). Owner declined an agent edit of
   `keybindings.json`; the three `sendSequence` entries are documented instead.
2. "in the chat mode [session/model info] is unnecessary. Let's remove it". The chat prompt is
   now the constant `chat> `. This overrides redesign note #11 ("REPL modes should indicate what
   model they're using") for the chat mode by the owner's explicit instruction; the `|` prompt
   still shows it.

## Revisit Trigger

Streaming (the renderer must work incrementally), users wanting the reply in `ans`, or more
slash commands accumulating (consider sharing the `|` command set).
