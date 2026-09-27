# Stream `}` replies on the alternate screen

| Field | Value |
|-------|-------|
| Artifact | `10_STREAMING_alternate_screen.md` |
| Category | work_history |
| Subject | `STREAMING` |
| Date | 2026-09-28 |
| Area/Purpose scope | REPL surface |
| Related | `9_STREAMING_repl_and_chat.md`, `design_decisions/16_STREAMING_repl_and_chat.md` (Amendment 2) |

## Scope of This Unit of Work

User, after the streaming commit: "Is there a way to clear all the streaming output once the
final output is ready so that the displayed output is the only thing in the repl output". Tall
replies left their raw head in the scrollback because scrolled-off rows can't be erased.

## What Changed

| File | Change |
|-------|--------|
| `src/repl/chat_mode.jl` | `_ALT_SCREEN_ON` / `_ALT_SCREEN_OFF`; `_chat_send` enters the alternate screen at the first delta (shows `chat> <prompt>` then raw text) and leaves it in a `finally`, then prints only the Markdown rendering; removed `_rows_above_cursor` and the `screen` kwarg |
| `docs/src/guide/repl.md`, `examples/chat.jl` | streaming description |
| `artifacts/design_decisions/16_STREAMING_repl_and_chat.md` | Amendment 2 |
| `artifacts/todos/pending/2_REPL_real_terminal_check.md` | item 7 rewritten for the alternate screen |

## Decisions

Amendment 2 of `design_decisions/16_STREAMING_repl_and_chat.md`: always stream on the alternate
screen (rejected: hybrid switch only on overflow; clearing scrollback with `\e[3J`, not offered
since it wipes the user's history).

## Verification

Fresh REPL, mock SSE server; `stream` Preference snapshotted and restored:

```
tty stream:
"thinking…\r\e[2K\e[?1049h\e[H\e[2Jchat> append?\n\nUse `push!`:\n\n```julia\npush!(v, 3)\n```\e[?1049l  Use push!:\n\n  push!(v, 3)\n"
non-tty stream:
"Use `push!`:\n\n```julia\npush!(v, 3)\n```\n"
error: openai stream error: boom
tty stream error:
"thinking…\r\e[2K\e[?1049h\e[H\e[2Jchat> append?\n\npartial \e[?1049l"
length(s.messages) = 4
pref off:
"thinking…\r\e[2K  Use push!:\n\n  push!(v, 3)\n"
JAIL._load_pref("stream") = true
```

Load check: `JAIL._ALT_SCREEN_ON = "\e[?1049h\e[H\e[2J"`, `_stream_pref() = true`,
`isdefined(JAIL, :_rows_above_cursor) = false`. Docs built with no warnings. User: "Okay
perfect." (behaviour in their terminal confirmed by the owner, not seen by the agent).

## Known Limitations

- The view flips to the alternate screen for every streamed reply, even short ones.
- Partial text of a failed or interrupted stream is not visible afterwards.
- Terminals without alternate-screen support would show the raw text followed by the rendering.

## Todos

- Completed: none
- Created: none

## Next Steps

1. `4_MESSAGES_replay_reasoning.md`.
2. `1_TESTS_test_suite_setup.md` (SSE mock server + Preferences snapshot/restore helpers).
3. Tools (redesign note #8) and the `&` agentic mode.
