# TODO: Set up the test suite and port the REPL checks

| Field | Value |
|-------|-------|
| Artifact | `1_TESTS_test_suite_setup.md` |
| Category | todos |
| Subject | `TESTS` |
| Date created | 2026-09-27 |
| Area/Purpose scope | tests, package structure |
| Related | `work_history/1_PROVIDER_providers_and_model_selection.md` … `4_SESSION_registry_and_default_session.md` |
| Priority | high |
| Owner | any |

## What

1. Ask the owner where tests live: a workspace `test/Project.toml` (Julia ≥ 1.11 `[workspace]`)
   or `[extras]` + `[targets]` in `Project.toml`. Record the answer as a design decision.
2. Create `test/runtests.jl` and port the checks that were only run in the REPL:
   - provider config round trips (`configure_provider!`, `register_provider!`, reset with `nothing`)
   - `Model` parsing and errors
   - `_list_models` against doc fixtures (OpenAI, Anthropic 2 pages, Google 2 pages + filter)
   - `_natural_less` ordering
   - `_get_json` against a local `HTTP.serve!` stub (auth headers, error bodies)
   - menus via a fake `REPL.Terminals.TTYTerminal` fed a `Base.BufferStream`
   - `|` mode commands via `JAIL._model_command` and completion via `JAIL._complete_model_mode`
   - session registry: naming/suffixes, `delete_session!` rules, `_start_default_session!` with no / bad saved default

## Why

Everything has been verified only by hand. Later refactors (messages, requests) need a safety net.

## Acceptance Criteria

- [ ] Test layout decision recorded in `artifacts/design_decisions/`
- [ ] `Pkg.test()` passes
- [ ] Tests don't touch the developer's real Preferences (save and restore `LocalPreferences.toml`, or use a temp project)

## Notes

- Fixtures and exact expected outputs are pasted in the work_history artifacts listed above.
- `run-julia-code` doesn't capture stderr; errors from `_print_error` go to stderr.
- Fake terminals print "Unable to enter raw mode" warnings; that's expected.
