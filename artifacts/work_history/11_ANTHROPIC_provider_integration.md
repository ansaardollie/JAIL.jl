# Native Anthropic provider integration

| Field | Value |
|-------|-------|
| Artifact | `11_ANTHROPIC_provider_integration.md` |
| Category | work_history |
| Subject | `ANTHROPIC` — native provider, configuration, and documentation |
| Date | 2026-09-25 |
| Area/Purpose scope | providers, configuration, documentation |
| Related | `artifacts/design_decisions/6_ANTHROPIC_native_provider.md`, `artifacts/lib_inventories/Claude/1_CLAUDE_api_inventory.md`, `artifacts/lib_inventories/Claude/2_CLAUDE_usage_guide.md`, `artifacts/work_history/10_OAI_PROVIDER_auth_and_protocol_hardening.md` |

## Scope of This Unit of Work

Add first-class Anthropic support to AskAI using the existing provider dispatch path and the vendored Claude.jl API shape as reference. Update documentation with the required API-key and model configuration, then close out the completed unit.

## What Changed

| File | Change |
|------|--------|
| `src/models.jl` | Added `Anthropic <: ModelProvider`; implemented model listing, configuration requirements, URL normalization, `/v1/messages` request bodies, Anthropic headers, non-stream response parsing, SSE `content_block_delta` parsing, and API error extraction. Requests preserve bounded AskAI history and place assembled context in the Anthropic top-level `system` field. |
| `src/AskAI.jl` | Added `anthropic` to `PROVIDERS`, configured the default `https://api.anthropic.com` URL, and added `ANTHROPIC_API_KEY` fallback when explicit and generic AskAI keys are absent. |
| `readme.md` | Added Anthropic to supported providers, configuration tables, environment setup, and runtime `setapi` examples. |
| `docs/src/index.md` | Added Anthropic to overview/configuration text and a complete environment-variable setup example. |
| `artifacts/design_decisions/6_ANTHROPIC_native_provider.md` | Recorded the native-provider decision and rejected alternatives. |

## Design Decisions

- Use a dedicated provider rather than adding Anthropic protocol branches to `OpenAICompatible`, because the authentication, URL, body, response, and SSE contracts differ. See `artifacts/design_decisions/6_ANTHROPIC_native_provider.md`.
- Keep the implementation on HTTP.jl and JSON3.jl, matching AskAI's existing provider code and avoiding a new dependency.
- Default Anthropic requests to `max_tokens = 1024`, matching the vendored Claude.jl client's default. A future configurable token limit is a separate extension.

## Verification

Package loading through the Julia REPL:

```julia
using AskAI
println("AskAI loaded; provider names: ", AskAI.PROVIDERS)
println("Anthropic type available: ", AskAI.Anthropic)
```

```text
AskAI loaded; provider names: ["gemini", "ollama", "openai", "openai-compatible", "anthropic"]
Anthropic type available: AskAI.Anthropic
```

Provider request and parser fixtures:

```text
https://api.anthropic.com/v1/messages
Dict("anthropic-version" => "2023-06-01", "Content-Type" => "application/json", "x-api-key" => "test-key")
claude-3-5-sonnet-20241022 1024 Hello
Hi
Hi
true
AskAI.Anthropic https://api.anthropic.com
```

Credential fallback and error parsing:

```text
env-key https://api.anthropic.com claude-3-haiku
https://api.anthropic.com/v1/messages
test-key
ok
ok
```

The error fixture produced `Anthropic API error: bad key`. `get_errors` reported no diagnostics for the changed source or docs, and `git diff --check` passed.

## Known Limitations

- Live Anthropic model discovery was not completed: the environment's proxy blocked the attempted `/v1/models` request with `proxy CONNECT failed with status 403`. The local URL construction and model-list parser are implemented but not live-verified.
- No live Anthropic generation was attempted because no usable Anthropic credential was available.
- The provider currently sends a fixed `max_tokens = 1024`; AskAI does not yet expose a provider-wide max-token setting.
- Tool use, vision content, prompt caching, beta headers, and server-side Anthropic conversation state are not implemented.

## Todos

- Completed: none.
- Created: none.

## Next Steps

1. Add a focused local HTTP fixture for Anthropic `/v1/models`, non-streaming messages, and SSE streaming if automated provider tests are introduced.
2. Add a configurable Anthropic `max_tokens` field if users need output limits beyond the current default.
3. Extend the request model only when Anthropic tools, vision, or other native features are required.
