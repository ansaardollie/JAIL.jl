# Decision: Server-side chaining by default (OpenAI `previous_response_id`, Google `previous_interaction_id`)

| Field | Value |
|-------|-------|
| Artifact | `15_MESSAGES_server_side_chaining.md` |
| Category | design_decisions |
| Subject | `MESSAGES` |
| Date | 2026-09-28 |
| Area/Purpose scope | provider layer, public API, Preferences |
| Related | `12_MESSAGES_types_and_chat.md` (superseded in part), `../provider_reviews/2_MESSAGES_text_turns.md`, `../todos/pending/4_MESSAGES_replay_reasoning.md` |
| Status | accepted |
| Decided by | user (default on, storage coupling, id field, compatible servers, fallback); agent (validity rule, fingerprint, retry statuses) |

## Context

User, reviewing the source: why no `previous_response_id` / `previous_interaction_id`? After the
rationale for stateless replay (decision 12), user: "I'd like the previous_id to be the default
for those providers that support it."

## The Questions and Answers

| Question | Options | Chosen |
|---|---|---|
| Storage vs chaining (ids need stored responses) | flip `store_requests` default to true, false disables chaining; separate Preference | **flip `store_requests` default** |
| Where the reply id lives | public `AssistantMessage.id`; field `response_id`; private on Session | **`id::Union{Nothing,String}`** |
| OpenAICompatible | never chain; opt-in per endpoint | **never** |
| Rejected / expired id | retry once with full history on HTTP 400/404; raise | **retry** |

## Decision

- `store_requests` default is now `true` (was `false` in decision 12).
- `AssistantMessage(...; id)`: every provider's reply id is kept (OpenAI `resp_…`, Google
  interaction id, Anthropic `msg_…`, Chat Completions id).
- Reference data `_supports_chaining(::Type{P})`: `true` for `OpenAI`, `Google`.
- `_complete` chains when: storing is on, the provider supports chaining, the last
  `AssistantMessage` has an `id` and came from the same provider type and `base_url` (the model
  may differ), and the history up to that reply is unchanged since it was received. Then only
  the messages after it are sent, with `previous_response_id` / `previous_interaction_id`.
  System instructions are sent every turn (both APIs scope them to one request).
- On `_APIError` with status 400 or 404 from a chained request, retry once with the full
  history (logged with `@debug`).

Agent-decided:

- "Unchanged" is checked with `_CHAIN_STATE::Dict{String,UInt}`: reply id → hash of
  `(role, text)` of the history up to and including that reply, recorded after each stored
  reply. Edits, seeding, `empty!`, or a Julia restart therefore fall back to full replay.
  Rejected: a hidden field on `AssistantMessage` (leaks into a public struct), a Session field
  (`_complete` is session-less).
- `_api_error` now returns `_APIError(status, msg)`; `showerror` prints the same text as before.

## Consequences

- Google thought steps are kept server-side when chaining, which satisfies the "resend thought
  blocks" rule for chained turns; full replays (edits, provider switch, `store_requests = false`)
  still drop them (todo 4 stands).
- Replies are retained by providers by default (OpenAI 30 days; Google 55 days paid / 1 day free).
- `_CHAIN_STATE` grows by one entry per stored reply for the life of the process.
- The fingerprint only covers text; must be extended when other content parts are replayed.

## Revisit Trigger

Non-text content parts landing (fingerprint), OpenAI `conversation` objects being preferred over
response chains, or a compatible server needing chaining.
