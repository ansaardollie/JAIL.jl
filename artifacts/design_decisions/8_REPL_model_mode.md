> **Partly superseded by:** `10_SESSION_registry_and_default_session.md` (`use`/`select` now
> change only the active session; new `default`, `sessions`, `session …` commands; prompt shows
> the session name).

# Decision: Model REPL mode — commands, prompt, activation

| Field | Value |
|-------|-------|
| Artifact | `8_REPL_model_mode.md` |
| Category | design_decisions |
| Subject | `REPL` |
| Date | 2026-09-27 |
| Area/Purpose scope | REPL surface, Preferences |
| Related | `7_MODEL_interactive_selection.md`, `3_PREFERENCES_nested_layout.md` |
| Status | accepted |
| Decided by | user (commands, prompt, activation); agent (completion, error display) |

## Context

The `|` key opens the model selection mode (`:` was rejected earlier: collides with Symbol
literals). The user asked for Pkg-style keywords to list/select providers and models, built on
ReplMaker.jl.

## The Question

1. "Command set for the model REPL mode?"
2. "Prompt format for the model mode (key `|`)?"
3. "How does the REPL mode get installed?"

## Options Considered

1. **A**: `select` does both menus and direct selection (agent recommendation, rejected).
   **B**: separate `use provider/model`; `select` only opens menus (chosen).
2. `(anthropic/claude-sonnet-4-5) model> ` (chosen), `model[...]> `, `anthropic/... | `.
3. **Auto with a `repl_modes` Preference opt-out** (chosen), explicit function only, auto without
   opt-out.

## Decision

```
(anthropic/claude-sonnet-4-5) model> status | st         # selected model
(anthropic/claude-sonnet-4-5) model> providers           # providers + key status
(anthropic/claude-sonnet-4-5) model> models [provider]   # list (default: current provider)
(anthropic/claude-sonnet-4-5) model> select [provider]   # menus, same as select_model!
(anthropic/claude-sonnet-4-5) model> use openai/gpt-5    # set directly
(anthropic/claude-sonnet-4-5) model> help | ?
```

- `(no model) model> ` when no default is set.
- Installed on `using JAIL` in an interactive REPL (or via `atreplinit` if the REPL is not up),
  silently. Preference `repl_modes = false` in `[JAIL]` disables all JAIL REPL modes.

Agent-decided:

- Every command delegates to the public functions (`providers`, `list_models`, `select_model!`,
  `set_default_model!`); the REPL layer only parses and prints.
- Errors print as `ERROR: <message>` without a stack trace, like Pkg mode.
- Tab completion: commands; provider names after `models`/`select`/`use`; model ids after
  `use provider/` from models fetched earlier in this process (in-memory cache, never fetched on Tab).

## Consequences

`repl_modes` is the first non-provider Preferences key. The `}` and `&` modes will reuse the same
install hook and opt-out.

## Revisit Trigger

Users wanting to disable individual modes, or `|` conflicting with another package's REPL mode.
