# Decision: How a model is represented and written as a string

| Field | Value |
|-------|-------|
| Artifact | `2_MODEL_parametric_model_string_form.md` |
| Category | design_decisions |
| Subject | `MODEL` |
| Date | 2026-09-27 |
| Area/Purpose scope | core ontology, public API, Preferences, `\|` REPL mode |
| Related | `1_PROVIDER_configurable_instances.md`, `3_PREFERENCES_nested_layout.md` |
| Status | accepted |
| Decided by | user |

## Context

Note #1: provider ≠ model; OldJAIL's bare `.model` string conflated them.

## The Question

"How should a model be represented?" and "Short string form for a model?"

## Options Considered

### Shape A — `Model{P}(provider, id)` (chosen)

One parametric type; the id is provider-specific data. Capabilities later as functions.

### Shape B — per-family types (`Claude`, `GPT`, `Gemini`)

Rejected: needs updating every release; doesn't fit `OpenAICompatible` (arbitrary models).

### String forms

- `provider:model` (agent recommendation; `/` appears in OpenRouter ids)
- `provider/model` (chosen; familiar from LiteLLM/OpenRouter)
- no string form

## Decision

```julia
abstract type AbstractModel end
struct Model{P<:AbstractProvider} <: AbstractModel
    provider::P
    id::String
end
Model("anthropic/claude-sonnet-4-5")
Model("openrouter/openai/gpt-5")   # provider "openrouter", id "openai/gpt-5"
```

Split on the **first** `/`, so ids containing `/` still work. The prefix is `provider_name`
(lowercase type name, or the `OpenAICompatible` name). `string(m)` returns the same form.

## Consequences

- Provider names can never contain `/` (enforced at registration).
- `Model(str)` resolves the provider through Preferences at call time.

## Revisit Trigger

A provider whose model ids *start* with something that looks like a registered provider name and
causes ambiguity, or a request to attach listing metadata (display name, limits) to `Model`.
