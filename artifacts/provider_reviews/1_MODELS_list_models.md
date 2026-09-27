# List Models — Provider Review

- **Date:** 2026-09-27
- **Providers:** OpenAI | OpenAICompatible | Anthropic | Google
- **Sub-features:** endpoint, auth headers, pagination, id extraction
- **Doc snapshot:** artifacts/provider_docs (2026-09-26) plus two official pages fetched 2026-09-27
  with user approval (not saved locally):
  - Anthropic: https://platform.claude.com/docs/en/api/models/list
  - Google: https://ai.google.dev/api/models (models.list, Model resource)

## Summary

All three vendors expose a GET list endpoint returning model objects with a string id. They
differ in path, auth header, pagination (none / cursor / page token), and Google prefixes ids with
`models/` and mixes in non-chat models.

## Per Provider

### OpenAI / OpenAICompatible

- **Endpoint:** `GET {base_url}/models`, base `https://api.openai.com/v1` · `openapi/api_spec.yaml#L14-L17`, `#L10097-L10115`
- **Auth:** `Authorization: Bearer <key>` (`ApiKeyAuth`, http bearer) · `openapi/api_spec.yaml#L110188-L110191`
- **Response:** `ListModelsResponse {object: "list", data: [Model]}`; `Model.id` required · `openapi/api_spec.yaml#L52219-L52233`, `#L53954-L53985`
- **Pagination:** none.
- **Fixture:** `openapi/api_spec.yaml#L10155-L10181` (`{"object":"list","data":[{"id":"model-id-0",...}]}`).
- **OpenAICompatible:** same shape assumed; UNVERIFIED per server (LM Studio, vLLM, llama.cpp).

### Anthropic

- **Endpoint:** `GET https://api.anthropic.com/v1/models` · fetched page (not in local spec; `anthropic/api_spec.yaml` has no `/v1/models` path)
- **Auth:** `x-api-key: <key>`, `anthropic-version: 2023-06-01` · `anthropic/claude-docs/claude-docs-02-get-api-key.md#L45`, `claude-docs-03-get-started.md#L31-L32`
- **Query:** `limit` (1–1000, default 20), `after_id`, `before_id` · fetched page
- **Response:** `{data: [ModelInfo], first_id, has_more, last_id}`; `ModelInfo.id`, `display_name`,
  `created_at`, `max_input_tokens`, `max_tokens`, `capabilities` · fetched page
- **Pagination:** repeat with `after_id = last_id` while `has_more`.
- **Fixture:** `{"data":[{"id":"claude-opus-5","type":"model","display_name":"Claude Opus 5","created_at":"2026-07-24T00:00:00Z"}],"first_id":"...","has_more":false,"last_id":"..."}` (trimmed from fetched page).

### Google

- **Endpoint:** `GET https://generativelanguage.googleapis.com/v1beta/models` · fetched page; host from `google/interactions.openapi.json#L9-L14`
- **Auth:** `x-goog-api-key: <key>` · `google/interactions.openapi.json#L10338-L10340`
- **Query:** `pageSize` (default 50, max 1000), `pageToken` · fetched page
- **Response:** `{models: [Model], nextPageToken}`; `Model.name` = `models/{id}`,
  `supportedGenerationMethods: [string]` · fetched page
- **Pagination:** repeat with `pageToken = nextPageToken` until it is absent.
- **Filter:** keep models whose `supportedGenerationMethods` contains `"generateContent"`
  (UNVERIFIED proxy for Interactions support; doc 069 lists Interactions models statically at
  `gemini-docs/gemini-docs-069-interactions-overview.md#L351-L376`).
- **Fixture:** `{"models":[{"name":"models/gemini-3.8-flash","supportedGenerationMethods":["generateContent"]},{"name":"models/text-embedding-004","supportedGenerationMethods":["embedContent"]}]}` (constructed from the Model resource schema).

## Concept Mapping

| Concept | OpenAI | Anthropic | Google | OpenAICompatible | JAIL |
|---|---|---|---|---|---|
| List path | `/models` | `/v1/models` | `/v1beta/models` | `/models` | `list_models(p)` |
| Model id | `data[].id` | `data[].id` | `models[].name` minus `models/` | `data[].id` | `Model{P}.id` |
| Next page | — | `after_id=last_id` if `has_more` | `pageToken=nextPageToken` | — | internal loop |
| Auth | Bearer | `x-api-key` + `anthropic-version` | `x-goog-api-key` | Bearer (optional) | `_auth_headers(p)` |

Extensions (not in `Model` yet): Anthropic `capabilities`, `max_input_tokens`; Google
`inputTokenLimit`, `thinking`; OpenAI `owned_by`, `shutdown_date`.

## Conflicts

- The local Anthropic spec's `Model` schema (`anthropic/api_spec.yaml#L5527`) is a stale enum of
  claude-3 ids; ignore it for listing.

## Open Questions

- Should `Model` carry listing metadata (display name, context window)? Deferred.
