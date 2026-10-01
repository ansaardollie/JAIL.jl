# GoogleEnterprise: generateContent by default, partner models reverted, docs

| Field | Value |
|-------|-------|
| Artifact | `17_PROVIDER_google_enterprise_generate_content.md` |
| Category | work_history |
| Subject | `PROVIDER` |
| Date | 2026-10-01 |
| Area/Purpose scope | provider wire format, configuration, docs build, docs |
| Related | `design_decisions/21_PROVIDER_google_enterprise_generate_content.md`, `design_decisions/20_PROVIDER_google_enterprise_vertex_ai.md`, `work_history/16_PROVIDER_google_enterprise_partner_models.md` |

## Scope of This Unit of Work

Picks up from work history 16 and commit `f022d64`. The owner reported two problems from live use:

1. The Interactions API on Vertex AI does not handle function-call results properly. Make
   generateContent the default for `GoogleEnterprise` and keep Interactions as an opt-in setting.
2. Partner (Model Garden) models don't support Interactions and each may use a different
   endpoint. Revert partner-model support.

The docs were then brought up to date (julia-documenter pass).

## What Changed

| File | Change |
|-------|--------|
| `src/providers/google.jl` | `GoogleEnterprise` gains `api::Symbol` (`:generate_content` default, `:interactions`), validated in a new inner constructor; `==` compares it; new `show` that hides the token cache. The Interactions code moved behind an `_InteractionsAPI` wire tag (`Google` always uses it); new `_GenerateContentAPI` wire: request URL with the model id (`:generateContent`, or `:streamGenerateContent?alt=sse`), `contents`/`systemInstruction`/`generationConfig.maxOutputTokens`/`tools[].functionDeclarations` with `parametersJsonSchema`, `functionResponse.response` as `output`/`error`, reply and SSE-stream parsing. Made-up call ids (`jail_call_…`) when the model omits `FunctionCall.id`, never sent back. `thoughtSignature`s kept in `_THOUGHT_SIGNATURES` by call id and replayed. `_supports_chaining`/`_has_store_field` are per instance (true only for `:interactions`). `list_models` back to `publishers/google/models`; `_publisher_model_id` removed |
| `src/ontology/requests.jl` | New `_request_url(p, req)` that falls back to `_request_url(p)`; the generateContent URL depends on the model and on streaming |
| `src/chat.jl` | `_send` calls `_request_url(p, req)`; `chat!` docstring mentions `GoogleEnterprise` with `api = :interactions` |
| `src/configuration.jl` | `api` persisted (only when not the default), configurable, resettable with `nothing`. **Bug fix (all providers):** `configure_provider!` rewrote the whole provider table and dropped a saved per-provider `default_model`; it now keeps it. Docstrings updated |
| `src/ontology/providers.jl` | `AbstractProvider` docstring mentions `GoogleEnterprise` and its project/location config |
| `docs/make.jl` | Preferences isolation fixed, see Note below |
| `docs/src/reference.md` | `GoogleEnterprise` added to the Providers `@docs` block (the build was failing without it) |
| `docs/src/guide/providers.md` | New "Gemini on Google Cloud (Vertex AI)" section: required project/location, credential lookup order, the `api` table, no partner models, the `set_default_model!` caveat. Four new Preferences-key rows. Stale "`api` only matters once requests are implemented" line removed |
| `docs/src/guide/{concepts,chat,models}.md`, `docs/src/index.md` | `GoogleEnterprise` added; concepts states the generateContent default as a second exception to the multi-turn rule, alongside `OpenAICompatible` |
| `examples/providers_and_models.jl` | Header updated; `api` switch, reset and invalid-value error shown; variable renamed to avoid a soft-scope warning |
| `artifacts/design_decisions/21_…` | New: default wire, opt-in switch shape, partner revert, keep `Model ==` |
| `artifacts/design_decisions/20_…`, `artifacts/work_history/16_…` | Marked superseded in part / reverted |

## Decisions

Recorded in `design_decisions/21_PROVIDER_google_enterprise_generate_content.md`, asked via
ask-questions:

- Switch shape: an `api` field plus `providers.google_enterprise.api`, mirroring `OpenAICompatible`.
  Rejected: a separate or global Preferences key.
- Partner models: reverted to Google's own catalog. Rejected: keep listing them, since they'd be
  selectable but unusable.
- Keep the `==(::Model, ::Model)` fix from work history 16. Rejected: revert it with partner models.
- Agent-decided: generateContent uses Vertex `v1` (the documented version in
  `ai-platform-spec.json`); Interactions stays on `v1beta1`. Tool schemas use
  `parametersJsonSchema` because JAIL emits plain JSON Schema that the OpenAPI-subset
  `parameters` field doesn't accept.

## Verification

Offline request body for a tool round (made-up id omitted, schema under `parametersJsonSchema`):

