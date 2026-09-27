# Decision: How providers carry configuration, and what they are called

| Field | Value |
|-------|-------|
| Artifact | `1_PROVIDER_configurable_instances.md` |
| Category | design_decisions |
| Subject | `PROVIDER` |
| Date | 2026-09-27 |
| Area/Purpose scope | core ontology, public API |
| Related | `2_MODEL_parametric_model_string_form.md`, `3_PREFERENCES_nested_layout.md`, `5_API_provider_model_functions.md` |
| Status | accepted |
| Decided by | user (shape, names); agent (constructor-reads-Preferences, name rules, persisted-diff rule) |

## Context

First implementation session. Every later feature (requests, streaming, tools) dispatches on the
provider, so its shape had to be fixed first. Redesign notes #1, #2, #10 apply.

## The Question

"How should providers carry configuration (base URL, key env var, API flavour)?" and
"Exported provider type names?"

## Options Considered

### Option A — first-party singletons + named `OpenAICompatible` instances

- Pros: minimal; several compatible endpoints coexist.
- Cons: overriding a first-party base URL/key env only via Preferences.

### Option B — all singletons, all config in Preferences

- Cons: only one `OpenAICompatible` endpoint at a time.

### Option C — every provider is a configurable instance (chosen)

- Pros: most flexible; an ad-hoc `Anthropic(base_url="http://proxy")` works without touching Preferences.
- Cons: slightly more verbose; two notions of a value (type default vs instance).

Name options: `OpenAI, OpenAICompatible, Anthropic, Google` (chosen) vs `*Provider` suffixes
(rejected: verbose; the OpenAI.jl clash was accepted).

## Decision

Option C, short names.

```julia
abstract type AbstractProvider end
abstract type AbstractOpenAIProvider <: AbstractProvider end   # shared impl via dispatch
struct OpenAI <: AbstractOpenAIProvider;  base_url::String; api_key_env::String; end
struct Anthropic <: AbstractProvider;     base_url::String; api_key_env::String; end
struct Google <: AbstractProvider;        base_url::String; api_key_env::String; end
struct OpenAICompatible <: AbstractOpenAIProvider
    name::String; base_url::String; api_key_env::Union{Nothing,String}; api::Symbol  # :responses | :chat_completions
end
```

Agent-decided details:

- Type-level reference data (`base_url(::Type{P})`, `default_api_key_env(::Type{P})`,
  `provider_name(::Type{P})`, `anthropic_version`, `api_version(::Type{Google})`) are the defaults.
- Keyword constructors fill unset fields from Preferences, then from the type default. So
  `Anthropic()` always reflects the persisted config; explicit kwargs win.
- `OpenAICompatible(name)` loads a registered endpoint; `OpenAICompatible(name, base_url; ...)` builds one.
- Compatible names must match `^[A-Za-z0-9._-]+$` (no `/`, which is the model-string separator) and
  may not be `openai`, `anthropic`, `google`.
- Only fields that differ from the type default are persisted, so future default changes propagate.
- Default key env vars: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`
  (`GEMINI_API_KEY` is the name used across `artifacts/provider_docs/google/gemini-docs`).

## Consequences

- Dispatch on the concrete provider type; instance fields only carry connection config.
- Adding a first-party field later means a Preferences key and a constructor kwarg.

## Revisit Trigger

A need for two differently configured first-party providers under distinct names (e.g. two
Anthropic workspaces), which the current name-per-type scheme cannot express.
