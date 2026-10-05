# TODO: Replay reasoning / thought output instead of dropping it

| Field | Value |
|-------|-------|
| Artifact | `4_MESSAGES_replay_reasoning.md` |
| Category | todos |
| Subject | `MESSAGES` |
| Date created | 2026-09-27 |
| Area/Purpose scope | core ontology, provider layer |
| Related | `work_history/6_MESSAGES_text_chat.md`, `design_decisions/12_MESSAGES_types_and_chat.md`, `provider_reviews/2_MESSAGES_text_turns.md` |
| Priority | high |
| Owner | any |

## What

`_parse_reply` in `src/providers/{google,openai,anthropic}.jl` keeps only text. Google
`thought` steps (with `signature`), OpenAI `reasoning` items, and Anthropic `thinking` blocks
are dropped, so they are never replayed.

## Why

Google docs: in stateless mode you "MUST always resend all `thought` blocks exactly as they were
received" (`artifacts/provider_docs/google/gemini-docs/gemini-docs-034-thought-signatures.md#L725-L731`).
OpenAI with `store=false` needs `include: ["reasoning.encrypted_content"]` to replay reasoning
(`openapi/api_spec.yaml#L45512-L45518`).

## Acceptance Criteria

- [ ] New content part type (name/shape asked of the owner) carrying summary text and a
      provider-opaque signature/encrypted payload
- [ ] Replayed to the provider that produced it; policy for other providers decided
      (Google says resend even across models)
- [ ] Mock-server check that the replayed request echoes the part verbatim for each provider
- [ ] `examples/chat.jl` updated

## Notes

Since `design_decisions/15_MESSAGES_server_side_chaining.md`, chained OpenAI/Google turns keep
reasoning/thought steps server-side; this todo now concerns full replays only (history edited,
provider switched, stored reply expired, `store_requests = false`).

Use a provider review first (skill `provider-docs-review`), covering doc 034 (Google), Anthropic
doc 21 (thinking), and OpenAI reasoning items.

## Completion

2026-10-05. `ReasoningPart(text, format, data)` (decision `25_MESSAGES_reasoning_part.md`) is
parsed, streamed, persisted and replayed for Anthropic, OpenAI Responses, Google Interactions and
GoogleEnterprise generateContent, only to the same provider type and wire. Verified live on all
four (full replays with tool calls). The provider review was done inline (citations in decision 25)
rather than as a separate `provider_reviews` artifact. `examples/chat.jl` was not changed; the
feature has its own `examples/reasoning.jl`. See `work_history/21_MESSAGES_reasoning_replay.md`.
