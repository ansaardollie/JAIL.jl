# Decision: Preferences layout, library, and write semantics

| Field | Value |
|-------|-------|
| Artifact | `3_PREFERENCES_nested_layout.md` |
| Category | design_decisions |
| Subject | `PREFERENCES` |
| Date | 2026-09-27 |
| Area/Purpose scope | configuration, dependencies |
| Related | `1_PROVIDER_configurable_instances.md`, `4_DEPS_preferences_json.md` |
| Status | accepted |
| Decided by | user (layout); agent (write semantics, verified in REPL) |

## Context

Note #4: Preferences.jl over ENV so changes apply without restarting. API keys stay in ENV;
Preferences stores only the ENV var *name*.

## The Question

"Preferences layout (in the active project's LocalPreferences.toml)?" — nested vs flat.

## Options Considered

- **Nested per-provider tables** (chosen)
- **Flat keys** (`anthropic_api_key_env`): rejected, messy with several compatible endpoints.

## Decision

```toml
[JAIL]
default_model = "anthropic/claude-sonnet-4-5"

[JAIL.providers.anthropic]
api_key_env = "MY_ANTHROPIC_KEY"     # only non-default fields are stored

[JAIL.providers.lmstudio]
type = "openai_compatible"
base_url = "http://localhost:1234/v1"
api = "chat_completions"
```

Agent-decided, verified in the REPL on 2026-09-27 (Preferences v1.6.0, Julia 1.13.0):

- Read at runtime with `load_preference(uuid, key)`, never at top level or with `@load_preference`
  into a const. A hand edit of `LocalPreferences.toml` was picked up by the next `load_preference`
  call without a restart.
- `set_preferences!(uuid, "providers" => dict)` **replaces** the whole `providers` table (it does
  not deep-merge), and a `nothing` leaf writes a `__clear__` entry. So JAIL reads the full table,
  edits it, and writes it back whole, removing keys rather than writing `nothing`.
- Writes use `force = true` into the active project (the Preferences default target).
- `LocalPreferences.toml` is added to `.gitignore` in this repo.

## Consequences

- Preferences live per active project. A user who switches projects sees that project's config.
- Merging across load-path layers is left to Preferences; a write flattens the merged view into
  the active project.

## Revisit Trigger

Users wanting one global JAIL config regardless of active project, or Preferences.jl gaining a
deep-merge write.
