# Provider review: Function calling (define, call, return result, stream)

| Field | Value |
|-------|-------|
| Artifact | `4_TOOLS_function_calling.md` |
| Category | provider_reviews |
| Subject | `TOOLS` |
| Date | 2026-09-28 |
| Providers | OpenAI (Responses), OpenAI-compatible (Responses / Chat Completions), Anthropic (Messages), Google (Interactions) |
| Related | `design_decisions/17_TOOLS_definitions_and_registry.md`, `design_decisions/18_TOOLS_session_tools_and_call_loop.md`, `provider_reviews/2_MESSAGES_text_turns.md`, `provider_reviews/3_STREAMING_text_deltas.md` |

Paths are relative to `artifacts/provider_docs/`.

## Definition (request `tools`)

| | Shape | Cite |
|---|---|---|
| OpenAI Responses | `{"type":"function","name","description","parameters","strict"?}` | `openapi/api_spec.yaml#L79526-L79575` (FunctionTool); `tools` on ResponseProperties `#L69291` |
| Chat Completions | `{"type":"function","function":{"name","description","parameters","strict"?}}` | `#L41167-L41183` (ChatCompletionTool), `#L49838-L49870` (FunctionObject) |
| Anthropic | `{"name","description","input_schema"}` | `anthropic/api_spec.yaml#L5059-L5103` (Tool), `tools` `#L3584`; `claude-docs/claude-docs-25-define-tools.md#L16-L53` |
| Google | `{"type":"function","name","description","parameters"}` | `google/interactions.openapi.json#L5093-L5115` (Function), `tools` `#L3992-L3998`; `gemini-docs/gemini-docs-036-function-calling.md#L229-L252` |

- `strict` (OpenAI): omitted → Responses normalises to strict when possible and falls back to
  best effort; Chat Completions stays non-strict (`openapi/tool-guides/openai-tool-guides-02-function-calling-20260926.md#L1045-L1053`). JAIL omits it.
- Name: spec `^[a-zA-Z0-9_-]{1,64}$` (Anthropic `#L5071-L5081`, OpenAI FunctionObject); the
  Anthropic guide says `{1,128}` (`claude-docs-25#L22`). **Conflict**; JAIL keeps 64.
- Nullable: OpenAI strict example uses `"type": ["string","null"]` (guide `#L1059-L1090`); Gemini
  documents null via a type array (`gemini-docs-035-structured-output.md#L1486`). JAIL emits a
  type array for `Union{Nothing,T}` when `T` has a single `type`, else `anyOf`.
- Google function-parameter schema subset: local docs only say "a subset of the OpenAPI schema"
  (`gemini-docs-036#L3704`); the fetched official page had no field list. `{}` (untyped) and
  `additionalProperties` for function parameters are **UNVERIFIED** (documented for structured
  output, `gemini-docs-035#L1467-L1528`).

## Calls in the response

| | Where | Fields | Stop signal |
|---|---|---|---|
| OpenAI | `output[]` item `type: function_call` | `call_id`, `name`, `arguments` (JSON **string**), `id` (`fc_…`) | `status: completed`; presence of calls. `openapi/api_spec.yaml#L49877-L49935`; guide `#L599-L640` |
| Chat Completions | `choices[0].message.tool_calls[]` | `id`, `function.name`, `function.arguments` (string) | `finish_reason: tool_calls`. `#L40242-L40277` |
| Anthropic | `content[]` block `type: tool_use` | `id`, `name`, `input` (object) | `stop_reason: tool_use`. `claude-docs-26-handle-tool-calls.md#L15-L41`; `api_spec.yaml#L5015` |
| Google | `steps[]` `type: function_call` | `id`, `name`, `arguments` (object) | `status: requires_action`. `interactions.openapi.json#L5145` (FunctionCallStep, required `arguments,id,name,type`) |

## Returning results

