---
name: provider-docs-review
description: 'Review LLM provider docs and API specs (OpenAI, OpenAI-compatible, Anthropic, Google Gemini) to determine the canonical wire-level way to implement a feature. Use before implementing or changing any provider feature in JAIL.jl: messages, multi-turn state, streaming, tool/function calling, structured output, thinking/reasoning, files, token counting, stop reasons, errors. Also use when asked "how does provider X do Y", to compare providers, or to map a feature onto the JAIL ontology.'
argument-hint: 'Feature to review, optionally with providers (e.g. "function calling for Anthropic and Google")'
---

# Provider Docs Review

Produces a verified, citation-backed account of how each provider expects a feature to be implemented over raw HTTP, and how that maps onto JAIL's provider-agnostic types.

## When to Use

- Before writing or changing request/response code for any provider.
- When a provider's behavior or field name is uncertain.
- When designing an ontology type that must cover several providers.

## Ground Rules

- **Raw HTTP is canonical, SDKs are not.** JAIL talks HTTP directly. SDK examples hide field names, casing, and defaults. Use `curl`/REST examples; if only SDK examples exist, translate them and flag the translation.
- **Multi-turn API only**: OpenAI Responses, Anthropic Messages, Google Interactions. Legacy endpoints (Chat Completions, Text Completions, generateContent) are noted only as "not canonical", except Chat Completions as the `OpenAICompatible` fallback.
- **Spec wins on shape, docs win on behavior.** Field names, types, required-ness, and enums come from the spec when it covers the endpoint. Semantics, ordering rules, limits, and caveats come from the guides. Record every conflict.
- **Cite everything** as `path#Lstart-Lend`. A claim without a citation is a guess, so mark it `UNVERIFIED`.
- **Local first.** Use `artifacts/provider_docs/`. If local docs don't cover the feature, say so and ask before fetching the official URL (Claude docs carry a `url:` front-matter field).

## Procedure

1. **Scope.** Pin down the feature and providers (default: OpenAI, Anthropic, Google, plus an OpenAI-compatible note). Split broad features ("tools") into concrete sub-features (define, call, return result, parallel calls, forced choice, streaming of arguments).
2. **Check prior work.** Search `artifacts/provider_reviews/` and `artifacts/design_decisions/` for the feature. If a review exists, only refresh what changed.
3. **Locate docs** per provider with the recipes in [provider index](./references/provider-index.md). Read the primary guide fully, not just the matched lines; caveats sit at the end.
4. **Pin the endpoint.** Method, path, required headers (auth, version, beta flags), and query params.
5. **Verify shapes in the spec.** Find the request schema, response schema, and stream event schemas. Follow `$ref`s until you reach primitives, but only for fields the feature touches. For Google, use `interactions.openapi.json`, not the legacy `api_spec.json`. Mark a field `DOCS-ONLY` only when no local spec covers it.
6. **Extract, per provider:**
   - Request: fields the feature adds, with types, required-ness, and enums.
   - Response: where the feature appears (content block, output item, part) and how to recognize it.
   - Multi-turn: how the result is fed back (replay the full history, `previous_response_id`, or interaction id) and what must be echoed verbatim (ids, signatures, thought signatures).
   - Streaming: event names, order, how partial data accumulates, and the terminal event.
   - Termination: stop/finish reasons tied to the feature.
   - Limits and gotchas: model restrictions, size caps, mutually exclusive options, beta status.
   - One minimal raw request/response JSON pair copied from the docs, which is useful as a mock-test fixture.
7. **Synthesize across providers.** Fill the concept mapping table in the [template](./assets/review-template.md): one row per semantic concept, one column per provider, plus the proposed JAIL concept. Mark provider-unique capabilities as extensions, and don't force them into the common abstraction.
8. **Recommend.** State the canonical approach per provider, the ontology types and interface functions it touches, and open questions. Anything touching public API goes to the user as a question, not a decision.
9. **Write the artifact** using the [template](./assets/review-template.md) at `artifacts/provider_reviews/X_<TAG>_<summary>.md`, following the `artifact-authoring` skill's naming and id rules. `<TAG>` is the feature topic (e.g. `TOOLS`, `STREAMING`), not the provider.

## Completion Checks

- [ ] Every provider in scope has endpoint, request, response, multi-turn, streaming, and termination sections, or an explicit "not supported" with a citation.
- [ ] Every field name is cited from the spec or marked `DOCS-ONLY` / `UNVERIFIED`.
- [ ] No SDK-only names (camelCase SDK params, helper classes) are presented as wire fields.
- [ ] Spec vs. docs conflicts are listed.
- [ ] The concept mapping table is complete and extensions are labeled.
- [ ] Open questions are listed separately from recommendations.
