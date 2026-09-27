# Provider Index

All paths are relative to the repository root. Line numbers are as of the 2026-09-26 snapshot, so re-grep if a spec is replaced.

## OpenAI (`artifacts/provider_docs/openapi/`)

| Item | Detail |
|------|--------|
| Spec | `api_spec.yaml`, OpenAPI 3.1, ~3.8 MB. **Never read whole; grep.** |
| Canonical endpoint | `POST /responses` (server `https://api.openai.com/v1`) |
| Fallback (OpenAICompatible only) | `POST /chat/completions` |
| Docs | `core-concepts/openai-core-concepts-NN-<topic>-YYYYMMDD.md`, `tool-guides/openai-tool-guides-NN-<topic>-YYYYMMDD.md` |
| Key docs | 01 responses-api (migration + concepts), 02 conversation-state, 04 streaming, 10 compaction, 11 counting-tokens; tools: 01 using-tools, 02 function-calling |
| Known gaps | No local guides for structured outputs, reasoning, or vision. Use spec plus ask before fetching. |

Recipes:

```bash
# paths (2-space indent)
grep -nE '^  /responses' artifacts/provider_docs/openapi/api_spec.yaml
# schemas live under components/schemas at 4-space indent (e.g. CreateResponse, ResponseStreamEvent, FunctionTool)
grep -nE '^    CreateResponse:' artifacts/provider_docs/openapi/api_spec.yaml
# then read a bounded window from the line number; find the next schema to bound it
awk 'NR>45451 && /^    [A-Za-z]/ {print NR": "$0; exit}' artifacts/provider_docs/openapi/api_spec.yaml
```

Beta variants (`/responses?beta=true`) exist. Prefer the non-beta path unless the feature is beta-only.

## Anthropic (`artifacts/provider_docs/anthropic/`)

| Item | Detail |
|------|--------|
| Spec | `api_spec.yaml`, OpenAPI 3.1, ~200 KB |
| Canonical endpoint | `POST /v1/messages` (host `https://api.anthropic.com`) |
| Not canonical | `/v1/complete` (Text Completions) |
| Docs | `claude-docs/claude-docs-NN-<topic>.md`; front matter has `title`, `url`, `description` |
| Key docs | 06 working-with-messages, 07 handling-stop-reasons, 13 structured-outputs, 15 streaming, 21 thinking, 23 to 29 tool use (how it works, define, handle calls, parallel, strict), 47 fine-grained tool streaming, 50 prompt caching, 54 token counting |

Recipes:

```bash
grep -nE '^  /v1/messages' artifacts/provider_docs/anthropic/api_spec.yaml
grep -nE '^    (CreateMessageParams|Message|MessageStreamEvent|Tool):' artifacts/provider_docs/anthropic/api_spec.yaml
grep -l '^title: .*<keyword>' -i artifacts/provider_docs/anthropic/claude-docs/*.md
```

Beta variants use `?beta=true` paths and `anthropic-beta` headers. Record the header value when a feature needs one.

## Google Gemini (`artifacts/provider_docs/google/`)

| Item | Detail |
|------|--------|
| Spec | `interactions.openapi.json`: OpenAPI 3.0.3, pretty-printed (~10.4k lines), uses the post-May-2026 `steps` schema. Use it for all Interactions shapes. |
| Legacy spec | `api_spec.json`: v1beta3 generateText/generateMessage only. **Ignore for JAIL.** |
| Canonical endpoint | `POST /{api_version}/interactions` with `api_version = v1beta` (host `https://generativelanguage.googleapis.com`). Body is `CreateModelInteractionParams` (required: `model`, `input`). Streaming: body `"stream": true` → `text/event-stream`. Other ops: `GET /{id}`, `DELETE /{id}`, `POST /{id}/cancel` |
| Auth | `x-goog-api-key` header (or OAuth bearer); see `components.securitySchemes.googleGenAIAuth` |
| Multi-turn | `previous_interaction_id` (server-side state; the spec does not say whether the prior turn must have `store: true`, so check doc 060/069), or replay history as a `Step` list in `input` |
| Not canonical | `models/{model}:generateContent`; the whole Agents/Environments/Triggers/Webhooks/Credentials surface in the same spec is out of scope unless asked |
| Docs | `gemini-docs/gemini-docs-NNN-<topic>.md` |
| Key docs | 069 interactions-overview, 091 migrate-to-interactions, 092 interactions-breaking-changes-may-2026, 027 text-generation, 033/057 thinking, 034 thought-signatures, 035 structured-output, 036 function-calling, 046/059 tools, 060 session-management, 070 streaming, 071 background-execution, 076 tokens, 096 api-errors |

Recipes:

```bash
# path and schemas (paths at 4-space indent, schemas at 6-space indent)
grep -n '"/{api_version}/interactions' artifacts/provider_docs/google/interactions.openapi.json
grep -nE '^      "(CreateModelInteractionParams|InteractionsInput|Interaction|Step|FunctionCallStep|InteractionSseEvent)": \{' artifacts/provider_docs/google/interactions.openapi.json
# resolve a schema with its oneOf/discriminator (stdlib json, no deps)
python3 -c "import json,sys;s=json.load(open('artifacts/provider_docs/google/interactions.openapi.json'))['components']['schemas'];print(json.dumps(s[sys.argv[1]],indent=1))" Step
# confirm which docs show Interactions REST calls (vs generateContent)
grep -c 'v1beta/interactions' artifacts/provider_docs/google/gemini-docs/*.md | grep -v ':0'
```

Polymorphism uses `oneOf`. Only `InteractionSseEvent` declares a `discriminator` (`event_type`). `Step` and `Content` variants are tagged by a `type` property with a `const` value (e.g. `FunctionCallStep.type = "function_call"`). Record that wire tag, not the schema name.

Docs vs. spec caveats:

- Many guides show both generateContent and Interactions examples. Use only the Interactions ones.
- Doc 092: `outputs` was replaced by `steps`. The spec uses `steps`; any doc example with `outputs` is legacy. `POST` returns only output steps, and `GET /{id}` returns the full timeline including the `user_input` step.
- Docs 002, 027, and 036 stream via `?alt=sse`; the spec and doc 070 use `"stream": true`. Prefer the spec form and record the conflict.
- A `v1beta2/interactions` form appears in some docs. The spec leaves `api_version` as a free string, so use `v1beta` unless a feature requires otherwise.

## OpenAI-compatible

No local spec. Assume Chat Completions shape from the OpenAI spec (`/chat/completions`) and note Responses-API support as server-dependent. Flag every assumption as `UNVERIFIED` for specific servers (vLLM, llama.cpp, LM Studio).