| | Shape | Cite |
|---|---|---|
| OpenAI | input item `{"type":"function_call_output","call_id","output":string}` | `#L81074-L81130`; guide `#L660-L676` |
| Chat Completions | `{"role":"tool","tool_call_id","content":string}` after the assistant message carrying `tool_calls` | `#L40800-L40830`, assistant `tool_calls` `#L40509` |
| Anthropic | user message, `{"type":"tool_result","tool_use_id","content":string,"is_error"?}` blocks **first**, immediately after the `tool_use` turn | `api_spec.yaml#L4926-L4966`; `claude-docs-26#L50-L93` |
| Google | input step `{"type":"function_result","call_id","name","result":string,"is_error"?}` | `interactions.openapi.json#L5239` (FunctionResultStep); `gemini-docs-036#L1175-L1193` |

## Multi-turn

- **OpenAI**: chained turns send only `function_call_output` items with `previous_response_id`.
  Full replay re-sends the `function_call` items (`call_id`, `name`, `arguments`) before the
  outputs (guide `#L225-L262`, `input_list += response.output`). JAIL omits the item `id` on
  replay since it does not keep the paired reasoning items (UNVERIFIED: the API is known to
  reject an `fc_` id whose reasoning item is missing).
- **Anthropic**: always full replay; the assistant turn re-sends its `tool_use` blocks.
- **Google**: chained turns send `function_result` steps with `previous_interaction_id`
  (`gemini-docs-036#L1177-L1193`). Stateless replay must include "all model-generated steps …
  (including `thought` and `function_call` steps) exactly as received" (`#L1399-L1407`). JAIL
  drops `thought` steps (todo `4_MESSAGES_replay_reasoning.md`), so stateless tool turns on
  thinking models may be rejected. **Gap.**

## Streaming

- **OpenAI**: `response.function_call_arguments.delta` / `.done` (`#L68249`, `#L68295`); the
  terminal `response.completed` carries the full Response with the `function_call` items, so
  JAIL's existing final-response parse covers it.
- **Chat Completions**: `choices[].delta.tool_calls[]` chunks `{index, id?, function:{name?, arguments}}`,
  accumulate by `index` (`#L40278-L40310`).
- **Anthropic**: `content_block_start` with `{"type":"tool_use","id","name","input":{}}`, then
  `content_block_delta` `input_json_delta.partial_json` (accumulate, parse at stop)
  (`claude-docs-15-streaming.md#L933-L960`; `api_spec.yaml#L3728`).
- **Google**: `step.start` with `{"type":"function_call","id","name","arguments":{}}`, then
  `step.delta` `{"type":"arguments_delta","arguments": partial string}`; status `requires_action`
  (`gemini-docs-070-streaming.md#L207-L250`, `#L289-L298`; `interactions.openapi.json#L2997`).
  `interaction.completed` carries no steps (`#L166`), so steps are rebuilt from events.

## Concept mapping

| Concept | OpenAI | Chat | Anthropic | Google | JAIL |
|---|---|---|---|---|---|
| definition | FunctionTool | ChatCompletionTool | Tool | Function | `ToolSpec` |
| call | function_call item | tool_calls[] | tool_use block | function_call step | `ToolCall <: AbstractContentPart` in `AssistantMessage` |
| call id | call_id | id | id | id | `ToolCall.id` |
| arguments | JSON string | JSON string | object | object | `Dict{String,Any}` |
| result | function_call_output | role tool | tool_result block | function_result step | `ToolResult` in `ToolResultMessage` |
| error flag | — | — | is_error | is_error | `ToolResult.is_error` (text only where no flag) |
| stop | status completed + calls | finish_reason tool_calls | stop_reason tool_use | status requires_action | `:tool_use` |

Extensions not modelled: `tool_choice`, `parallel_tool_calls`, `strict`, OpenAI namespaces /
tool search, Anthropic `input_examples` / `cache_control`, server tools.

## Open questions

- Google parameter-schema subset (see above).
- Replaying Google `thought` steps and OpenAI reasoning items (todo 4).
