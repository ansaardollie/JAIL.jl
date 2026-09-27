# Text chat: message ontology and `chat!` on all providers

| Field | Value |
|-------|-------|
| Artifact | `6_MESSAGES_text_chat.md` |
| Category | work_history |
| Subject | `MESSAGES` |
| Date | 2026-09-27 |
| Area/Purpose scope | core ontology, provider layer, public API |
| Related | `design_decisions/12_MESSAGES_types_and_chat.md`, `design_decisions/10_SESSION_registry_and_default_session.md` (amended), `provider_reviews/2_MESSAGES_text_turns.md`, `4_SESSION_registry_and_default_session.md` |

## Scope of This Unit of Work

First request/response slice, kept small on purpose: text-only, non-streaming turns on a
`Session` for OpenAI, OpenAICompatible (Responses and Chat Completions), Anthropic and Google.
Follow-up in the same unit: the user hit `set_model!("anthropic/claude-opus-5-5")` failing
(no session-less method) and asked that all session functions work on the active session.

## What Changed

| File | Change |
|-------|--------|
| `src/ontology/messages.jl` | `AbstractContentPart`, `TextPart`, `UserMessage`, `AssistantMessage`, `Usage`, `_STOP_REASONS`, `print`/`show` |
| `src/ontology/requests.jl` | new: `_Request`, interface stubs `_request_url`/`_request_body`/`_parse_reply`, `default_max_tokens`, `_has_store_field`, `_replayable`, `_usage` |
| `src/http.jl` | `_post_json` with `@debug` request/response logging; `_error_message` |
| `src/providers/openai.jl` | `_ResponsesAPI`/`_ChatCompletionsAPI` tags, `_wire`, Responses encode/parse |
| `src/providers/openai_compatible.jl` | `_wire` by `p.api`, Chat Completions encode/parse |
| `src/providers/anthropic.jl` | Messages encode/parse, `default_max_tokens = 8192`, stop map |
| `src/providers/google.jl` | Interactions encode/parse (Step list replay) |
| `src/chat.jl` | new: `_max_tokens`, `_store_requests`, `_complete`, `chat!` |
| `src/JAIL.jl` | includes + exports |
| `src/session.jl` | `set_model!(model)` on `active_session()` |
| `examples/sessions.jl`, `docs/src/guide/sessions.md` | show `set_model!(model)`; stale header line fixed |
| `artifacts/design_decisions/10_SESSION_registry_and_default_session.md` | amendment: every Session-first function has a session-less form; `Base.empty!()` excluded (type piracy) |
| `examples/chat.jl` | new (live part behind `LIVE = false`) |
| `docs/src/guide/chat.md`, `docs/make.jl`, `reference.md`, `index.md`, `concepts.md`, `sessions.md`, `providers.md` | chat page, reference entries, new Preferences keys |

## Verification

REPL (Julia 1.13) against a local `HTTP.serve!` stub returning doc/spec fixtures:

- Captured request bodies for all five wire paths match the specs (roles, `instructions` /
  `system` / `system_instruction` / system message, `store: false` only for OpenAI/Google,
  `max_output_tokens` / `max_tokens` / `generation_config.max_output_tokens`, no auth header for
  keyless compatible server).
- Multi-turn replay includes the prior assistant reply in each wire format.
- Parse: text, usage and stop reason for each; refusal, incomplete, failed (error raised),
  `model_context_window_exceeded`, `pause_turn`.
- HTTP 400 → `anthropic API error (HTTP 400): …`, history length unchanged.
- Preferences `max_tokens = 2048` / `store_requests = true` applied; kwarg overrides; invalid
  `store_requests = "yes"` rejected; keys removed afterwards.
- Debug log shows bodies, not the key.
- `examples/chat.jl` offline part ran in a fresh REPL; `docs/make.jl` built with no warnings.
- No live provider calls made by the agent. The user reported afterwards: "the chat
  functionality works nicely" (user-verified live; agent did not see the output).
- `set_model!` follow-up, fresh REPL:

  ```
  set_model!("anthropic/claude-opus-5-5") = Model("anthropic/claude-opus-5-5")
  active_session() = Session("default", anthropic/claude-opus-5-5, 0 messages)
  set_model!(Model("openai/gpt-5")) = Model("openai/gpt-5")
  ERROR: ArgumentError: expected "provider/model" (e.g. "anthropic/claude-sonnet-4-5"), got "claude-opus-5-5"
  ```

  `examples/sessions.jl` ran top to bottom; docs rebuilt with no warnings.

## Known Limitations

- Google thought steps, OpenAI reasoning items, Anthropic thinking blocks are dropped; Google
  docs say thought steps MUST be replayed.
- No streaming, tools, images, `}` mode, one-shot functions.
- Compatible-server behaviour (Responses without `store`, Chat `max_tokens`) unverified.
- No session-less way to clear history (`empty!` needs a session); a JAIL-named function
  (e.g. `clear_history!()`) was offered but not requested.

## Todos

- Completed: none
- Created: `todos/pending/4_MESSAGES_replay_reasoning.md`

## Next Steps

1. Reasoning content part with provider-opaque signatures (fixes the Google MUST in
   `gemini-docs-034-thought-signatures.md#L725-L731`).
2. `}` ask REPL mode on `chat!`.
3. Streaming.
4. Test suite (`artifacts/todos/pending/1_TESTS_test_suite_setup.md`) with the stub-server
   fixtures from this session.
