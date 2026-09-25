# OpenAI-compatible provider authentication and protocol hardening

| Field | Value |
|-------|-------|
| Artifact | `10_OAI_PROVIDER_auth_and_protocol_hardening.md` |
| Category | work_history |
| Subject | `OAI_PROVIDER` — OpenAI-compatible request behavior and credential configuration |
| Date | 2026-09-25 |
| Area/Purpose scope | providers, configuration, documentation |
| Related | `artifacts/work_history/9_OAI_PROVIDER_responses_default.md`, `artifacts/design_decisions/3_API_naming_and_env_config.md`, `artifacts/design_decisions/5_OAI_PROVIDER_responses_default.md` |

## Scope of This Unit of Work

The OpenAI-compatible provider existed after artifact 9, but its chat-completions mode did not
send prior turns, and API errors could silently appear as blank output. A subsequent
`available_models()` request returned HTTP 401 because the active environment supplied
`OPENAPI_API_KEY`, while `setapi` only read `JAIL_API_KEY` and `OPENAI_API_KEY`.

## What Changed

| File | Change |
|------|--------|
| `src/models.jl` | `request_body(::OpenAICompatible, ...)` now sends a bounded recent conversation for chat completions, matching the Responses API path. Old turns are represented by `Brain.memory`; recent turns are emitted as alternating `user` and `assistant` messages. `parse_answer` and `_responses_answer` now call `_throw_api_error`, surfacing standard OpenAI error payloads and `response.failed` SSE events. |
| `src/JAIL.jl` | `setapi` resolves credentials for both `openai` and `openai-compatible` in this order: explicit `api`, `JAIL_API_KEY`, `OPENAI_API_KEY`, then `OPENAPI_API_KEY`. `CONFIG_HELP` and the `setapi` docstring explain the fallback. |
| `readme.md` | Documents the same OpenAI API-key environment-variable precedence. |

## Design Decisions Made

- Treat `OPENAPI_API_KEY` as a compatibility alias after the standard `OPENAI_API_KEY`, not as a
  replacement. This fixes the supplied environment without changing the documented primary
  configuration surface. Rejected: requiring users to rename the existing environment variable
  before model discovery works, and preferring the nonstandard alias over `OPENAI_API_KEY`.
- Keep chat-completions history bounded by `AIBrain.max_turns`, identical to the existing
  Responses API semantics. Rejected: sending unbounded history, which can exhaust provider
  context windows, and leaving chat-completions stateless.

## Verification

Package loading:

```julia
using JAIL
println("JAIL_loaded=", isdefined(Main, :JAIL))
```

```text
JAIL_loaded=true
```

The chat-completions request fixture confirmed the recent-turn window and summarized older
context:

```text
roles=system,user,assistant,user,assistant,user
contents=system prompt

Conversation so far:
summary|q2|a2|q3|a3|q4
chat_history_fixture=ok
```

OpenAI and Responses response fixtures passed for non-streaming, SSE streaming, and API errors:

```text
OpenAI-compatible API error: chat failed
OpenAI-compatible API error: responses failed
openai_parse_fixtures=ok
```

A local HTTP fixture exercised the actual `available_models`, `@ai` non-streaming, and SSE paths:

```text
available_models=["fixture-model"]
nonstream_history="responses once ok"
¬ responses stream ok
stream_history="responses stream ok"
```

The live OpenAI credential fallback and model listing succeeded:

```julia
JAIL.setapi("openai", "gpt-5-nano")
models = JAIL.available_models(pretty=false)
```

```text
api_present=true
authorization_present=true
model_url=https://api.openai.com/v1/models
model_count=132
first_models=gpt-4o-transcribe, gpt-5.5-pro-2026-04-23, gpt-5.4, chatgpt-image-latest, o1-2024-12-17
```

`openai-compatible` also emitted an `Authorization` header when configured from
`OPENAPI_API_KEY`. `get_errors` found no source diagnostics, and `git diff --check` passed.

## Known Limitations

- The previously configured external local gateway could not be rechecked: its proxy failed with
  `proxy CONNECT failed with status 503` before JAIL reached the gateway.
- Real OpenAI chat/responses generation was not invoked; only authenticated model discovery was
  exercised against the real service.
- Local servers that do not implement `/v1/responses` still require
  `JAIL_CHAT_COMPLETIONS=true`; there is no automatic 404 fallback.

## Todos

- Completed: none.
- Created: none.

## Next Steps

1. Add a focused automated test suite for provider JSON bodies, SSE error events, and credential
   precedence, using a local HTTP fixture.
2. Re-run real OpenAI non-streaming and streaming generation with a permitted model to verify
   Responses API behavior end to end.
3. Consider automatic fallback to chat completions when a local endpoint returns 404 for
   `/v1/responses`.