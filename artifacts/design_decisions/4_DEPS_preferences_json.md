# Decision: Dependency changes for configuration and JSON

| Field | Value |
|-------|-------|
| Artifact | `4_DEPS_preferences_json.md` |
| Category | design_decisions |
| Subject | `DEPS` |
| Date | 2026-09-27 |
| Area/Purpose scope | dependencies |
| Related | `3_PREFERENCES_nested_layout.md` |
| Status | accepted |
| Decided by | user |

## Context

`Project.toml` carried `PreferenceTools` (an interactive pkg-REPL helper, not a runtime API) and
`JSON3`, which `Pkg.status()` reports as `[deprecated]`.

## The Question

"Dependency changes?" (multi-select)

## Options Considered

- Add Preferences.jl, remove PreferenceTools (chosen)
- Replace JSON3 with JSON.jl v1 (chosen)
- Keep deps as they are (rejected)

## Decision

`Pkg.rm(["PreferenceTools", "JSON3"])`, `Pkg.add(["Preferences", "JSON"])`,
`Pkg.compat("JSON", "1")`, `Pkg.compat("Preferences", "1.4")`. Resolved: JSON v1.9.0,
Preferences v1.6.0. HTTP v2.8.0 and ReplMaker stay.

## Consequences

JSON parsing/writing goes through `JSON.parse` / `JSON.json`, only inside the provider layer.

## Revisit Trigger

JSON.jl v1 missing something the provider layer needs (e.g. typed struct parsing performance).