```
https://aiplatform.googleapis.com/v1/projects/dhd-prima/locations/global/publishers/google/models/gemini-3.1-flash-lite:generateContent
https://aiplatform.googleapis.com/v1/projects/dhd-prima/locations/global/publishers/google/models/gemini-3.1-flash-lite:streamGenerateContent?alt=sse
https://aiplatform.googleapis.com/v1beta1/projects/dhd-prima/locations/global/interactions
"functionCall": {"args": {"x": 41}, "name": "add_one"}          # no id
"functionResponse": {"name": "add_one", "response": {"output": "42"}}
"functionDeclarations": [{"name": "add_one", "parametersJsonSchema": {...}}]
```

Live, against `dhd-prima`, `location = "global"` (owner approved live calls):

```
# gemini-3.1-flash-lite, two text turns (second replays the full history)
string(r1) = "pong"   r1.stop_reason = :end_turn   r1.usage = Usage(10 in, 1 out)
string(r2) = "Pong"   r2.stop_reason = :end_turn   length(s.messages) = 4

# gemini-3.1-flash-lite, tool round trip
AssistantMessage => (AbstractContentPart[ToolCall(secret_number(name = "ansaar"))], :tool_use)
ToolResultMessage => ToolResult[ToolResult(secret_number "7331")]
AssistantMessage => (AbstractContentPart[TextPart("The secret number for ansaar is 7331.")], :end_turn)

# gemini-3.1-flash-lite, streamed text then streamed tool round
1, 2, 3, 4, 5
→ secret_number(name = "ansaar")
← 7331
The secret number for ansaar is 7331.

# gemini-3.8-flash: server sends call ids and a thought signature; replaying them works
stream=false: The secret number for ansaar is 7331. | stop=end_turn | call ids=["call_324862"] | signed=1
stream=true:  The secret number for ansaar is 7331. | stop=end_turn | call ids=["call_2619682"] | signed=1

# opt-in Interactions path still works, with chaining
string(r1) = "pong"   string(r2) = "pong"   _chain_point(...) !== nothing = true
```

Preferences round trip and the `configure_provider!` fix (providers table saved and restored):

```
JAIL._provider_prefs("google_enterprise") = Dict("api" => "interactions", "project" => "dhd-prima", "default_model" => "gemini-3.1-flash-lite", "location" => "global")
JAIL._provider_prefs("anthropic") = Dict("default_model" => "claude-sonnet-5", "api_key_env" => "X_KEY")
JAIL._load_pref("providers") == snap = true
length(ms) = 27   any(m -> occursin('/', m.id), ms) = false     # listing reverted
```

`examples/providers_and_models.jl` ran top to bottom with `LIVE = false`; Preferences restored
(`restored: true`). Not run: its `LIVE` section.

Docs build (`julia --project=docs docs/make.jl`): before, it failed with 3 errors
(`GoogleEnterprise` not in any `@docs` block); after, exit 0 and 0 warnings. No built page
contains `dhd-prima`, and the `GoogleEnterprise()` example throws as the page says.

Load check before committing (fresh REPL):

```
p = GoogleEnterprise(project = "dhd-prima", location = "global")
JAIL._supports_chaining(p) = false
[JAIL.provider_name(x) for x = providers()] = ["openai", "anthropic", "google", "google_enterprise"]
```

## Note

**Docs build was showing the owner's Preferences.** In a workspace, the `docs` project also reads
the root `LocalPreferences.toml`. The `__clear__` block in `make.jl` only masks a key until it is
written: Preferences.jl removes the key from `__clear__` on write
(`process_sentinel_values!`), so after any example saved a provider setting, the owner's root
`providers` table merged back in. The built docs showed `project = "dhd-prima"` and
`GoogleEnterprise()` didn't throw. First attempt (setting `Base.ACTIVE_PROJECT` to a temp copy of
`docs/Project.toml`) broke loading Documenter (no manifest). Fix: after `using JAIL`, `make.jl`
puts a scratch project with JAIL only in `[extras]` first on `LOAD_PATH`, so JAIL's Preferences
are read and written there. The root `LocalPreferences.toml` was never written to.

The owner's `LocalPreferences.toml` holds `confirm_tools = false` and
`default_model = "google_enterprise/gemini-3.8-flash"`, which this session did not set; left as is.

## Limitations

- **Bug, not fixed (code, found while documenting):** `set_default_model!(GoogleEnterprise(...), id)`
  before `project`/`location` are saved writes a `google_enterprise` table with only
  `default_model`, after which `providers()` throws (and so does the REPL's provider listing).
  The docs warn about it. Todo `6_PROVIDER_google_enterprise_partial_prefs.md`.
- `jail-developer.agent.md` principle 4 still says "Google Interactions (not generateContent)" and
  names only `OpenAICompatible` as an exception. Todo `7_PROVIDER_update_principle_4.md`.
- Thought signatures live only in process memory; lost if sessions are ever persisted.
- Regional locations (not `global`) not tested live. No automated tests (todo 1).
- Vertex AI partner models are unsupported by decision.

## Next Steps

1. Fix todo 6 (small, in `configuration.jl` / `providers()`).
2. Owner: update principle 4 in `.github/agents/jail-developer.agent.md` (todo 7).
3. One live check with a regional `location` such as `us-central1`.
4. Todo 1 (test suite): include generateContent fixtures from the verification above.
