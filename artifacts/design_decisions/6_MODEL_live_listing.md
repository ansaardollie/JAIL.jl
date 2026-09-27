# Decision: How available models are discovered

| Field | Value |
|-------|-------|
| Artifact | `6_MODEL_live_listing.md` |
| Category | design_decisions |
| Subject | `MODEL` |
| Date | 2026-09-27 |
| Area/Purpose scope | provider layer, public API |
| Related | `2_MODEL_parametric_model_string_form.md`, `../provider_reviews/1_MODELS_list_models.md` |
| Status | accepted |
| Decided by | user (live listing, OK to fetch docs); agent (Google filter) |

## Context

Model selection needs a list to pick from. Local docs covered only OpenAI `GET /models`.

## The Question

"How should available models be discovered?"

## Options Considered

- **Live API listing** (chosen): always current; needs key and network.
- **Static curated list**: rejected, goes stale.
- **Live with static fallback**: rejected, same staleness plus two code paths.

## Decision

`list_models(p)` calls each provider's list endpoint and follows pagination. Endpoint details are
in `artifacts/provider_reviews/1_MODELS_list_models.md`. Google results are filtered to models
whose `supportedGenerationMethods` contains `"generateContent"` (agent choice, UNVERIFIED as a
proxy for Interactions support).

Results are sorted by id in natural order (user request, 2026-09-27): case-insensitive
alphabetical, with digit runs compared numerically so versions in a family ascend
(`claude-opus-4-9` < `claude-opus-4-10`, `gpt-5` < `gpt-10`). This replaces the provider's own
order (e.g. Anthropic's newest-first). `select_model!` and the `|` mode inherit it through
`list_models`. Implemented by `_natural_less` in `src/configuration.jl`.

## Revisit Trigger

Google exposing an Interactions-specific capability flag, or the filter hiding a model listed in
`gemini-docs-069-interactions-overview.md#L351-L376`.
