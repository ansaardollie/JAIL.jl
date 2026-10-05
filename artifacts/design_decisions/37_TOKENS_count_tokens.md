# Decision: `count_tokens` and `TokenCount`

| Field | Value |
|-------|-------|
| Artifact | `37_TOKENS_count_tokens.md` |
| Category | design_decisions |
| Subject | `TOKENS` |
| Date | 2026-10-05 |
| Area/Purpose scope | public API for counting a session's input tokens; provider counting endpoints; `|` mode |
| Related | `9_SESSION_session_type.md`, `12_MESSAGES_types_and_chat.md`, `21_PROVIDER_google_enterprise_generate_content.md` |
| Status | accepted |
| Decided by | user (API shape); agent (details listed) |

## Context

User asked for "a token counter function for a session which counts how many tokens the
session's system prompt/tools/message history takes up for each provider using their canonical
token counting endpoint."

Endpoints (canonical, per provider):

- OpenAI / OpenAICompatible: `POST /responses/input_tokens` (`openapi/api_spec.yaml#L29898-L29935`,
  `TokenCountsBody #L84371`, `TokenCountsResource #L84471`;
  `openapi/api-references/openai-api-references-01-input-tokens.md`).
- Anthropic: `POST /v1/messages/count_tokens` (`anthropic/api_spec.yaml#L1118-L1187`,
  `BetaCountMessageTokensParams #L1527-L1711`; `claude-docs/claude-docs-54-token-counting.md`).
- Google: `POST /v1beta/models/{model}:countTokens` with a `generateContentRequest` wrapper for
  system instructions and tools (`google/counting-tokens.md#L28-L40`; GenerateContentRequest
  `model` required, fetched from https://ai.google.dev/api/batch-api#GenerateContentRequest).
  The Interactions API has no counting endpoint, so the generateContent `contents` format is used.
- GoogleEnterprise: `POST v1/projects/{p}/locations/{l}/publishers/google/models/{m}:countTokens`
  with top-level `contents`, `systemInstruction`, `tools` (`google/ai-platform-spec.json#L16210-L16240`,
  `#L49367-L49404`, response `#L53549`; `google/gemini-docs/count-tokens.md`), for both `api` values.

## Decision

User-decided:

- `count_tokens(session[, prompt]; model = nothing) -> TokenCount`, plus session-less
  `count_tokens([prompt]; model)` on `active_session()`.
- Returns a `TokenCount` with `total`, `system`, `tools`, `messages` (breakdown).
- `model` overrides the session's model (string or `Model`), to count for another model/provider.
- Optional `prompt`: counts history + that prompt without changing the session.
- OpenAICompatible uses the same `/responses/input_tokens` endpoint (user supplied its reference).
- Google implements system + tools via `generateContentRequest`.
- `|` mode gets `tokens [provider/model]`.

Agent-decided:

- Breakdown by cumulative requests: messages alone, + system, + tools; `system` and `tools` are
  the differences, `messages` the first count. Requests for an absent part are skipped (0 to 3
  requests). The breakdown is approximate (formatting tokens, Anthropic's estimate).
- Always the full history (never `previous_response_id`): the question is what the session's
  context costs, independent of server-side state.
- With no messages, Anthropic and Google (where `messages` / `contents` are required) count a
  one-character placeholder user message, which is subtracted; `messages` is then 0.
- Internal interface: `_count_url(p, model)`, `_count_body(p, req::_Request)`,
  `_parse_count(p, json)`.

## Rejected

- `Int` total only (no breakdown).
- Session's model only (no override).
- Throwing for OpenAICompatible.
- Counting messages only for Google (would silently omit system and tools).
- Local tokenizers (tiktoken etc.): new dependencies, inaccurate for tools and non-OpenAI models.

## Revisit Trigger

A provider adds per-part counts, Interactions gains a counting endpoint, or users need the
count of a single request including `previous_response_id` chaining.
