> **Superseded by:** `26_PROVIDER_google_enterprise_interactions_default.md` (the default wire; the
> tool-result failure was JAIL's plain-string `result`) and `25_MESSAGES_reasoning_part.md` (the
> thought-signature table).

# Decision: GoogleEnterprise defaults to generateContent; Interactions is opt-in; no partner models

| Field | Value |
|-------|-------|
| Artifact | `21_PROVIDER_google_enterprise_generate_content.md` |
| Category | design_decisions |
| Subject | `PROVIDER` |
| Date | 2026-09-30 |
| Area/Purpose scope | provider config, wire format, public API, Preferences |
| Related | `20_PROVIDER_google_enterprise_vertex_ai.md` (partly superseded), `1_PROVIDER_configurable_instances.md` |
| Status | accepted |
| Decided by | user (default wire, opt-in switch shape, partner-model revert, keep `Model ==`); agent (API version, thought-signature and call-id handling) |

## Context

In live use, the owner found that the Interactions API on Vertex AI does not handle function-call
results properly. The owner also concluded that partner (Model Garden) models from
`publishers/*/models` would break things: they don't support Interactions, and each publisher may
use a different endpoint.

## The Question

1. Which wire format does `GoogleEnterprise` use by default, and how is the other selected?
2. Keep partner-model listing?

## Options Considered

1. Switch shape: an `api` field + `providers.google_enterprise.api` Preference, mirroring
   `OpenAICompatible`'s `api` (chosen), vs a separate/global Preference key.
2. Partner models: keep listing them (rejected: selectable but unusable) vs revert to
   `publishers/google/models` (chosen).

## Decision

```julia
GoogleEnterprise(; project, location, service_account_path, api = :generate_content)  # or :interactions
configure_provider!(GoogleEnterprise(); api = :interactions)   # persisted as api = "interactions"
configure_provider!(GoogleEnterprise(); api = nothing)         # back to :generate_content (key removed)
```

- `:generate_content` (default): `POST {host}/v1/projects/{p}/locations/{l}/publishers/google/models/{id}:generateContent`,
  streaming via `:streamGenerateContent?alt=sse` (ai-platform-spec.json#L16296-L16357; `alt=sse`
  from python-genai models.py#L4753, absent from the discovery doc's `alt` enum). Stateless: full
  history every turn, `_supports_chaining`/`_has_store_field` are false for this wire.
- `:interactions`: the previous behaviour (`v1beta1/.../interactions`, server-side chaining).
- Wire chosen per instance via `_wire(p)` → `_GenerateContentAPI()` / `_InteractionsAPI()`, the
  same pattern as `OpenAICompatible`. `Google` itself always speaks Interactions.
- Tool schemas go in `FunctionDeclaration.parametersJsonSchema` (#L68049), because JAIL emits
  plain JSON Schema (`["t", "null"]` types, `anyOf`) that the OpenAPI-subset `parameters` field
  does not accept.
- `FunctionCall.id` is optional (#L65345): if it's missing, JAIL makes one up (`jail_call_…`) and
  never sends it back. `Part.thoughtSignature` is kept in a private table keyed by call id and
  replayed on that call's `functionCall` part (`ToolCall` has no field for it).
- Tool results are sent as `functionResponse.response = {"output": …}`, or `{"error": …}` when
  `is_error` (#L56327-L56370).
- Partner-model listing reverted: `list_models` uses `publishers/google/models` again.
- The `==(::Model, ::Model)` fix from the partner-model work is kept: it's needed by any provider
  with internal mutable state.
- Found while verifying: `configure_provider!` rewrote the whole provider table and so dropped a
  saved per-provider `default_model`. It now keeps it (affects every provider).

## Consequences

- `_request_url` gained a request-aware form `_request_url(p, req)` (default falls back to
  `_request_url(p)`), since the generateContent URL contains the model id and differs for streaming.
- Thought signatures live only in process memory: a history reloaded in a new process would lose
  them. Not a concern today, since sessions aren't persisted.

## Revisit Trigger

- Vertex fixes Interactions tool results → consider flipping the default.
- A need for partner models → probably a separate wire per publisher (e.g. Anthropic's
  `rawPredict` on Vertex), not a listing change.
- Session persistence lands → thought signatures need to live on the message.
  (Met: `24_SESSION_persistence.md` saves them on the `tool_call` line and reloads the table.)
