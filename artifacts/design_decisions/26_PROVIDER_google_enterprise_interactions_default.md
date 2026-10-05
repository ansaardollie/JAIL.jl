# Decision: GoogleEnterprise defaults to the Interactions API again

| Field | Value |
|-------|-------|
| Artifact | `26_PROVIDER_google_enterprise_interactions_default.md` |
| Category | design_decisions |
| Subject | `PROVIDER` |
| Date | 2026-10-05 |
| Area/Purpose scope | provider config, wire format, Preferences |
| Related | `21_PROVIDER_google_enterprise_generate_content.md` (default superseded), `20_PROVIDER_google_enterprise_vertex_ai.md` |
| Status | accepted |
| Decided by | user |

## Context

Decision 21 made `:generate_content` the default because "the Interactions API on Vertex AI does
not handle function-call results properly". Comparing JAIL with mitmproxy captures of the Python
google-genai SDK (`vault/GoogleGenAI_Requests/flows/flows-interactions_2.har`) showed that the SDK
sends `function_result.result` as a list of TextContent items, while JAIL sent a plain string.
The spec allows both (interactions.openapi.json FunctionResultStep #L5239-L5300) but its example
uses the list.

A/B run live (dhd-prima, `global`, `gemini-3.1-flash-lite`, a tool returning 22°C):

| `result` form | Runs | Model answer | 2nd-request input tokens |
|---|---|---|---|
| plain string | 6 | 9–11°C every time (tool output ignored) | 229 (result ≈ 2 tokens) |
| `[{"type": "text", "text": …}]` | 7+ | 22°C every time | 237 |

So the string form was the cause. It is fixed for both `Google` and `GoogleEnterprise`.

Also found: on Vertex, Interactions rejects Gemini 2.5 models (HTTP 400 "Unsupported model
interaction: gemini-2.5-pro" / "gemini-2.5-flash"), and `gemini-3.1-flash-lite` in `europe-west1`
returned HTTP 500 (works at `global`).

## The Question

"The tool-result fix is confirmed. Do you still want GoogleEnterprise to default to the
Interactions API?", with the model/location limits stated.

## Options Considered

- Flip the default to `:interactions` (chosen). The owner had asked for this up front if the fix
  was confirmed.
- Keep `:generate_content` default (rejected): the reason for it is gone; Interactions gives
  server-side chaining like `Google`.

## Decision

`GoogleEnterprise(; api = :interactions)` is the default. `providers.google_enterprise.api` is
written only when it is `"generate_content"`; `configure_provider!(GoogleEnterprise(); api = nothing)`
returns to `:interactions`.

## Consequences

- Saved configs with no `api` key move to Interactions. Gemini 2.5 models or unsupported
  locations then fail until `api = "generate_content"` is saved. The owner's own
  `LocalPreferences.toml` (gemini-2.5-pro, europe-west1) is in that position.
- Decision 21's other points (wire switch shape, `parametersJsonSchema`, synthetic call ids, no
  partner models) stand. Its thought-signature table is replaced by decision 25.

## Revisit Trigger

- Vertex Interactions gains Gemini 2.5 / regional support, or loses something generateContent has.
- Reports of tool-result or chaining problems on Vertex Interactions with the list form.
