# Streaming (text) — Provider Review

- **Date:** 2026-09-28
- **Providers:** OpenAI | OpenAICompatible | Anthropic | Google
- **Sub-features:** request flag, event sequence, text deltas, terminal event, usage, errors
- **Doc snapshot:** artifacts/provider_docs (2026-09-26)

## Summary

All four wire formats stream over SSE when the body has `"stream": true`. OpenAI Responses ends
with an event carrying the full Response (so the non-stream parser can be reused); Anthropic and
Google require accumulating deltas plus a final usage/status event; Chat Completions ends with
`data: [DONE]` and has no usage unless `stream_options.include_usage` is sent.

## Per Provider

### OpenAI (Responses)

- **Request:** `stream: true` · `openapi/api_spec.yaml#L45562`
- **Text:** `response.output_text.delta` → `delta` · `#L70512`; refusal `response.refusal.delta` · `#L69679`
- **Terminal:** `response.completed` · `#L67455`, `response.incomplete` · `#L68572`, `response.failed` · `#L67945`, each with `response` = full Response
- **Error:** `{type: "error", code, message, param}` · `#L67898`
- **Guide:** `core-concepts/openai-core-concepts-04-streaming-20260926.md#L142-L228`

### OpenAICompatible (Chat Completions)

- **Request:** `stream: true` · `#L42521`
- **Chunks:** `CreateChatCompletionStreamResponse` · `#L42853`: `choices[].delta.{content, refusal}` · `#L41065`, `choices[].finish_reason`; usage only on the last chunk with `stream_options: {"include_usage": true}` (not sent: server support UNVERIFIED)
- **End:** `data: [DONE]` (DOCS-ONLY convention; not in the spec's schemas)

### Anthropic (Messages)

- **Request:** `stream: true` · `anthropic/api_spec.yaml#L3287`
- **Flow:** `message_start` (Message with id, usage) → per block `content_block_start` / `content_block_delta` / `content_block_stop` → `message_delta` (`delta.stop_reason`, cumulative `usage.output_tokens`) → `message_stop`; `ping` anywhere · `claude-docs/claude-docs-15-streaming.md#L296-L306`, example `#L539-L563`
- **Text:** `delta.type = "text_delta"`, `delta.text` · `#L328-L336`; `thinking_delta` / `signature_delta` / `input_json_delta` ignored for now
- **Error:** `event: error`, `{type: "error", error: {type, message}}` · `#L318-L319`

### Google (Interactions)

- **Request:** `stream: true` · `google/interactions.openapi.json#L3983`
- **Events (`event_type`):** `interaction.created`, `interaction.status_update`, `step.start` (`step.type`), `step.delta`, `step.stop` (`usage`), `interaction.completed` (partial Interaction: id, status, usage), `error` · `InteractionSseEvent` schema; `gemini-docs/gemini-docs-070-streaming.md#L133-L184`
- **Text:** `step.delta` with `delta.type = "text"` in a `model_output` step; thought steps stream `thought_signature` / `thought_summary` deltas (ignored for now)
- **Conflict:** docs 002/027/036 use `?alt=sse`; spec and doc 070 use `"stream": true` (used)

## Concept Mapping

| Concept | OpenAI | Anthropic | Google | Chat Completions | JAIL |
|---|---|---|---|---|---|
| Enable | `stream` | `stream` | `stream` | `stream` | `_Request.stream` (set when `on_text` given) |
| Text delta | `output_text.delta` | `text_delta` | `step.delta` text | `delta.content` | `on_text(delta)` |
| Final reply | terminal event's `response` | accumulated + `message_delta` | accumulated + `interaction.completed` | accumulated + `finish_reason` | `_stream_finish` → `AssistantMessage` |
| Error | `error` event | `error` event | `error` event | HTTP status | exception after the stream |

## Recommendation (implemented)

Per-provider accumulators (`_stream_state` / `_stream_event!` / `_stream_finish`) that rebuild the
non-stream JSON shape and reuse `_parse_reply`; transport via HTTP.jl 2.8 `sse_callback`.

## Open Questions

- Whether compatible servers support `stream_options.include_usage` (would restore usage).
