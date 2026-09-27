# Server-side chaining for OpenAI and Google

| Field | Value |
|-------|-------|
| Artifact | `8_MESSAGES_server_side_chaining.md` |
| Category | work_history |
| Subject | `MESSAGES` |
| Date | 2026-09-28 |
| Area/Purpose scope | provider layer, public API, Preferences |
| Related | `7_REPL_chat_mode.md`, `design_decisions/15_MESSAGES_server_side_chaining.md`, `design_decisions/12_MESSAGES_types_and_chat.md` (partly superseded) |

## Scope of This Unit of Work

The user, reviewing the source, asked why `previous_response_id` / `previous_interaction_id` were
never used. After the stateless-replay rationale (decision 12) they asked for chaining to be the
default wherever supported.

## What Changed

| File | Change |
|-------|--------|
| `src/ontology/messages.jl` | `AssistantMessage` gains `id::Union{Nothing,String}` (kwarg `id`) |
| `src/ontology/requests.jl` | `_Request.previous_id`; `_supports_chaining(::Type{P})` (default false) |
| `src/http.jl` | `_APIError(status, msg)` replaces `ErrorException` from `_api_error` (same text) |
| `src/chat.jl` | `store_requests` default → `true`; `_CHAIN_STATE`, `_fingerprint`, `_same_endpoint`, `_chain_point`, `_send`; `_complete` chains and retries once with full history on 400/404; `chat!` docstring |
| `src/providers/openai.jl` | `_supports_chaining(OpenAI) = true`, sends `previous_response_id`, parses `id` |
| `src/providers/google.jl` | `_supports_chaining(Google) = true`, sends `previous_interaction_id`, parses `id` |
| `src/providers/anthropic.jl`, `openai_compatible.jl` | parse `id` (no chaining) |
| `docs/src/guide/chat.md`, `providers.md` | "What gets sent" section; `store_requests` default |
| `examples/chat.jl`, `examples/sessions.jl` | header notes; `reply.id` in the live part |
| `artifacts/todos/pending/4_MESSAGES_replay_reasoning.md` | scope narrowed to full replays |

## Decisions

`design_decisions/15_MESSAGES_server_side_chaining.md`. User chose: flip `store_requests`
default (rejected: a separate chaining Preference); public `AssistantMessage.id` (rejected:
`response_id`, private Session storage); never chain OpenAICompatible (rejected: per-endpoint
opt-in); retry once on 400/404 (rejected: raise). Agent: fingerprint map keyed by reply id
(rejected: hidden message field, Session field).

## Verification

Fresh REPL, mock server returning a new id per request (`n_input` = messages sent):

```
(prev = "—", n_input = 1, store = true)
(prev = "resp_1", n_input = 1, store = true)
(prev = "resp_2", n_input = 1, store = true)
edit history → full replay        (prev = "—", n_input = 7, store = true)
next turn chains again            (prev = "resp_4", n_input = 1, store = true)
expired id → 400 → full replay    (prev = "resp_5", n_input = 1, store = true)  then  (prev = "—", n_input = 11, store = true)
chains from the retried reply     (prev = "resp_7", n_input = 1, store = true)
switch to anthropic → no chain    (prev = "—", n_input = 15, store = "—")
back to openai: last reply anthropic(prev = "—", n_input = 17, store = true)
different model, same provider    (prev = "resp_10", n_input = 1, store = true)
empty! → fresh                    (prev = "—", n_input = 1, store = true)
store_requests=false → full, store=false(prev = "—", n_input = 3, store = false)
google turn 2 chains              (prev = "int_15", n_input = 1, store = true)
compatible turn 2 (never chains)  (prev = "—", n_input = 3, store = "—")
```

Load check before commit:

```
fieldnames(AssistantMessage) = (:content, :model, :stop_reason, :usage, :id)
JAIL._store_requests() = true
JAIL._supports_chaining(OpenAI) = true
JAIL._supports_chaining(OpenAICompatible) = false
```

`examples/chat.jl` offline part ran; docs built with no warnings. No live provider calls.

## Known Limitations

- Status codes for an expired/unknown id on OpenAI and Google are assumed (400/404), not
  confirmed live.
- Full replays still drop reasoning / thought steps (todo 4).
- `_CHAIN_STATE` grows one entry per stored reply per process; fingerprint is text-only.
- No user-visible signal of chained vs full replay except `JULIA_DEBUG=JAIL`.
- Replies are retained by providers by default now.

## Todos

- Completed: none
- Created: none (todo 4 updated)

## Next Steps

1. Live check with the owner's keys: two OpenAI and two Google turns, confirm the second sends
   only the new turn; then try a bogus id to confirm the 400/404 fallback.
2. `4_MESSAGES_replay_reasoning.md`.
3. Streaming into `chat!` and the `}` mode.
4. `1_TESTS_test_suite_setup.md` (the mock server above is a ready fixture).
