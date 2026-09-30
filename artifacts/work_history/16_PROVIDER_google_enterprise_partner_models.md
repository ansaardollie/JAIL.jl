# GoogleEnterprise: partner (Model Garden) models in list_models + Model equality bugfix

| Field | Value |
|-------|-------|
| Artifact | `16_PROVIDER_google_enterprise_partner_models.md` |
| Category | work_history |
| Subject | `PROVIDER` |
| Date | 2026-09-29 |
| Area/Purpose scope | provider config, core ontology |
| Related | `work_history/15_PROVIDER_google_enterprise_list_models.md`, `design_decisions/20_PROVIDER_google_enterprise_vertex_ai.md` |

## Scope of This Unit of Work

The owner found (via curl) that `GET /v1beta1/publishers/*/models` (wildcard publisher) returns
Vertex AI's partner/Model Garden catalog too (Anthropic, Mistral, xAI, ...), not just Google's own
models, and asked for these to be selectable through `list_models`/`Model` as well.

## What Changed

| File | Change |
|-------|--------|
| `src/providers/google.jl` | `_list_models(p::GoogleEnterprise, ...)` now hits `publishers/*/models` instead of `publishers/google/models`. New `_publisher_model_id(name)` turns `"publishers/{publisher}/models/{id}"` into a `Model` id: bare for `google` (backward compatible with ids already saved without a prefix), `"{publisher}/{id}"` otherwise (e.g. `"anthropic/claude-opus-4-5"`) — the same compounding `OpenAICompatible` already uses for `"openrouter/openai/gpt-5"` |
| `src/ontology/models.jl` | New `Base.:(==)(a::Model, b::Model) = a.provider == b.provider && a.id == b.id`. Found while testing the above: `Model` had no explicit `==`, so it fell back to the default egal (`===`)-based fallback, which recurses into each field's own `===` rather than dispatching to a provider's custom `==`. That silently broke `Model{GoogleEnterprise}` equality specifically, because `GoogleEnterprise`'s internal token-cache `Base.RefValue` is mutable (identity-based `===`), even though `GoogleEnterprise`'s own `==` (added in stage 1) correctly ignores it. Every other provider happened to work by accident, since their fields are all plain immutable value types |
| `src/configuration.jl` | `list_models` docstring updated: partner models are prefixed by publisher (Google's own stay bare) |

## Verification

Live, against the real `dhd-prima` project (read-only — no Preferences touched):

```julia
models = list_models(JAIL.GoogleEnterprise())
length(models)   # 49 (was 27 for google-only)
# google_enterprise/anthropic/claude-opus-4-5, google_enterprise/xai/grok-4.6,
# google_enterprise/mistralai/mistral-medium-3, ... alongside the bare google_enterprise/gemini-*

m = Model("google_enterprise/anthropic/claude-opus-4-5")
m == Model(JAIL.GoogleEnterprise(), "anthropic/claude-opus-4-5")   # true (was false before the == fix)
Model(Anthropic(), "claude-sonnet-4-5") == Model("anthropic/claude-sonnet-4-5")  # true (unaffected, regression-checked)
```

## Gaps / Open Question — flagged, not resolved here

**Whether a partner-model id can actually be *used* in a `chat!` call is unverified.**
`_request_body` still sends `body["model"] = req.model.id` unchanged (e.g. `"gemini-2.5-flash"`
or now `"anthropic/claude-opus-4-5"`) for both `Google` and `GoogleEnterprise`. There is no
provider documentation for the Interactions API's `model` field on Vertex AI (only the Developer
API's, which takes a bare id), and no live text-chat call against `GoogleEnterprise` has been
made yet at all (per the stage-1 decision). It is plausible Vertex's Interactions endpoint instead
expects a fully-qualified resource reference (`"publishers/{publisher}/models/{id}"`, matching the
pattern used everywhere else in the Vertex REST API — `generateContent`'s `model` path parameter,
`publisherModelTemplate`), especially for non-Google publishers. This was deliberately left
unchanged rather than guessed, per the "don't add a wire-format field without citing a doc" rule —
worth a live single-turn `chat!` test (one Google model, one partner model) before relying on
partner-model selection for anything beyond listing.
