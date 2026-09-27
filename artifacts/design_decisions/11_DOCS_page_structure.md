# Decision: Documentation page structure

| Field | Value |
|-------|-------|
| Artifact | `11_DOCS_page_structure.md` |
| Category | design_decisions |
| Subject | `DOCS` |
| Date | 2026-09-27 |
| Area/Purpose scope | docs |
| Related | `work_history/5_DOCS_documenter_site.md` |
| Status | accepted |
| Decided by | user |

## Context

No `docs/` existed. Surface at the time: one module, 24 exports, 3 example scripts, the `|` mode.

## The Question

"Documentation page structure?"

## Options Considered

- **A** — index + guide (concepts, providers, models, sessions, repl) + one reference page (chosen)
- **B** — index + single guide page + reference (rejected)
- **C** — index + reference only (rejected)

## Decision

```
docs/src/index.md
docs/src/guide/{concepts,providers,models,sessions,repl}.md
docs/src/reference.md        # @docs blocks grouped: Providers, Models, Sessions
```

Each guide page mirrors an `examples/*.jl` script where one exists.

## Consequences

New features get a guide page (or a section) plus entries in `reference.md`. When the messages,
ask mode and tools land, the guide will likely need a "Requests" or "Conversations" page.

## Revisit Trigger

`reference.md` growing past one screenful per section, or a submodule being introduced (each
submodule then needs its own reference page and `makedocs(modules=...)` entry).
