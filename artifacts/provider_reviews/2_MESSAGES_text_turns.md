# Text Turns (messages, system, multi-turn replay) — Provider Review

- **Date:** 2026-09-27
- **Providers:** OpenAI | OpenAICompatible | Anthropic | Google
- **Sub-features:** endpoint, text messages, system instructions, stateless history replay,
  reply text, stop reason, usage, reply-length cap, server-side storage
- **Doc snapshot:** artifacts/provider_docs (2026-09-26)

## Summary

All three multi-turn APIs accept a full client-side history of user/assistant text turns plus
a top-level system string, and return typed content with usage. They differ in container
(`input` items / `messages` / `input` steps), in the stop signal (a status field vs a
stop_reason), and in what must be echoed on replay: Google asks that thought steps (with
signatures) are replayed unmodified, OpenAI reasoning items need `encrypted_content` when
`store = false`. JAIL's first step drops both (text only).

## Per Provider

### OpenAI (Responses) — also OpenAICompatible default

- **Endpoint:** `POST {base}/responses` · `openapi/api_spec.yaml#L21038` · Bearer auth `#L110188-L110191`
- **Request fields:**

  | Field | Type | Req | Notes | Source |
  |---|---|---|---|---|
  | `model` | string | yes | | `#L54140` (ModelResponseProperties / ResponseProperties) |
  | `input` | string or item list | | EasyInputMessage `{role: user\|assistant\|system\|developer, content: string\|list}` | `#L45485`, `#L47189-L47240` |
  | `instructions` | string | | system/developer message; not carried over with `previous_response_id` | `#L45539` |
  | `max_output_tokens` | int ≥ 16 | | includes reasoning tokens | `#L45590` |
  | `store` | bool | | default **true** (30 days) | `#L45529-L45538` |

- **Response:** `status` (`completed|failed|in_progress|cancelled|queued|incomplete`),
  `incomplete_details.reason` (`max_output_tokens|max_messages|content_filter|steered`),
  `error`, `output[]` items; text in items `type = "message"` → `content[]` of `output_text`
  (`text`) or `refusal` (`refusal`) · `#L66872-L66965`, `#L54863-L54918`, `#L78719`, `#L78800`
- **Usage:** `input_tokens`, `output_tokens`, `total_tokens` (+ details) · `#L70636-L70680`
- **Multi-turn:** replay prior turns as `{role, content: string}` ·
  `core-concepts/openai-core-concepts-02-conversation-state-20260926.md#L40-L53` (SDK example,
  same wire shape). Reasoning items with `store=false` need `include: ["reasoning.encrypted_content"]` `#L45512-L45518` — not done yet.
- **Termination mapping:** refusal part → `:refusal`; completed → `:end_turn`; incomplete →
  `:max_tokens` / `:content_filter` / `:other`; failed → error.
- **Fixture:** `{"status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Orange who?","annotations":[],"logprobs":[]}]}],"usage":{"input_tokens":36,"output_tokens":87,...}}` (built from the schema).

### OpenAICompatible (Chat Completions fallback)

- **Endpoint:** `POST {base}/chat/completions` · `#L2249`, `CreateChatCompletionRequest #L42331`
- **Request:** `model`, `messages[{role: system|user|assistant, content}]`; `max_tokens`
  (deprecated at OpenAI for `max_completion_tokens`, `#L42574-L42586`, but what compatible
  servers accept — UNVERIFIED per server). No `store` sent (support unknown).
- **Response:** `choices[0].message.{content, refusal}`, `finish_reason`
  (`stop|length|tool_calls|content_filter|function_call`) · `#L42695-L42745`, `#L40876`;
  usage `prompt_tokens`, `completion_tokens` · `#L41457`
- **Mapping:** stop → `:end_turn`, length → `:max_tokens`, tool_calls/function_call →
  `:tool_use`, content_filter → `:content_filter`; a refusal → `:refusal`.

### Anthropic (Messages)

- **Endpoint:** `POST /v1/messages` · `anthropic/api_spec.yaml#L6`; headers `x-api-key`,
  `anthropic-version: 2023-06-01`
- **Request:** `model`, `messages[{role: user|assistant, content: string|blocks}]`,
  `max_tokens` (**required**), `system` (string or text blocks; no system role) ·
  `CreateMessageParams #L3437-L3691`, `InputMessage #L3745-L3785`. Consecutive same-role turns
  are merged.
- **Response:** `content[]` blocks (`type = "text"` → `text`), `stop_reason`, `usage
  {input_tokens, output_tokens}` · `Message #L3823-L3960`, `Usage #L5172`
