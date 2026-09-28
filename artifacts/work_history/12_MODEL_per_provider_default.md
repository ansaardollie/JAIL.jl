# Per-provider default models and `use provider` / `use_provider!`

| Field | Value |
|-------|-------|
| Artifact | `12_MODEL_per_provider_default.md` |
| Category | work_history |
| Subject | `MODEL` |
| Date | 2026-09-28 |
| Area/Purpose scope | configuration, public API, REPL surface, docs |
| Related | `design_decisions/19_MODEL_per_provider_default.md`, `design_decisions/8_REPL_model_mode.md` |

## Scope of This Unit of Work

User request: let each provider have its own saved default model, so `use <provider>` (no model
id) in the model REPL mode picks it; the global `default_model`/`set_default_model!` stays the
fallback new sessions start from; `use <provider>` fails if that provider has no default saved;
and an imperative equivalent must exist too.

## What Changed

| File | Change |
|-------|--------|
| `src/configuration.jl` | new `set_default_model!(p::AbstractProvider, id::AbstractString)` and `default_model(p::AbstractProvider)`, storing/reading `providers.<name>.default_model` via the existing `_provider_prefs`/`_save_provider_prefs!` helpers; same "must be registered first" check as `configure_provider!` for `OpenAICompatible` |
| `src/session.jl` | new `use_provider!(session, p::AbstractProvider)` / `use_provider!(p::AbstractProvider)`, switching to `default_model(p)` via the existing `set_model!` |
| `src/repl/model_mode.jl` | `_cmd_use` dispatches on `occursin('/', arg)`: with a slash, unchanged (`set_model!`); without, `use_provider!(s, _provider(arg))`. `_cmd_default` takes 0–2 args: unchanged with 0 or a `provider/model` string; a bare provider name shows its saved default; `provider model-id` saves it. Help text, usage strings and tab completion (`n == 3 && cmd == "default"` completes model ids) updated |
| `src/JAIL.jl` | exports `use_provider!` |
| `docs/src/guide/{models,providers,repl}.md`, `docs/src/reference.md` | per-provider default section, Preferences key row, REPL command table row, `use_provider!` in the Sessions `@docs` block |
| `examples/model_selection.jl` | REPL transcript shows `use anthropic` / `default anthropic [model-id]`; misuse section demos `use_provider!` failing on a provider with no default |
| `examples/providers_and_models.jl` | new section 5b: `set_default_model!(Anthropic(), ...)`, `default_model(Anthropic())`, `use_provider!(Anthropic())`, and the "not saved" error |
| `artifacts/design_decisions/19_MODEL_per_provider_default.md` | records the API shape (asked via ask-questions: overload names, `use_provider!`, `default` REPL extension, storage key) |

## Verification

Interactively in the REPL (Julia 1.13.0), with the owner's real `LocalPreferences.toml` snapshotted
and restored around the mutating parts:

```julia
default_model(Anthropic())                       # Model("anthropic/claude-sonnet-5") — read the
                                                  # pre-existing providers.anthropic.default_model
s = new_session!("t1"; model = "openai/gpt-5")
use_provider!(s, Anthropic())                    # -> anthropic/claude-sonnet-5
use_provider!(Google())                          # active session -> google/gemini-3.1-flash-lite
use_provider!(OpenAICompatible("nope"))          # ERR: not registered

# temporarily cleared providers.google, confirmed:
use_provider!(Google())   # ERR: no default model is set for "google"; choose one with e.g. ...
# restored, default_model(Google()) back to Model("google/gemini-3.1-flash-lite")

_model_command("use anthropic")            # Session "t2" now uses anthropic/claude-sonnet-5
_model_command("default openai")           # Default model for openai: gpt-6-luna
_model_command("default openai gpt-6-luna")# Default model for openai saved: gpt-6-luna
_model_command("use unknownprov")          # ERROR: unknown provider "unknownprov" (known: ...)
```

`julia --project=docs docs/make.jl` builds clean (no new warnings). `git status` after cleanup
shows only the intended file changes; `LocalPreferences.toml` unchanged.

### Documentation review pass

Re-checked as a separate pass (julia-documenter mode): read every changed docstring and guide
paragraph against the source, rebuilt the docs, and inspected the rendered HTML rather than
trusting the build log alone.

- `julia --project=docs docs/make.jl`: 0 warnings before this pass, 0 after.
- Reference page: confirmed via `grep` on `docs/build/reference/index.html` that Documenter
  renders *both* methods of `set_default_model!`/`default_model` (global and per-provider) and
  the two `use_provider!` methods under one binding, as expected.
- Added a runnable misuse example to `docs/src/guide/models.md` (was prose-only, "throws" was
  asserted but not shown) — real rebuilt output:
  ```
  ArgumentError: no default model is set for "openrouter"; choose one with e.g.
  `set_default_model!(p, "<model-id>")`, or `list_models(p)` to see options
  ```
- Drift found and fixed: `examples/model_selection.jl`'s REPL transcript used `claude-sonnet-5`
  (the owner's real saved value, copied from a live REPL check) where the rest of the file
  consistently uses the illustrative `claude-sonnet-4-5` — corrected for consistency, since the
  transcript is illustrative, not a pasted real session.
- No other drift: the per-provider Preferences key row, the REPL command table rows, and the
  guide prose all matched the implementation as written.

## Gaps

- `examples/providers_and_models.jl`'s section 5b and `examples/model_selection.jl`'s misuse demo
  were not run end-to-end (both persist to the real `LocalPreferences.toml` — registering
  `lmstudio`/`openrouter`/`jail-example-misuse` — and the latter also makes live `list_models`
  calls); the underlying calls were verified directly in the REPL instead. Run them if a
  disposable Preferences project is set up for examples.
