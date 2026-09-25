> **Partially superseded by:** `5_OAI_PROVIDER_responses_default.md` (flag shape: the Responses API is now the default, opt-in via `chat_completions`)

# Decision: Responses API as a flag on `OpenAICompatible`, with stateless multi-turn input

| Field | Value |
|-------|-------|
| Artifact | `4_OAI_PROVIDER_responses_api_multiturn.md` |
| Category | design_decisions |
| Subject | `OAI_PROVIDER` — OpenAI-compatible provider, `/v1/responses` support |
| Date | 2026-09-25 |
| Area/Purpose scope | providers, request format, conversation context |
| Related | `artifacts/design_decisions/3_API_naming_and_env_config.md`, `artifacts/work_history/8_OAI_PROVIDER_responses_api.md` |
| Status | accepted |
| Decided by | agent, from the user's requests ("support (with a feature flag) for the Responses API", "try working with multi turn conversations") and live gateway probes |

## Context

`OpenAICompatible` only spoke `/v1/chat/completions`. The user asked for `/v1/responses` support
behind a feature flag, then for real multi-turn conversations over it. Until now, conversation
context was only the text summary `AIBrain.memory`, placed in the system prompt.

## The Question

1. How is the Responses API turned on?
2. How is conversation state carried between turns?
3. Where does the system prompt go?

## Options Considered

### 1. Flag shape

- **A (chosen):** `OpenAICompatible.responses::Bool = false`, set by the `setapi(...; responses)`
  keyword, which falls back to `ENV["JAIL_RESPONSES_API"]` (`1`/`true`/`yes`). It can also be
  flipped while running with `Brain.model.responses = true`. One struct, so every
  `request_*`/`parse_answer` method branches on the flag.
- **B:** a separate `OpenAIResponses <: ModelProvider` type or a new provider name. Rejected: it
  duplicates URL, auth and model listing, and the user asked for a flag, not a provider.

### 2. Conversation state

- **A (chosen):** stateless. Resend the last `AIBrain.max_turns` (default 10) turns from
  `Brain.history` as `user`/`assistant` messages in `input`, with `store: false`. The `memory`
  summary is added to the system prompt only when older turns have been cut off.
- **B:** server-side state with `previous_response_id` and `store: true`. Rejected for now: the
  local gateway returns `404` on the follow-up request (probed live), and it would need the
  response id carried back out of `parse_answer`.
- **C:** keep only the text summary. Rejected: it loses exact wording and is refreshed
  asynchronously.

### 3. System prompt placement

- **A (chosen):** a leading `{"role":"system"}` message in `input`.
- **B:** the `instructions` field. Rejected: the gateway silently drops it for the
  `Discovery-large` backend. A probe returned "Unknown" with `instructions` and "PELICAN" with a
  system message, while `openai/qwen3-coder-30b` honoured both. Real OpenAI accepts system
  messages in `input`.

## Decision

1A, 2A, 3A.

## Consequences

- Works with any Responses-compatible server, whether or not it keeps state.
- Request size grows with `max_turns` × answer length. There is no token-based limit.
- Chat completions is unchanged and still gets only the summary. Resending history there would
  be a separate change.

## Revisit Trigger

Real OpenAI use where resending history is too costly (then consider `previous_response_id`),
context-window overflows, or a gateway that honours `instructions` but not system messages.
