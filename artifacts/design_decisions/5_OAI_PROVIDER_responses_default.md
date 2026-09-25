# Decision: Responses API is the default; chat completions is the opt-in flag

| Field | Value |
|-------|-------|
| Artifact | `5_OAI_PROVIDER_responses_default.md` |
| Category | design_decisions |
| Subject | `OAI_PROVIDER` — which endpoint `OpenAICompatible` uses by default |
| Date | 2026-09-25 |
| Area/Purpose scope | providers, configuration |
| Related | partially supersedes `4_OAI_PROVIDER_responses_api_multiturn.md` (option 1, flag shape); `artifacts/work_history/9_OAI_PROVIDER_responses_default.md` |
| Status | accepted |
| Decided by | user: "make the response the default feature and allow the chat completion to be the toggleable one either through the feature flag or it should check whether an appropriate ENV var is set" |

## Context

Decision 4 added `OpenAICompatible.responses::Bool = false`, set by `setapi(...; responses)` and
`JAIL_RESPONSES_API`. The user wants the Responses API on by default for `openai` and
`openai-compatible`, with chat completions as the option you turn on.

## The Question

Which name should the flag have, and what happens to `JAIL_RESPONSES_API`?

## Options Considered

### Option A — rename the flag to `chat_completions::Bool = false` (chosen)

- Field, keyword and environment variable all say the same thing:
  `OpenAICompatible.chat_completions`, `setapi(...; chat_completions)` and
  `JAIL_CHAT_COMPLETIONS` (`1`/`true`/`yes`). The keyword beats the environment variable when
  both are set.
- `false` stays the "off" value, matching the other `AIBrain` boolean settings.

### Option B — keep `responses`, change its default to `true`

- Rejected: switching to chat completions would then mean setting the flag to `false`, and there
  is no natural environment-variable spelling for "responses off".

### Option C — a string setting such as `JAIL_OPENAI_API = "responses" | "chat"`

- Rejected: it needs value validation for only two choices, and the user asked for a
  toggle-style flag.

## Decision

Option A. `JAIL_RESPONSES_API` and the `responses` keyword are removed with no deprecation
alias. They existed in exactly one unreleased commit (`15ff71d`).

## Consequences

- Local servers without `/v1/responses` (for example Ollama's OpenAI-compatible endpoint,
  llama.cpp, older vLLM) now need `JAIL_CHAT_COMPLETIONS=true`. There is no automatic fallback.
- Decision 4's other choices still hold: stateless history in `input`, a system message instead
  of `instructions`, and `store: false`.

## Revisit Trigger

Frequent failures on local servers that don't support `/v1/responses`. In that case, consider
falling back automatically to chat completions when `/v1/responses` returns 404.
