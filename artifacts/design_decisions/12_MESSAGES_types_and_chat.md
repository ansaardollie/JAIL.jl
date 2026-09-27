# Decision: Message types, `chat!`, stop reasons, and request Preferences

| Field | Value |
|-------|-------|
| Artifact | `12_MESSAGES_types_and_chat.md` |
| Category | design_decisions |
| Subject | `MESSAGES` |
| Date | 2026-09-27 |
| Area/Purpose scope | core ontology, public API, Preferences |
| Related | `9_SESSION_session_type.md`, `10_SESSION_registry_and_default_session.md`, `3_PREFERENCES_nested_layout.md`, `../provider_reviews/2_MESSAGES_text_turns.md` |
| Status | accepted |
| Decided by | user (names, return value, scope, Preferences); agent (details below) |

## Context

User: "let's start with the meat of this package: the messages with the models. Remember that
there should be a JAIL semantic concept for the provider-agnostic version of each of the
Provider's message type. Also try starting off small so that I can run examples and
troubleshoot the flow." Decision 9 deferred concrete messages.

## The Questions and Answers

| Question | Options | Chosen |
|---|---|---|
| Message / content type names | `UserMessage`/`AssistantMessage` + `TextPart <: AbstractContentPart`; `UserMessage`/`AIMessage`; single `Message(role, parts)` | **first** |
| Function sending a turn | `chat!(session, prompt; max_tokens)` + `chat!(prompt)`; `send!`; `ask!` | **`chat!`** |
| Return value | the `AssistantMessage` carrying model, stop_reason, usage; separate `Response` wrapper | **`AssistantMessage`** (a tool loop yields several replies per turn, each with its own metadata) |
| Server-side storage (OpenAI/Google default to storing) | always `store=false`; provider default; Preference default false | **Preference, default false** |
| Preference key name | `store`; `server_store`; `store_requests` | **`store_requests`** |
| First-step scope | all providers text-only; + `}` mode; one provider | **all providers (incl. compatible Responses + Chat Completions), text only, no streaming, `chat!` only** |
| Stop reason symbols | `:end_turn :max_tokens :stop_sequence :tool_use :refusal :content_filter :other`; other set | **proposed set** |
| Reply text accessor | `string(msg)`; exported `text(msg)` | **`string(msg)`** |
| Anthropic `max_tokens` default | 8192; 4096; 16384; Preference `max_tokens` default 8192 | **Preference `max_tokens`, default 8192** |

## Decision

```julia
abstract type AbstractContentPart end
struct TextPart <: AbstractContentPart; text::String; end
struct UserMessage <: AbstractMessage; content::Vector{AbstractContentPart}; end
struct AssistantMessage <: AbstractMessage
    content::Vector{AbstractContentPart}
    model::Union{Nothing,AbstractModel}
    stop_reason::Union{Nothing,Symbol}
    usage::Union{Nothing,Usage}
end
struct Usage; input_tokens::Int; output_tokens::Int; end

UserMessage("text"); AssistantMessage("text"; model, stop_reason, usage)
chat!(session, prompt; max_tokens = nothing) -> AssistantMessage
chat!(prompt; max_tokens = nothing)            # active_session()
string(msg)                                    # concatenated TextParts
```

```toml
[JAIL]
max_tokens = 2048        # optional
store_requests = false   # optional, default false
```

Agent-decided:

- No system message type: system stays on `Session.system` (all three APIs take it top-level).
- `max_tokens` resolution: kwarg → Preference (applies to **every** provider) → reference
  function `default_max_tokens(::Type{P})` (8192 for Anthropic, `nothing` = omit for others).
  Rationale: a blanket 8192 would truncate OpenAI reasoning models (the cap includes
  reasoning tokens).
- `store` is sent only where `_has_store_field(::Type{P})` is true (OpenAI, Google), never to
  `OpenAICompatible` (server support unknown).
- History is replayed in full each call (stateless); `previous_response_id` /
  `previous_interaction_id` unused.
- A failed `chat!` pops the prompt again, leaving history unchanged.
- Messages whose text is empty are skipped on replay (Anthropic rejects empty blocks).
- `AssistantMessage` validates `stop_reason` against the set.
- `pause_turn` → `:other`, `model_context_window_exceeded` → `:max_tokens`, Google
  `incomplete` → `:max_tokens`, `requires_action` → `:tool_use`. Raw values are not kept.
- `ENV["JULIA_DEBUG"] = "JAIL"` logs request/response bodies (`@debug` in `_post_json`);
  headers are never logged.
- Internal wire tags `_ResponsesAPI` / `_ChatCompletionsAPI` so `OpenAICompatible` picks its
  wire format by dispatch after one check of `p.api`.

## Consequences

- Images, reasoning and tool calls become new `AbstractContentPart` subtypes (and a tool-result
  message type), additively.
- Google thought steps are dropped on replay, which the docs say MUST NOT happen
  (`gemini-docs-034-thought-signatures.md#L725-L731`). Fix next with a reasoning content part.

## Revisit Trigger

Reasoning/tool parts landing (may need per-part provider provenance), a need for the raw
provider stop reason, or a provider needing server-side state for correctness.
