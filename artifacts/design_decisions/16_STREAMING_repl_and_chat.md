# Decision: Streaming replies (REPL and `chat!`)

| Field | Value |
|-------|-------|
| Artifact | `16_STREAMING_repl_and_chat.md` |
| Category | design_decisions |
| Subject | `STREAMING` |
| Date | 2026-09-28 |
| Area/Purpose scope | public API, REPL surface, Preferences, provider layer |
| Related | `14_REPL_chat_mode.md`, `15_MESSAGES_server_side_chaining.md`, `../provider_reviews/3_STREAMING_text_deltas.md` |
| Status | accepted |
| Decided by | user (Preference, rendering, imperative API); agent (details below) |

## Context

User: "implement streaming to the repl when the provider supports it (and the user has set a
preference for streaming) otherwise the `thinking...` is fine". Redesign note #6.

## The Questions and Answers

| Question | Options | Chosen |
|---|---|---|
| Preference | `stream` default false; `stream` default true; `stream_replies` | **`stream = true`, default false** |
| REPL rendering | block-by-block Markdown (agent recommendation); raw only; raw then redraw as Markdown | **raw then redraw** |
| Imperative API | `on_text` callback kwarg (agent recommendation); `stream::Bool` printing to stdout; none | **`stream::Bool`** |

## Decision

```julia
chat!(s, prompt; stream = true)   # prints deltas to stdout, returns the full AssistantMessage
```

```toml
[JAIL]
stream = true    # the `}` mode streams (default false: `thinking…` until the reply is done)
```

Agent-decided:

- `chat!`'s `stream` kwarg defaults to `false` and ignores the Preference; the Preference only
  affects the `}` mode. A newline is printed after the stream if the text didn't end with one.
- Core hook: internal `_chat!(s, prompt; on_text)` / `_complete(...; on_text)`; streaming is used
  when `on_text` is given and `_supports_streaming(::Type{P})` (true for all four providers).
- REPL: `thinking…` stays until the first delta; raw text streams; afterwards the raw rows are
  erased (`\e[<n>A\r\e[J`, n from `textwidth` and the terminal width) and the Markdown rendering
  printed (see Amendment for replies taller than the screen). Non-TTY output is left raw.
- Errors mid-stream: the partial text stays on screen, a newline is printed, then the error;
  the history is unchanged (same as non-streaming).
- Provider errors inside the stream (`error` events) are raised after the stream ends.
- Chaining (decision 15) and the 400/404 retry work the same when streaming.

## Consequences

- Markdown redraw miscounts rows if the terminal wraps differently from `textwidth` (some
  emoji), leaving a stray line or erasing one line too many.
- Chat Completions streams have no usage (no `stream_options` sent).

## Amendment (2026-09-28, user report)

"When asking it to generate code - it streams everything but then doesn't show the final parsed
markdown." Cause: code replies were taller than the terminal, so the "leave raw" branch ran.
User chose (over: stream-only-while-it-fits with a progress line; print Markdown below the raw
text; keep raw with a note): **always redraw on a TTY**, moving up at most `rows - 1` lines, so
the screen ends with the rendered reply and raw lines that scrolled off stay in the scrollback.
Also fixed: tabs counted as width 0 in `_rows_above_cursor`; they now advance to the next
8-column stop.

## Amendment 2 (2026-09-28, user request) — supersedes the redraw above

"Is there a way to clear all the streaming output once the final output is ready so that the
displayed output is the only thing in the repl output". Scrolled-off lines can't be erased and
`\e[3J` would wipe the user's whole scrollback (not offered). User chose (over: hybrid, switch
only when the text would overflow) **always stream on the alternate screen**: at the first delta
`thinking…` is cleared and `\e[?1049h\e[H\e[2J` enters the alternate screen, which shows
`chat> <prompt>` then the raw text; at the end (or on error / Ctrl-C, in a `finally`)
`\e[?1049l` restores the REPL screen and only the Markdown rendering is printed.
`_rows_above_cursor` and the row-count redraw were removed. Non-TTY output still streams raw.
Consequence: the partial text of a failed stream is no longer visible afterwards.

## Revisit Trigger

Redraw glitches reported in real terminals, tool-call streaming (needs argument deltas), or a
request for a callback API (`on_text`) in addition to `stream::Bool`.
