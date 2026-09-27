# Decision: User-facing functions for providers and model selection

| Field | Value |
|-------|-------|
| Artifact | `5_API_provider_model_functions.md` |
| Category | design_decisions |
| Subject | `API` |
| Date | 2026-09-27 |
| Area/Purpose scope | public API |
| Related | `1_PROVIDER_configurable_instances.md`, `2_MODEL_parametric_model_string_form.md`, `6_MODEL_live_listing.md` |
| Status | accepted |
| Decided by | user (names); agent (semantics under provider shape C) |

## Context

Names were proposed while provider shape A was on the table; the user then picked shape C
(configurable instances) and kept the names "as-is". Semantics were adapted by the agent.

## The Question

"Names for this session's user-facing functions?" Options: proposal as-is (chosen), merge
configure/register into one `configure!` (rejected), freeform.

Also: "Define the session (Brain-like) type now, or later?" → later; this session only persists
a default model.

## Decision

```julia
set_default_model!("anthropic/claude-sonnet-4-5")   # also accepts a Model; returns the Model
default_model()                                      # -> Model{Anthropic}; errors if unset
configure_provider!(Anthropic(); api_key_env="MY_KEY", base_url=nothing)
register_provider!(OpenAICompatible("lmstudio", "http://localhost:1234/v1"))
providers()                                          # Vector{AbstractProvider}
list_models(Anthropic())                             # Vector{Model{Anthropic}}
```

Agent-decided semantics:

- `configure_provider!(p; kw...)`: apply `kw` on top of `p`, then persist the result. `nothing`
  removes the stored value (first-party: back to default; `OpenAICompatible`: no key / default api).
  Returns the freshly loaded provider. For `OpenAICompatible`, the name must already be registered.
- `register_provider!(p::OpenAICompatible)`: persist a named endpoint, overwriting an existing one
  with the same name, so scripts can be re-run. Returns `p`.
- `set_default_model!` validates that the provider resolves; it does not call the API.

## Consequences

The session type (name and shape) is still open; `default_model()` is what it will start from.

## Revisit Trigger

The session type lands and needs `select_model!(session, ...)`, or users ask for
`unregister_provider!`.
