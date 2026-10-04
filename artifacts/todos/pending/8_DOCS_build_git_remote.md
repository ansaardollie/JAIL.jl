# TODO: Fix the docs build failing on git remote detection

| Field | Value |
|-------|-------|
| Artifact | `8_DOCS_build_git_remote.md` |
| Category | todos |
| Subject | `DOCS` |
| Date created | 2026-10-04 |
| Area/Purpose scope | docs build |
| Related | `work_history/19_SESSION_persistence.md`, `work_history/5_DOCS_documenter_site.md` |
| Priority | medium |
| Owner | any |

## What

`julia --project=docs docs/make.jl` fails before rendering:

```
ERROR: LoadError: ArgumentError: Unable to automatically determine remote for main repo.
```

Find why Documenter can't infer the remote on branch `refactor-1` (origin set?) and fix it, e.g.
pass `repo`/`remotes` to `makedocs` in `docs/make.jl`.

## Why

The session persistence docs (sessions, REPL, Preferences pages) were updated but never built.

## Acceptance Criteria

- [ ] `julia --project=docs docs/make.jl` completes
- [ ] No new warnings from the sessions / REPL / reference pages
- [ ] Built HTML contains no owner Preference values

## Notes

- See repo memory: docs env inherits root LocalPreferences; `@example` blocks run in file-name order.
