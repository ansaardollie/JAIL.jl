# Streaming replies in the `}` mode and `chat!`

| Field | Value |
|-------|-------|
| Artifact | `9_STREAMING_repl_and_chat.md` |
| Category | work_history |
| Subject | `STREAMING` |
| Date | 2026-09-28 |
| Area/Purpose scope | provider layer, REPL surface, public API, Preferences |
| Related | `8_MESSAGES_server_side_chaining.md`, `design_decisions/16_STREAMING_repl_and_chat.md`, `provider_reviews/3_STREAMING_text_deltas.md` |

## Scope of This Unit of Work

User: stream to the REPL when the provider supports it and the user opted in, else keep
`thinking…`. Then two follow-ups: long (code) replies weren't redrawn as Markdown, and streaming
"stopped" (caused by the agent's test cleanup deleting the owner's `stream = true`).

## What Changed

| File | Change |
|-------|--------|
| `src/ontology/requests.jl` | `_Request.stream`; interface `_stream_state` / `_stream_event!` / `_stream_finish`; `_supports_streaming(::Type{P})` |
| `src/http.jl` | `_post_sse` via HTTP.jl 2.8 `sse_callback`; error statuses read as a normal body |
| `src/providers/openai.jl` | Responses stream: text/refusal deltas, terminal event's `response` reused by `_parse_reply` |
| `src/providers/openai_compatible.jl` | Chat Completions stream accumulator (`[DONE]`, no usage) |
| `src/providers/anthropic.jl` | Messages stream accumulator (message_start / text_delta / message_delta / error) |
| `src/providers/google.jl` | Interactions stream accumulator (step.start / step.delta text in model_output / interaction.completed / error) |
| `src/chat.jl` | `_send` streams when `req.stream`; `_complete(...; on_text)`; `chat!(...; stream::Bool)`; internal `_chat!(...; on_text)` |
| `src/repl/chat_mode.jl` | `_stream_pref`, `_render_stop`, `_rows_above_cursor` (tabs to 8-col stops), `_chat_send` streams raw then redraws as Markdown (clamped to screen height) |
| docs (`chat.md`, `repl.md`, `providers.md`, `index.md`, `make.jl`), `examples/chat.jl` | streaming sections, `stream` Preference |

## Decisions

`design_decisions/16_STREAMING_repl_and_chat.md`: Preference `stream` (default false); REPL
raw-then-redraw (rejected: block-by-block Markdown, raw only); `chat!(; stream::Bool)` printing
to stdout (rejected: `on_text` callback, no public API). Amendment: tall replies always redrawn
(rejected: stream-only-while-it-fits, Markdown below raw, keep raw with a note).

## Verification

Fresh REPL, mock server with each provider's documented events:

```
openai/gpt-5                stream=true  deltas=["Hel", "lo **there**"]
    → "Hello **there**"  end_turn  Usage(5 in, 3 out)  id=resp_s1
anthropic/claude-opus-5-5   stream=true  deltas=["Hello", "!"]
    → "Hello!"  end_turn  Usage(25 in, 15 out)  id=msg_s1
google/gemini-3.8-flash     stream=true  deltas=["1, 2, 3, ", "4, 5"]
    → "1, 2, 3, 4, 5"  end_turn  Usage(11 in, 90 out)  id=v1_s
stubc/qwen                  stream=true  deltas=["Hi", " you"]
    → "Hi you"  max_tokens  nothing  id=chatcmpl-s
--- REPL tty, fits:  "thinking…\r\e[2KHello **there**\r\e[J  Hello there\n"
--- not a tty:       "Hello **there**\n"
--- pref off, tty:   "thinking…\r\e[2K  non-streamed\n"
out: "partial\n"   err: ERROR: anthropic stream error: Overloaded
err: ERROR: openai API error (HTTP 429): Rate limit reached   (history lengths 0)
stamps = [1.18, 1.56, 1.96]     # server sending every 0.4 s → incremental
tall reply, 10-row screen: "\n\e[9A\r\e[J" then the full Markdown rendering
JAIL._rows_above_cursor("\t" ^ 11 * "x", 80) = 1
```

Load check before commit: `_stream_pref() = true`, `_supports_streaming(Google) = true`,
`hasmethod(chat!, Tuple{Session,String}, (:stream,)) = true`. Docs built with no warnings.
User-verified in their terminal: prose streams and is redrawn; code replies weren't redrawn
before the amendment (not re-verified after).

Incident: a test cleanup ran `JAIL._delete_pref!("stream")` and wiped the owner's
`stream = true`; restored with `JAIL._save_pref!("stream", true)`. Repo memory now requires
snapshot/restore of Preferences in tests.

## Known Limitations

- Redraw row count can be off with some emoji / unusual wrapping; tall replies leave the raw head
  in the scrollback.
- Chat Completions streams report no usage (`stream_options.include_usage` not sent).
- Reasoning / thought deltas are ignored.
- No live provider calls; real-terminal redraw only partly checked by the owner.

## Todos

- Completed: none
- Created: none (`2_REPL_real_terminal_check.md` item 7 added)

## Next Steps

1. Owner: re-check a long code reply in the `}` mode with `stream = true`.
2. `4_MESSAGES_replay_reasoning.md`.
3. `1_TESTS_test_suite_setup.md`: the SSE mock server and Preferences snapshot/restore belong in
   the test helpers.
4. Tools (redesign note #8).
