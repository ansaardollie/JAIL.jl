# TODO: Verify `|` mode and menus in a real terminal, plus live listing

| Field | Value |
|-------|-------|
| Artifact | `2_REPL_real_terminal_check.md` |
| Category | todos |
| Subject | `REPL` |
| Date created | 2026-09-27 |
| Area/Purpose scope | REPL surface, providers |
| Related | `work_history/2_REPL_model_selection_mode.md`, `work_history/4_SESSION_registry_and_default_session.md` |
| Priority | normal |
| Owner | any (needs the owner at a keyboard) |

## What

In a plain terminal `julia` (not the agent's tool REPL):

1. `using JAIL`, press `|` at an empty prompt, and check that the prompt shows `(default: <model>) model> `.
2. Run `sessions`, `session new x`, `session use default`, `use …`, `default …`, and `select`
   (arrow keys, Enter, `q`), then use Tab completion and exit with backspace.
3. `select_model!()` and `select_model!(Anthropic())` from `julia>`.
4. With the owner's approval, set `LIVE = true` in `examples/providers_and_models.jl` and run it.

## Why

The agent could only drive menus with a fake terminal, and has never made a live provider call.
The Google `generateContent` filter and the model-list shapes are unconfirmed against real APIs.

## Acceptance Criteria

- [ ] All commands behave as in `work_history/4_SESSION_registry_and_default_session.md`
- [ ] Menus render, scroll (pagesize 15) and cancel cleanly
- [ ] `list_models` returns non-empty lists for OpenAI, Anthropic and Google

## Notes

API keys are already set in the owner's ENV (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`).