- **Stop reasons:** spec enum is stale; docs list `end_turn, max_tokens, stop_sequence,
  tool_use, pause_turn, refusal, model_context_window_exceeded` ·
  `claude-docs/claude-docs-07-handling-stop-reasons.md#L13-L21`. JAIL:
  `model_context_window_exceeded` → `:max_tokens`, `pause_turn` → `:other` (server tools only).
- **Gotcha:** SDKs require streaming for `max_tokens` above ~21k (`claude-docs-07#L3501`).
- **Fixture:** spec example `#L3824-L3835` (`"Hi! My name is Claude."`, `end_turn`, 2095/503).

### Google (Interactions)

- **Endpoint:** `POST /v1beta/interactions` · `google/interactions.openapi.json#L1142`; header
  `x-goog-api-key`
- **Request:** `model`, `input` (string | Content | Content list | **Step list**),
  `system_instruction` (string), `store` (bool, default true: 55 days paid / 1 day free),
  `generation_config.max_output_tokens` · `CreateModelInteractionParams #L3850`,
  `GenerationConfig #L5314`, `gemini-docs-069-interactions-overview.md#L16-L19`, `#L310-L323`
- **Steps:** `{type: "user_input", content: [TextContent]}`, `{type: "model_output",
  content: [...]}`, `{type: "thought", signature, summary}` · `#L9639`, `#L7523`, `#L8706`,
  `TextContent #L8529`
- **Response:** `Interaction {id, status, steps, usage, errors}`; `status` enum `in_progress,
  requires_action, completed, failed, cancelled, incomplete, budget_exceeded (deprecated),
  queued` · `#L6412`; usage `total_input_tokens`, `total_output_tokens` · `#L9561`; `Error
  {code, message}` · `#L4795`. The create response only returns model-generated steps (doc 069 L47).
- **Multi-turn (stateless):** append returned steps then the next `user_input` ·
  `gemini-docs-002-get-started.md#L656-L709`. Thought steps **MUST** be resent exactly as
  received, even after switching models
  (`gemini-docs-034-thought-signatures.md#L725-L731`) — JAIL drops them for now: **known
  spec violation, first thing to fix**.
- **Mapping:** completed → `:end_turn`, incomplete → `:max_tokens` (docs: "e.g. hitting
  max_tokens"), requires_action → `:tool_use`, failed → error.

## Concept Mapping

| Concept | OpenAI | Anthropic | Google | OpenAICompatible (chat) | JAIL |
|---|---|---|---|---|---|
| User turn | input item `role:user` | message `role:user` | step `user_input` | `role:user` | `UserMessage` |
| Assistant turn | output item `message` | response `Message` / `role:assistant` | step `model_output` | `choices[0].message` | `AssistantMessage` |
| Text | `output_text.text` / string content | `text` block | `TextContent.text` | `content` string | `TextPart` |
| System | `instructions` | `system` | `system_instruction` | `role:system` message | `Session.system` |
| Stop | `status` + `incomplete_details.reason` | `stop_reason` | `status` | `finish_reason` | `stop_reason::Symbol` |
| Usage | `input_tokens`/`output_tokens` | same | `total_input_tokens`/`total_output_tokens` | `prompt_tokens`/`completion_tokens` | `Usage` |
| Reply cap | `max_output_tokens` | `max_tokens` (required) | `generation_config.max_output_tokens` | `max_tokens` | `max_tokens` kwarg / Preference |
| Storage | `store` | — | `store` | — | `store_requests` Preference |

Extensions (not modelled yet): OpenAI `developer` role, `phase`; Anthropic `stop_sequence`
value, `pause_turn`; Google `budget_exceeded`, per-modality token counts; server-side state
(`previous_response_id`, `previous_interaction_id`).

## Conflicts

- Anthropic spec `stop_reason` enum (4 values) vs docs (7 values): docs win.
- Google docs send `user_input.content` as a bare string (`gemini-docs-002#L666-L670`); the
  spec types it as a Content list. JAIL sends the list.

## Recommendation (implemented)

Stateless full-history replay on all providers, text-only, `store = false` by default. Next:
a `ReasoningPart` carrying provider-opaque signatures so Google thought steps / Anthropic
thinking blocks / OpenAI encrypted reasoning are replayed to the same provider and dropped on
provider switch.

## Open Questions

- Whether compatible servers (LM Studio, vLLM, llama.cpp) accept Responses without `store`
  and Chat Completions `max_tokens` — check with a live local server.
