# Documenter site bootstrapped; docstrings corrected to current behavior

| Field | Value |
|-------|-------|
| Artifact | `5_DOCS_documenter_site.md` |
| Category | work_history |
| Subject | `DOCS` |
| Date | 2026-09-27 |
| Area/Purpose scope | docs |
| Related | `4_SESSION_registry_and_default_session.md`, `design_decisions/11_DOCS_page_structure.md`, `todos/pending/3_DEPS_repl_compat_bound.md` |

## Scope of This Unit of Work

Asked to document the providers / models / sessions / `|` mode work (work_history 1–4) in line
with `.github/agents/jail-developer.agent.md`. The previous unit (4) ended with messages ontology
and the ask mode as next steps; those are untouched.

## What Changed

| File | Change |
|-------|--------|
| `Project.toml` | `[workspace] projects = ["docs"]` (hand edit, the one sanctioned exception) |
| `docs/Project.toml` | via Pkg: Documenter v1.19.0, LiveServer v1.6.0, JAIL (path `.`) |
| `docs/make.jl` | writes `docs/LocalPreferences.toml` with a `[JAIL] __clear__` block before `using JAIL`, runs `makedocs`, deletes the file |
| `docs/serve.jl` | `serve(dir = "docs/build/")` |
| `docs/src/index.md`, `guide/*.md`, `reference.md` | new pages (structure per decision 11) |
| `.gitignore` | `docs/build/` |
| `src/providers/{openai,anthropic,google,openai_compatible}.jl` | docstrings: requests not implemented yet; `api` has no effect yet |
| `src/configuration.jl` | docstrings: `configure_provider!` `nothing` semantics per provider kind; `set_default_model!` / `default_model` session relationship; `list_models` Google filter named exactly |
| `src/session.jl` | `Session` docstring: name rules; `model === nothing` only for the startup session |

No behavior changed.

## Design Decisions Made

- Page structure: `design_decisions/11_DOCS_page_structure.md`.
- Agent: side-effect-free and docs-local-Preferences-writing code runs as `@example`; network /
  keyboard code (`list_models`, menus) is plain code; the `|` transcript is pasted real output
  from a local `HTTP.serve!` stub registered as `lmstudio`.
- Agent: isolate the docs build from the workspace root's `LocalPreferences.toml` with
  Preferences' `__clear__` inheritance block rather than editing or moving the root file.

## Verification

Baseline (before pages), `julia --project=docs docs/make.jl`:

```
┌ Error: 24 docstrings not included in the manual:
ERROR: LoadError: `makedocs` encountered an error [:missing_docs]
```

Final:

```
exit=0
0            # grep -cE 'Warning|Error' /tmp/jail_docs_build.log
```

Root prefs leak found and fixed: the docs env reads the root file (load path showed only
`docs/Project.toml`, but `JAIL._load_pref("default_model")` returned `"openai/gpt-5"`) and writes
`docs/LocalPreferences.toml`. With the `__clear__` block, the sessions page renders
`Session "default"  model: none`; root file still `default_model = "openai/gpt-5"`.

Package load after docstring edits: `using JAIL` → `Session("default", openai/gpt-5, 0 messages)`.

## Known Limitations

- `jd` alias fails: typo `isfle` in `~/.julia/config/requirements.jl:5` (owner's config, not
  touched). Use `julia --project=docs docs/make.jl` / `docs/serve.jl` until fixed.
- `@example` blocks run in file-name order, not `pages` order; each page must set up its own
  state (`models.md` has an `@setup` block for `openrouter`).
- `list_models` and menus are not executed in the docs.
- `REPL = "1.11.0"` compat conflicts with `julia = "1.10"` (reported; todo 3).
- No deployment (`deploydocs`) or CI.

## Todos

- Completed: none
- Created: `3_DEPS_repl_compat_bound.md`

## Next Steps

1. Owner fixes `requirements.jl` so `jd docs/make.jl` works.
2. Resolve todo 3 (REPL compat vs Julia 1.10).
3. Keep docs in step: new exports → `reference.md`; new features → guide page; rebuild to 0 warnings.
4. Messages ontology design (unchanged from work_history 4).
