# Decision: Native Anthropic provider in AskAI

| Field | Value |
|-------|-------|
| Artifact | `6_ANTHROPIC_native_provider.md` |
| Category | design_decision |
| Subject | `ANTHROPIC` — provider integration and request protocol |
| Date | 2026-09-25 |
| Area/Purpose scope | providers, configuration, request protocol |
| Related | `artifacts/design_decisions/3_API_naming_and_env_config.md`, `artifacts/lib_inventories/Claude/1_CLAUDE_api_inventory.md`, `artifacts/lib_inventories/Claude/2_CLAUDE_usage_guide.md` |
| Status | accepted |
| Decided by | agent, implementing the user's request for an Anthropic provider using the existing provider dispatch pattern |

## Context

AskAI already has provider-specific dispatch for Gemini, Ollama, and OpenAI-compatible APIs. Anthropic's API is not OpenAI-compatible at the wire level: it uses `/v1/messages`, `x-api-key`, `anthropic-version`, a top-level `system` field, and `content_block_delta` streaming events. The vendored `Claude.jl` package provided the request and response shape reference.

## Decision

Add a dedicated `Anthropic <: ModelProvider` with `model`, `url`, and `api` fields. Keep the existing AskAI provider contract and implement Anthropic-specific methods in `src/models.jl`:

- `GET /v1/models` for `available_models`.
- `POST /v1/messages` for completion requests.
- `x-api-key` and `anthropic-version: 2023-06-01` headers.
- A top-level `system` string assembled from AskAI prompt, RAG, terminal context, and bounded memory.
- `content[1].text` extraction for non-streaming responses.
- `content_block_delta` / `text_delta` extraction for SSE streaming.
- `ANTHROPIC_API_KEY` as the provider-specific credential fallback.

## Options considered

### Reuse `OpenAICompatible`

Rejected because Anthropic's endpoint paths, authentication headers, request fields, response shape, and SSE event protocol differ. Encoding these branches into the OpenAI-compatible provider would make its existing contract harder to reason about.

### Add the vendored `Claude.jl` package as a dependency

Rejected because AskAI already depends on HTTP.jl and JSON3.jl, and direct provider methods keep configuration, streaming, history, and error handling within AskAI's existing abstraction.

### Add a separate high-level client layer

Rejected because `AIBrain` already owns lifecycle, history, streaming, and Markdown rendering. A provider-specific dispatch implementation is smaller and preserves the established architecture.

## Consequences

- Users can configure `setapi("anthropic", model; api=...)` or use `ASK_AI_PROVIDER`, `ASK_AI_MODEL`, and `ANTHROPIC_API_KEY`.
- The provider currently sends `max_tokens = 1024`, matching Claude.jl's default; AskAI has no provider-wide max-token setting yet.
- Anthropic model discovery requires a reachable `/v1/models` endpoint and valid credentials.
- No additional dependency or manifest change is required.

## Revisit Trigger

Reopen this decision if Anthropic-specific features such as configurable max tokens, tool use, vision content, prompt caching, beta headers, or server-side conversation state become required. At that point, extend the provider fields and request model rather than adding protocol branches to `OpenAICompatible`.
