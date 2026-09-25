# Responses API support and multi-turn conversations for `OpenAICompatible`

| Field | Value |
|-------|-------|
| Artifact | `8_OAI_PROVIDER_responses_api.md` |
| Category | work_history |
| Subject | `OAI_PROVIDER` — `/v1/responses` support in the OpenAI-compatible provider |
| Date | 2026-09-25 |
| Area/Purpose scope | providers, core, configuration, docs |
| Related | `artifacts/design_decisions/4_OAI_PROVIDER_responses_api_multiturn.md`, `artifacts/work_history/7_API_naming_config_refactor.md`, `artifacts/work_history/5_OAI_PROVIDER_local_support.md` |

## Scope of This Unit of Work

This session asked for new work rather than following the "Next Steps" of artifact 7 (tests,
deprecated paths, real OpenAI, docs build), all of which are still open. The work:

1. OpenAI Responses API (`/v1/responses`) support behind a feature flag.
2. Multi-turn conversations over it.
3. A multi-turn eval, run and analysed (code is in the verification section below; it was not
   added to the repo).

## What Changed

| File | Change |
|------|--------|
| `src/models.jl` | `OpenAICompatible` gains `responses::Bool = false`. With the flag on, `request_url` returns `$(base)/v1/responses`. `request_body` builds `input` as a leading `system` message (from `_system_prompt`), then the last `b.max_turns` user/assistant pairs from `b.history`, then the question, with `stream` and `store: false`. `parse_answer` uses the new `_responses_answer`: without streaming it joins `output[type=message].content[type=output_text].text`, falling back to a top-level `output_text`; with streaming it takes only `data:` lines whose `type == "response.output_text.delta"` and returns `delta`, so other events yield `""`. `_system_prompt(b; memory = true)` gains a keyword so the memory summary can be left out when every turn is resent. |
| `src/brain.jl` | `AIBrain.max_turns::Int = 10`. |
| `src/JAIL.jl` | `setapi(provider, model; url, api, responses = nothing)`. `nothing` falls back to `ENV["JAIL_RESPONSES_API"]` in (`1`, `true`, `yes`), otherwise `false`. Docstring and `CONFIG_HELP` updated. |
| `readme.md` | Added a row for `JAIL_RESPONSES_API`. |

The request loop (`_complete`, `_ask_stream`, `_remember!`) is unchanged. The Responses API
streams SSE `data:` lines just like chat completions.

## Design Decisions Made

See `artifacts/design_decisions/4_OAI_PROVIDER_responses_api_multiturn.md`. Rejected:

- a separate provider type;
- `previous_response_id` (the gateway returns 404);
- the `instructions` field (dropped by the gateway for `Discovery-large`).

## Verification

All runs used the local gateway through `run-julia-code`.

Single turn (first iteration, model `openai/qwen3-coder-30b`):

```text
JAIL.OpenAICompatible responses=true url=https://llmgarden.../v1/responses models: 90
responses ok                              # without streaming
¬ 1 2 3 4 5                               # streaming; history last="1 2 3 4 5"
memory summarization path (non-stream _complete): "Sum ok"
flag off -> .../v1/chat/completions
¬ chat ok
```

Gateway probes that drove the design:

```text
previous_response_id -> http status error: 404 for POST https://llmgarden...:443/v1/responses
input array -> PELICAN
Discovery-large | instructions: "Unknown" | system msg: "PELICAN" | developer msg: "PELICAN"
openai/qwen3-coder-30b | instructions: "PELICAN" | system msg: "PELICAN" | developer msg: "PELICAN"
```

Falling back to the summary with `max_turns = 1`, after the switch to a system message:

```text
roles: ["system", "user", "assistant", "user"]
max_turns=1, recalled from summary: "PELICAN\n"
```

Multi-turn eval. It ran in a fresh REPL with model `Discovery-large` from the environment,
`B.prompt = "Answer concisely..."`, `terminal_hint = false` and `render_final = false`. The
script is an 8-turn trip budget: 1200 budget, companion Ana, hotel 150 × 4 nights, then checks
of 600, 160, Ana, 80, and 310 after one hotel night is made free. Runs: history without
streaming (`max_turns = 10`), history with streaming, and a control with `max_turns = 0` where
`B.memory = ""` is cleared before each question:

```text
== history, non-stream ==
  turn 4  PASS  "600"
  turn 5  PASS  "160"
  turn 6  PASS  "Ana"
  turn 7  PASS  "80"
  turn 8  PASS  "310"
== history, stream ==   (same five PASS answers, streamed)
== no history (control) ==
  turn 4  FAIL  "What is your total budget and how much did you spend on the hotel?"
  turn 5  FAIL  "60"
  turn 6  FAIL  "I’m sorry, I don’t know your travel companion’s name."
  turn 7  FAIL  "Could you please tell me the total amount of the remaining budget?"
  turn 8  FAIL  "0"
== summary ==
history, non-stream     5 / 5
history, stream         5 / 5
no history (control)    0 / 5
multi-turn eval passed
```

`get_errors` on `src/`: no errors.

Not verified:

- real OpenAI key auth with `responses = true`;
- `response.failed` / `error` stream events;
- `check_memory!` summarization past 3000 characters combined with `max_turns`;
- the eval with `max_turns < turns` (summary fallback inside the eval);
- repeated eval samples (it was run once, temperature not pinned);
- Gemini and Ollama (not touched).

## Known Limitations

- `response.failed` / `error` events and message-less replies without streaming produce an
  empty answer, not an error.
- History is limited by turn count, not tokens, so long answers can overflow a small context
  window.
- `check_memory!` is asynchronous, so the summary may lag the turns that were just cut off.
- Chat completions still sends only the summary, not message history.
- `max_turns` is a new struct field, so a running REPL needs a restart (Revise can't apply it).

## Todos

- Completed: none (no `artifacts/todos/` folder exists).
- Created: none.

## Next Steps

1. Raise an error on `response.failed` / `error` stream events and on non-stream replies with
   `status != "completed"` (in `_responses_answer`).
2. Optionally resend history as messages for the chat-completions path too (`request_body` for
   `OpenAICompatible`, non-`responses` branch).
3. Add the multi-turn eval as a `test/` script, gated on `JAIL_*` env vars, alongside artifact
   7's planned unit tests for `_responses_answer` on sample SSE lines.
4. Verify `setapi("openai", "gpt-5-mini"; responses = true)` with `OPENAI_API_KEY`, and consider
   `previous_response_id` when talking to real OpenAI.
5. Carried over from artifact 7: deprecated config paths, docs build.
