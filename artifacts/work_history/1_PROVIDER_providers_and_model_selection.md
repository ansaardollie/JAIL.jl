# Package skeleton, Preferences layer, providers and model selection

| Field | Value |
|-------|-------|
| Artifact | `1_PROVIDER_providers_and_model_selection.md` |
| Category | work_history |
| Subject | `PROVIDER` |
| Date | 2026-09-27 |
| Area/Purpose scope | core ontology, configuration, public API |
| Related | `design_decisions/1_PROVIDER_configurable_instances.md`, `2_MODEL_parametric_model_string_form.md`, `3_PREFERENCES_nested_layout.md`, `4_DEPS_preferences_json.md`, `5_API_provider_model_functions.md`, `6_MODEL_live_listing.md`, `provider_reviews/1_MODELS_list_models.md` |

## Scope of This Unit of Work

First implementation session of the rewrite (`src/JAIL.jl` was an empty module). Asked to go
slowly and cover only package structure, Preferences, providers, and model selection.

## What Changed

| File | Change |
|-------|--------|
| `Project.toml` | via Pkg: removed PreferenceTools, JSON3; added Preferences (compat 1.4), JSON (compat 1) |
| `.gitignore` | ignore `LocalPreferences.toml` |
| `src/JAIL.jl` | module, imports, exports, include order |
| `src/preferences.jl` | `_load_pref`, `_save_pref!`, `_delete_pref!`, `_provider_prefs`, `_save_provider_prefs!` (read-modify-write of the whole `providers` table) |
| `src/ontology/providers.jl` | `AbstractProvider`, `AbstractOpenAIProvider`; stubs `provider_name`, `default_base_url`, `default_api_key_env`, `_auth_headers`, `_list_models`; `_resolve_first_party`, `_normalize_url`, `_check_env_name`, `_api_key` |
| `src/ontology/models.jl` | `AbstractModel`, `Model{P}`, `Model("provider/id")`, `print`/`show` |
| `src/http.jl` | `_get_json` (HTTP.jl v2, `status_exception=false`), `_api_error` (`error.message`) |
| `src/providers/openai.jl` | `OpenAI`; shared `AbstractOpenAIProvider` bearer auth and `GET /models` |
| `src/providers/openai_compatible.jl` | `OpenAICompatible` (name, base_url, api_key_env, api), load-by-name constructor, `show`, name validation |
| `src/providers/anthropic.jl` | `Anthropic`, `anthropic_version`, `x-api-key` auth, paginated `GET /v1/models` |
| `src/providers/google.jl` | `Google`, `api_version`, `x-goog-api-key` auth, paginated `GET /v1beta/models` filtered to `generateContent` |
| `src/configuration.jl` | `_provider(name)`, `_to_prefs`, `_with`, `_settings`; public `configure_provider!`, `register_provider!`, `providers`, `set_default_model!`, `default_model`, `list_models` |
| `examples/providers_and_models.jl` | user-facing walkthrough; live section behind `const LIVE = false` |

## Design Decisions Made

See the six `design_decisions` artifacts in Related. Agent-level extras:
`default_base_url` instead of `base_url(::Type)` to avoid kwarg shadowing in constructors;
`_list_models(p, fetch)` takes the fetcher so parsing is testable without HTTP.

## Verification

REPL, Julia 1.13.0, 2026-09-27:

- Preferences: nested set/replace/`__clear__` behavior and runtime pickup of hand edits (see `3_PREFERENCES_nested_layout.md`).
- `configure_provider!` / `register_provider!` round trip; `LocalPreferences.toml` contained only non-default fields; reset with `nothing` removed the `anthropic` table.
- Doc-fixture parsing: OpenAI → `[Model("openai/model-id-0"), Model("openai/model-id-1")]`; Anthropic two pages with `after_id = "claude-opus-5"` on the second call; Google two pages with `pageToken = "tok2"`, embedding model filtered out.
- Local `HTTP.serve!` stub: `Authorization: Bearer <key>` sent when `api_key_env` set, no auth header when `nothing`; Anthropic sent `X-Api-Key` + `Anthropic-Version: 2023-06-01`, 401 surfaced as `anthropic API error (HTTP 401): invalid x-api-key`.
- `examples/providers_and_models.jl` ran top to bottom in a fresh REPL with `LIVE = false`.

Not verified: any live provider call.

## Known Limitations

- No test suite yet (`test/` does not exist); verification was REPL-only.
- Errors are plain `ArgumentError`/`ErrorException`; no JAIL error types.
- No request timeouts beyond HTTP.jl defaults (30 s connect); not configurable.
- Google filter is an UNVERIFIED proxy for Interactions support.
- `Model` drops listing metadata. No `unregister_provider!`, no way to clear the default model.
- Provider error messages use the lowercase provider name (`anthropic API error`).

## Todos

- Completed: none
- Created: none

## Next Steps

1. Decide test-suite layout (workspace `test/Project.toml` vs `[extras]`), then port the REPL fixture checks into tests.
2. Run `LIVE = true` in the example against real providers (with the owner's go-ahead).
3. Design the session type (name, shape) and messages ontology.
