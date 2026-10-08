# Preferences `allowed_skills` / `disallowed_skills` filter skills everywhere

| Field | Value |
|-------|-------|
| Artifact | `44_HARNESS_allowed_disallowed_skills.md` |
| Category | work_history |
| Subject | `HARNESS` |
| Date | 2026-10-08 |
| Area/Purpose scope | skills discovery, Preferences, docs |
| Related | `43_TOOLS_generated_text_files.md`, `design_decisions/48_HARNESS_allowed_disallowed_skills.md`, `design_decisions/46_HARNESS_agent_mode_agents_and_skills.md`, `todos/pending/12_HARNESS_live_checks_and_gates.md` |

## Scope of This Unit of Work

Follows `43_...` (commit `eeb3f7f`). Owner asked for two mutually exclusive top-level Preference
lists that whitelist or blacklist skills in agent mode.

## What Changed

| File | Change |
|-------|--------|
| `src/harness/discovery.jl` | `skills()` filters by `_skill_filter()`; new `_skill_filter()`; docstring paragraph |
| `docs/src/guide/providers.md` | two rows in the Preferences keys table |
| `docs/src/guide/agents.md` | Skills section: paragraph and TOML example |
| `examples/LocalPreferences.toml` | both keys, commented out, with a one-line comment each |
| `examples/agents.jl` | section 9 (set each Preference, show the filtered `skills()`, `run_skill!` refused); header note; `finally` restores both Preferences |
| `docs/make.jl` | both keys added to the `__clear__` list |
| `artifacts/design_decisions/48_HARNESS_allowed_disallowed_skills.md` | new decision |

## Design Decisions Made

`design_decisions/48_HARNESS_allowed_disallowed_skills.md`. Owner chose: filter applies everywhere
(`skills()`, model catalogue, `/name`, `run_skill!`, `|` mode, `edit_skill`); exact name match;
warn once and `allowed_skills` wins when both are set. Agent chose: top-level keys, no Julia
setter. Rejected: agent-mode-only filter, catalogue-only filter, error on both set, glob patterns.

## Verification

REPL, Preferences saved first and restored after (`allowed_skills` and `disallowed_skills` both
`nothing` again, `skills()` back to 10):
```
all: 10 ["artifact-authoring", "capability-scan", "design-decision-record", "housekeeping", "implementation-planning"]
disallowed: 9 false
allowed: ["housekeeping"]
both: ["housekeeping"] | ┌ Warning: JAIL: the Preferences `allowed_skills` and `disallowed_skills` are both set; `allowed_skills` is used
bad: ArgumentError("Preference `allowed_skills` must be a list of strings, got \"housekeeping\"")
```

`examples/agents.jl` run end to end with `include` (stderr discarded). Section 9 output:
```
filter(... [k.name for k = skills()]) = ["review-file"]              # disallowed_skills = ["style"]
[k.name for k = skills()] = ["style"]                                # allowed_skills = ["style"]
misuse: ArgumentError: no user-invocable skill named "review-file" (found: style)
```
(Section 2 of the same run, before any filter, printed `["review-file", "style"]`.)
Preferences afterwards: `allowed_skills` nothing, `disallowed_skills` nothing, `storage_dir` nothing.

Docs build: `julia --project=docs docs/make.jl > /tmp/jail_docs.log 2>&1` gave `exit=0`, and
`grep -ciE "warn|error"` on the log gave `0`. This also loads `using JAIL` after the change.

Not verified: the `&` REPL `/skills` listing and tab completion on a real terminal (todo 12 covers
that check and stays open).

## Known Limitations

- A disallowed skill can't be opened with `edit_skill`; its file has to be edited by hand.
- Names in either list that match no skill are ignored silently.
- The conflict warning shows once per process (`_warn_ref_once`), not once per session.
- `allowed_skills = []` hides every skill (an empty list is a list, not unset).
- The `&` mode's "skills are filtered out" message isn't shown; a filtered `/name` reports "no
  user-invocable skill named ...".

## Todos

- Completed: none.
- Created: none. Pending `12_HARNESS_live_checks_and_gates.md` still applies; the real-terminal
  check of `/skills` now also covers the filter.

## Next Steps

- `todos/pending/12_HARNESS_live_checks_and_gates.md`: include the filtered `/skills` listing in
  the real-terminal check.
- Owner: decide whether `edit_skill` should still open disallowed skills (see decision 48's
  Consequences and Revisit Trigger).
