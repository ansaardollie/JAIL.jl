# Decision: Public naming conventions and environment-variable configuration

| Field | Value |
|-------|-------|
| Artifact | `3_API_naming_and_env_config.md` |
| Category | design_decisions |
| Subject | `API` — public names, provider types and configuration surface |
| Date | 2026-09-25 |
| Area/Purpose scope | API, configuration |
| Related | supersedes `1_OAI_PROVIDER_key_at_url_config.md`; `artifacts/work_history/7_API_naming_config_refactor.md` |
| Status | accepted |
| Decided by | user (in a chat session whose transcript was lost; reconstructed from the resulting diff and the user's summary: "fixing some design/naming decisions which were not ideal") |

## Context

The public API had misspelled and inconsistently cased names (`avaliableModels`, `changeModels!`,
`modelProvider`, `ollama`, `exe`, `checkConfig`, `getRESTURL`, `getAnswer`, `question2JSONString`),
and configuration was a single pipe-delimited string (`"provider|model|apiOrURL"`) whose third
field was overloaded as key, URL, or `key@url` depending on the provider. `setapi` rebound a
global `Brain`, and `AskAI_key` was a hidden fallback.

## The Question

Not recoverable verbatim. Reconstructed: rename to idiomatic Julia names and replace the
overloaded config string with an explicit configuration surface, while keeping old usage working.

## Options Considered

### Option A — keep `provider|model|key@url` (decision 1)

- Pros: one env var, no API change.
- Cons: overloaded field, `@` ambiguity, provider-specific parsing, undiscoverable `AskAI_key`.

### Option B — separate env vars + keyword `setapi` (chosen)

- How it works: `ASK_AI_PROVIDER`, `ASK_AI_MODEL`, `ASK_AI_BASE_URL`, `ASK_AI_API_KEY`
  (plus `OPENAI_API_KEY`/`OPENAI_BASE_URL` for `openai`, `GEMINI_API_KEY` for `gemini`);
  `setapi(provider, model; url = nothing, api = nothing)` where `nothing` falls back to the env vars
  and then provider defaults.
- Pros: each value has one meaning; matches conventional OpenAI env names; real OpenAI works with
  only `OPENAI_API_KEY`.
- Cons: several env vars instead of one.

### Option C — hard break with no deprecations

- Rejected: breaks existing `startup.jl` files for no benefit.

## Decision

Option B, with snake_case function names and CamelCase types:

| Old | New |
|-----|-----|
| `avaliableModels` | `available_models` |
| `changeModels!` | `change_model!` |
| `exe` | `run_code` |
| `modelProvider` / `ollama` | `ModelProvider` / `Ollama` |
| `checkConfig` / `question2JSONString` / `getRESTURL` / `getAnswer` | `check_config` / `request_body` / `request_url` / `parse_answer` |
| `setAPI` export, `setapi("a|b|c")` | `setapi(provider, model; url, api)` |
| `AIBrain.RAG` | `AIBrain.rag` |

Old names remain as `@deprecate` / `Base.@deprecate_binding`; `setapi("p|m|x")` and
`ENV["AskAI_config"]` still work with a deprecation warning. `Brain` is a `const` mutated in place
by `setapi`, starting as a `NotConfigured` placeholder provider.

## Consequences

- Provider dispatch functions now take `(m, brain, question)` / `(m, stream::Bool)` so the provider
  sees stream mode and system context explicitly.
- `"openai"` is a distinct provider name mapping to `OpenAICompatible` with default URL
  `https://api.openai.com`.
- Deprecated names must be kept until a breaking version bump.

## Revisit Trigger

Next breaking release (remove deprecations), or if a provider needs configuration beyond
URL + single API key (e.g. org/project headers, Azure deployments).
