# TODO: Resolve the REPL compat bound vs `julia = "1.10"`

| Field | Value |
|-------|-------|
| Artifact | `3_DEPS_repl_compat_bound.md` |
| Category | todos |
| Subject | `DEPS` |
| Date created | 2026-09-27 |
| Area/Purpose scope | dependencies |
| Related | `work_history/5_DOCS_documenter_site.md`, `design_decisions/7_MODEL_interactive_selection.md` |
| Priority | normal |
| Owner | any (decision for the owner) |

## What

`Project.toml` has `REPL = "1.11.0"` (written by `Pkg.add("REPL")` on Julia 1.13) alongside
`julia = "1.10"`. REPL is a stdlib versioned with Julia, so the package can't resolve on 1.10.
Either raise `julia` to `"1.11"`, or widen the REPL bound (e.g. `Pkg.compat("REPL", "1.10, 1.11")`
or remove it) — ask the owner which.

## Why

`src/select.jl` `_menu_terminal()` deliberately supports pre-1.11 `TerminalMenus.terminal`,
which is pointless if 1.10 can't install the package.

## Acceptance Criteria

- [ ] Owner's choice recorded (design decision or note in `4_DEPS_preferences_json.md` follow-up)
- [ ] `Pkg.compat` applied via Pkg, not by hand
- [ ] `Pkg.resolve()` succeeds

## Notes

`Markdown = "1.11.0"` (added for the chat mode, same `Pkg.add` behaviour) has the same problem
and should get the same treatment.

If `julia` is raised to 1.11, `_menu_terminal()` can be reduced to `TerminalMenus.default_terminal()`.
