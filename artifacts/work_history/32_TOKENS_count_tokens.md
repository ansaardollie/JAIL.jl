# Token counting: `count_tokens` and `TokenCount`

| Field | Value |
|-------|-------|
| Artifact | `32_TOKENS_count_tokens.md` |
| Category | work_history |
| Subject | `TOKENS` |
| Date | 2026-10-05 |
| Area/Purpose scope | public API, providers, `|` mode, docs, examples |
| Related | `design_decisions/37_TOKENS_count_tokens.md`, `work_history/31_STREAMING_boxed_turn_display.md` |

## Scope of This Unit of Work

Follows `31_STREAMING_boxed_turn_display.md`. Request: a token counter for a session counting
what its system prompt, tools and message history take up, per provider, with each provider's
canonical counting endpoint. The owner added local docs for the endpoints during the session:
`provider_docs/openapi/api-references/openai-api-references-01-input-tokens.md`,
`provider_docs/google/counting-tokens.md` (Gemini API), `provider_docs/google/gemini-docs/count-tokens.md`
(Vertex). GenerateContentRequest's required `model` came from https://ai.google.dev/api/batch-api.

## What Changed

| File | Change |
|-------|--------|
| `src/tokens.jl` (new) | `TokenCount` (model, total, system, tools, messages) + `show`; `count_tokens(s[, prompt]; model)` and session-less form; `_count_tokens` (cumulative counts, placeholder message for providers that need one); `_count_request`; `_count_error` (OpenAICompatible 404/405/501 hint) |
| `src/ontology/requests.jl` | interface stubs `_count_url`, `_count_body`, `_parse_count`; `_count_needs_messages` (default false) |
| `src/providers/openai.jl` | `/responses/input_tokens` for every `AbstractOpenAIProvider` (Responses body filtered to model/input/instructions/tools) |
| `src/providers/anthropic.jl` | `/v1/messages/count_tokens` (body filtered to model/messages/system/tools); needs messages |
| `src/providers/google.jl` | Google: `/v1beta/models/{id}:countTokens` with `generateContentRequest` (generateContent body + `model`); needs messages. GoogleEnterprise: Vertex `v1 .../publishers/google/models/{id}:countTokens`, top-level body, either `api`. `_parse_count` reads `totalTokens` (default 0) |
| `src/repl/model_mode.jl` | `tokens [provider/model]` command, help, usage, completion |
| `src/JAIL.jl` | export `TokenCount`, `count_tokens`; include `tokens.jl` |
| `docs/src/reference.md`, `guide/chat.md`, `guide/repl.md` | Token counting section, reference entries, command row |
| `examples/token_counting.jl` (new) | offline + `LIVE` parts |

## Decisions

- `37_TOKENS_count_tokens.md` (user: name, breakdown struct, `model` kwarg, optional prompt,
  OpenAICompatible uses the same endpoint, Google system+tools, `tokens` command).

## Verification

Mock HTTP server (body length ÷ 10 as the count), session with system, one tool and a tool round,
`count_tokens(s, "And London?"; model = m)`:

```
TokenCount(anthropic/claude-x: 61 total, 2 system, 13 tools, 46 messages)
  /v1/messages/count_tokens => {"messages":[...5 turns...],"model":"claude-x"}
  ... + "system":"Be terse." ... + "tools":[{"input_schema":{...},"name":"get_weather"}]
TokenCount(openai/gpt-x: 51 total, 3 system, 14 tools, 34 messages)
  /v1/responses/input_tokens => {"input":[...function_call, function_call_output...],"model":"gpt-x"} (+ instructions, + tools)
TokenCount(google/gemini-x: 67 total, 5 system, 16 tools, 46 messages)
  /v1beta/models/gemini-x:countTokens => {"generateContentRequest":{"contents":[...],"model":"models/gemini-x"}} (+ systemInstruction, + tools functionDeclarations/parametersJsonSchema)
```

Empty Anthropic session sends a `"."` placeholder and reports `messages: 0`. GoogleEnterprise URL
`https://us-central1-aiplatform.googleapis.com/v1/projects/proj/locations/us-central1/publishers/google/models/gemini-y:countTokens`
and top-level body checked directly. OpenAICompatible on a 404 server:

```
mocklm API error (HTTP 404): Not Found
"mocklm" has no token counting endpoint (POST http://127.0.0.1:18765/nope/responses/input_tokens); count_tokens needs a server that implements OpenAI's /responses/input_tokens
```

`|` mode `tokens` printed the breakdown; `tokens a b` → `usage: tokens [provider/model]`.
`examples/token_counting.jl` offline part ran (zero count, two errors). Docs build: no warnings.

Unintended live calls: `tokens openai/gpt-x` in the mock test resolved `openai` through the
owner's Preferences, so two requests reached the real OpenAI counting endpoint with a fake model;
it answered `HTTP 404: The model 'gpt-x' does not exist` (route exists; nothing generated).

## Limitations

- No live counts verified for any provider (only the OpenAI route, via the 404 above).
- Vertex `contents: []` (empty history, no placeholder) unverified; spec marks it optional.
- Interactions reasoning (`:google_interactions`) isn't sent to Google's counter.
- No automated tests (test suite is still empty).

## Next Steps

- Run `examples/token_counting.jl` with `LIVE = true` to check the endpoints and the placeholder.
- Consider showing the count in the `|` mode `status` or the `}` prompt if useful.
