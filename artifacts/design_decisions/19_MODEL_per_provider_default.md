# Decision: Per-provider default models and `use provider` / `use_provider!`

| Field | Value |
|-------|-------|
| Artifact | `19_MODEL_per_provider_default.md` |
| Category | design_decisions |
| Subject | `MODEL` |
| Date | 2026-09-28 |
| Area/Purpose scope | configuration, REPL surface, imperative API |
| Related | `8_REPL_model_mode.md`, `3_PREFERENCES_nested_layout.md`, `9_SESSION_session_type.md` |
| Status | accepted |
| Decided by | user (names, shape); agent (message text, completion) |

## Context

The owner's `LocalPreferences.toml` already had `providers.<name>.default_model` entries with no
code reading or writing them — leftover intent from an earlier note. The request: make
`use <provider>` (no model id) in the model REPL mode pick that provider's own default model, keep
the existing global `default_model`/`set_default_model!` as the fallback for new sessions, add an
imperative equivalent, and fail (not fall back) if the provider has no default saved.

## The Question

1. Names/shape for the per-provider get/set API?
2. Name for the imperative "switch a session to a provider's default" function?
3. Should the REPL's `default` command also *set* a provider's default, not just `use` it?
4. Where in Preferences does the per-provider default live?

## Options Considered

1. `set_default_model!(p::AbstractProvider, id::AbstractString)` / `default_model(p::AbstractProvider)` overloads of the existing global-default names (chosen) vs. new names like `set_provider_default!`.
2. `use_provider!(session, p)` / `use_provider!(p)` (chosen) vs. overloading `set_model!(session, p::AbstractProvider)` vs. a REPL-only feature with no imperative form.
3. Extend `default provider [model-id]` (chosen) vs. Julia-mode only (`set_default_model!`).
4. Reuse the provider's existing prefs table, key `default_model` (chosen, and already the shape sitting unused in the owner's `LocalPreferences.toml`) vs. a separate top-level table.

## Decision

```julia
set_default_model!(Anthropic(), "claude-sonnet-4-5")   # this provider's own default
default_model(Anthropic())                             # Model("anthropic/claude-sonnet-4-5")
use_provider!(Anthropic())                              # active session -> that default
use_provider!(s, Anthropic())                           # a specific session
```

```
model> use anthropic              # = use_provider!(active_session(), Anthropic())
model> default anthropic          # show anthropic's saved default (or "none")
model> default anthropic claude-opus-4-5   # save it
model> default anthropic/claude-sonnet-4-5 # unchanged: sets the *global* default (has '/')
```

Preferences: `[JAIL.providers.anthropic] default_model = "claude-sonnet-5"`, alongside
`base_url`/`api_key_env`/`type`/`api`. The global fallback stays the top-level `[JAIL]
default_model = "provider/model-id"` string.

`default_model(p)` and `use_provider!` throw (no silent fallback to the global default) when
nothing is saved for `p`; an `OpenAICompatible` provider must be registered first, same rule as
`configure_provider!`.

## Consequences

- `use` and `default` in the model REPL mode both take either a bare provider name or a
  `provider/model` string, disambiguated on whether the argument contains `/`.
- Tab completion after `default <provider> ` now completes model ids from the in-process model
  cache (`n == 3 && cmd == "default"`), mirroring `use provider/`.

## Revisit Trigger

Users wanting `default_model(p)` to fall back to the global default instead of throwing, or
wanting `use_provider!` to auto-pick the provider's first listed model when none is saved.
