# Decision: Anthropic default `max_tokens` is the model's maximum output

| Field | Value |
|-------|-------|
| Artifact | `38_MESSAGES_anthropic_per_model_max_tokens.md` |
| Category | design_decisions |
| Subject | `MESSAGES` |
| Date | 2026-10-06 |
| Area/Purpose scope | default reply cap for Anthropic requests |
| Related | `12_MESSAGES_types_and_chat.md` (supersedes its 8192 Anthropic default) |
| Status | accepted |
| Decided by | user (values, per-model); agent (dispatch shape) |

## Context

Owner suspected the 8192 default cap reduced model efficacy. `max_tokens` is required with
`minimum: 1` (`anthropic/api_spec.yaml#L3518-L3529`); the owner confirmed live that omitting it
fails, and chose not to pursue 0.

## Decision

User-decided: when neither the `max_tokens` kwarg nor Preference is set, Anthropic sends the
model's maximum output: 128000 (Claude 4.6 / 5.1 / 5.5 generations and unknown ids), 64000
(Haiku 4.5), 4096 (3.5 generation).

Agent-decided:

- `default_max_tokens(::AbstractModel)` falls back to `default_max_tokens(::Type{P})`; Anthropic
  specializes on `Model{Anthropic}`, matching `"3-5"` and `"haiku-4-5"` in the model id.
- `_max_tokens` takes the model instead of the provider.
- 3.5 gets 4096 without the `max-tokens-3-5-sonnet-2024-07-15` beta header (headers are built
  from the provider only).

## Rejected

- Omitting `max_tokens` (API rejects; tried live by owner).
- `max_tokens = 0` (spec minimum 1; reverted by owner before trying).
- A flat 128000 for every model (exceeds Haiku 4.5 / 3.5 limits).

## Revisit Trigger

400s for models outside the listed families (3.7, Opus 4/4.1, Sonnet 4), or a model-metadata
source (e.g. the Models API) providing output limits.
