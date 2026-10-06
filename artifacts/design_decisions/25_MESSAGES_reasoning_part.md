# Decision: How reasoning/thought signatures are held in the history and replayed

| Field | Value |
|-------|-------|
| Artifact | `25_MESSAGES_reasoning_part.md` |
| Category | design_decisions |
| Subject | `MESSAGES` |
| Date | 2026-10-05 |
| Area/Purpose scope | core ontology, public API, provider layer, persistence |
| Related | `12_MESSAGES_types_and_chat.md`, `15_MESSAGES_server_side_chaining.md`, `21_PROVIDER_google_enterprise_generate_content.md` (its thought-signature table is replaced), `24_SESSION_persistence.md`, `todos/completed/4_MESSAGES_replay_reasoning.md` |
| Status | accepted |
| Decided by | user (public part, name, cross-provider policy); agent (wire-level mapping, persistence shape) |

## Context

The owner asked that thought signatures be "sent back for every provider where the full history
is attached to the request". Before this change JAIL dropped:

- Anthropic `thinking` / `redacted_thinking` blocks. Thinking is on by default on Sonnet 5 /
  Opus 5.x (claude-docs-21-thinking.md#L47-L49), and the blocks are required within a tool-use
  turn (#L909-L924). The API silently disables thinking rather than erroring, so this went unseen.
- OpenAI Responses `reasoning` items (`encrypted_content` returned by default; api_spec.yaml
  ReasoningItem #L66801; must be passed back with tool outputs, tool-guides-02 #L475-L477).
- Google Interactions `thought` steps (must be resent unchanged in stateless mode,
  gemini-docs-034-thought-signatures.md#L725-L731).
- generateContent `thoughtSignature` on text parts. Only function-call signatures were kept, in a
  process-global table keyed by call id.

## The Question

1. How should replies' reasoning/signatures be held in the history so they can be replayed?
2. Its name.
3. What happens when the history goes to a different provider than the one that produced it?

## Options Considered

### Option A: public content part (chosen)

- How it works: a new exported `ReasoningPart <: AbstractContentPart` in `AssistantMessage.content`,
  in arrival order, with `text` (readable summary, often empty), `format::Symbol` (wire format),
  and `data::Dict{String,Any}` (the provider's record, replayed verbatim).
- Pros: typed, visible, persisted like other parts; replaces the global signature table; opens the
  door to showing reasoning summaries later.
- Cons: exposes provider-opaque data on a public type.

### Option B: hidden payload on AssistantMessage

- How it works: a private field holding raw provider output items, replayed verbatim.
- Pros: nothing new public.
- Cons: users can't inspect reasoning; raw provider JSON lives on messages.

Names offered: `ReasoningPart` (chosen), `ThinkingPart`, `ThoughtPart`.

Cross-provider options: drop unless same provider type + wire format (chosen); drop unless same
provider + same model (rejected: Google and Anthropic both say to keep resending across model
switches and let the backend filter).

## Decision

```julia
struct ReasoningPart <: AbstractContentPart
    text::String                 # summary; not part of string(msg)
    format::Symbol               # :anthropic | :openai_responses | :google_interactions | :google_generate_content
    data::Dict{String,Any}       # replayed unchanged
end
```

Replayed only when `part.format` matches the request's wire and the message's
`model.provider` has the same type as the request's provider (`_replays` in
`src/ontology/messages.jl`). Hand-written replies (no model) never replay reasoning.

Agent-decided wire mapping:

| Format | Parsed from | Replayed as |
|---|---|---|
| `:anthropic` | `thinking` / `redacted_thinking` blocks (stream: `thinking_delta`, `signature_delta`) | the block, in order |
| `:openai_responses` | `reasoning` output item minus `status` | the item, in order |
| `:google_interactions` | `thought` step (stream: `thought_summary`, `thought_signature` deltas) | the step, in order |
| `:google_generate_content` | `thoughtSignature` on any part → a signature-only part placed before that part's content; `thought: true` parts kept whole | the signature goes back onto the next emitted part; a trailing one as `{"text": "", "thoughtSignature": …}` |

Persistence: `{"type": "reasoning", "text", "format", "data"}`. Lines written before this change
with `tool_call.thought_signature` are read as a `:google_generate_content` part before the call.

## Consequences

- `_THOUGHT_SIGNATURES` is gone; signatures survive restarts via the session files.
- Replays now preserve per-part order (text, reasoning, calls) instead of "all text, then calls".
- Any new provider must map its reasoning to a format symbol and replay it in `_request_body`.
- JAIL still does not request summaries (Anthropic `display`, OpenAI `reasoning.summary`, Google
  `thinking_summaries`), so `text` is usually empty. (Since `40_STREAMING_show_reasoning.md`, it
  does when `show_reasoning` is on, and adds a `:chat_completions` format that is never replayed.)

## Revisit Trigger

- Showing reasoning in the REPL or requesting summaries (a Preference or per-request option).
- A provider documents that signatures are portable across wires (e.g. Interactions ↔
  generateContent), which would relax the same-wire rule.
- A provider rejects verbatim replay of a field JAIL keeps (e.g. OpenAI `status`).
