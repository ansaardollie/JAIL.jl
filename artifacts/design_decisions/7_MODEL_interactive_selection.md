# Decision: Interactive model selection with `select_model!`

| Field | Value |
|-------|-------|
| Artifact | `7_MODEL_interactive_selection.md` |
| Category | design_decisions |
| Subject | `MODEL` |
| Date | 2026-09-27 |
| Area/Purpose scope | public API, dependencies |
| Related | `5_API_provider_model_functions.md`, `6_MODEL_live_listing.md`, `8_REPL_model_mode.md` |
| Status | accepted |
| Decided by | user |

## Context

User asked for `select_model!()` showing a terminal menu (provider, then model). No session type
exists yet, so something has to hold the choice.

## The Question

1. "Until sessions exist, what does select_model!() / the REPL mode change?"
2. "select_model! signature and behaviour?"
3. "Which TerminalMenus?"

## Options Considered

1. **Persistent default model** (chosen) vs **in-memory current model** (rejected: global state
   the later session design would have to absorb).
2. **Proposal** (chosen) vs **throw on cancel / listing failure** (rejected).
3. **`REPL.TerminalMenus` stdlib** (chosen) vs the standalone TerminalMenus.jl package (rejected:
   merged into the stdlib, unmaintained on its own).

## Decision

```julia
select_model!()               # provider menu → model menu (live list_models)
select_model!(Anthropic())    # skip the provider menu
# returns the Model, or `nothing` on cancel (q / Ctrl-C) or listing failure (error is printed)
```

- Selection calls `set_default_model!`.
- Provider menu lists `providers()`, marking providers whose key ENV var is unset.
- Model menu marks the current default with `*` and starts the cursor on it.
- `REPL` stdlib added to `[deps]` via `Pkg.add("REPL")`.

## Consequences

When sessions land, add `select_model!(session[, provider])`; `select_model!()` stays the path for
the default model.

## Revisit Trigger

Session type design, or long model lists (OpenAI returns non-chat models too) making the menu
unusable without filtering.
