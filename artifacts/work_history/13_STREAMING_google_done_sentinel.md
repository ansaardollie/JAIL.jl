# Fix Google streaming crash on the `[DONE]` SSE sentinel

| Field | Value |
|-------|-------|
| Artifact | `13_STREAMING_google_done_sentinel.md` |
| Category | work_history |
| Subject | `STREAMING` |
| Date | 2026-09-28 |
| Area/Purpose scope | provider (Google), bug fix |
| Related | `work_history/9_STREAMING_repl_and_chat.md` |

## Scope of This Unit of Work

User report: `chat!(prompt; stream=true)` on Google, and the `}` REPL chat mode, both threw
`ArgumentError: invalid JSON ... InvalidJSON` at the very end of an otherwise-successful stream
(the text had already printed correctly). Picked up right after `12_MODEL_per_provider_default.md`.

## What Changed

| File | Change |
|-------|--------|
| `src/providers/google.jl` | `_stream_event!` now returns early on `strip(data) == "[DONE]"` before calling `JSON.parse`, mirroring the existing guard in `src/providers/openai_compatible.jl`. Updated the doc comment above `_supports_streaming(::Type{Google})` to cite the sentinel event. |

## Design Decisions Made

None — this follows the exact precedent already established in `openai_compatible.jl`'s
`_stream_event!` for the Chat Completions fallback, no alternative considered.

## Verification

Root cause confirmed against `artifacts/provider_docs/google/gemini-docs/gemini-docs-070-streaming.md#L168-L169`:
the Interactions API streaming response always ends with a non-JSON terminal event

```
event: done
data: [DONE]
```

which `_stream_event!` was passing straight into `JSON.parse`.

In the REPL (Julia 1.13.0), after the fix, replaying a full mocked event sequence including the
sentinel raised no error and delivered the streamed text:

```julia
using JAIL
st = JAIL._GoogleStream(Dict(), Dict(), Dict(), nothing, nothing, nothing)
texts = String[]
JAIL._stream_event!(st, "{\"index\":0,\"step\":{\"type\":\"model_output\"},\"event_type\":\"step.start\"}", t -> push!(texts, t))
JAIL._stream_event!(st, "{\"index\":0,\"delta\":{\"type\":\"text\",\"text\":\"Hi there\"},\"event_type\":\"step.delta\"}", t -> push!(texts, t))
JAIL._stream_event!(st, "{\"index\":0,\"event_type\":\"step.stop\"}", t -> push!(texts, t))
JAIL._stream_event!(st, "{\"interaction\":{\"id\":\"abc\",\"status\":\"completed\",\"usage\":{\"total_input_tokens\":1,\"total_output_tokens\":2}},\"event_type\":\"interaction.completed\"}", t -> push!(texts, t))
JAIL._stream_event!(st, "[DONE]", t -> push!(texts, t))
# texts=["Hi there"]
# no error thrown
```

`using JAIL` still loads cleanly after the change.

## Known Limitations

- Not exercised against a live Google streaming call (no network call made this session); only
  the mocked-event replay above, plus reading the doc's exact SSE transcript.
- No automated test suite exists yet to pin this regression down (see
  `artifacts/todos/pending/1_TESTS_test_suite_setup.md`).

## Todos

- Completed: none
- Created: none

## Next Steps

- If/when `1_TESTS_test_suite_setup.md` is picked up, add a streaming test per provider that
  replays a captured SSE transcript (including each provider's terminal sentinel) through
  `_stream_event!`/`_stream_finish` without a network call.
