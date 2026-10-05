# Reasoning replayed on full-history requests; Vertex Interactions tool results fixed and made default

| Field | Value |
|-------|-------|
| Artifact | `21_MESSAGES_reasoning_replay.md` |
| Category | work_history |
| Subject | `MESSAGES` |
| Date | 2026-10-05 |
| Area/Purpose scope | core ontology, provider layer, persistence, configuration, docs, examples |
| Related | `design_decisions/25_MESSAGES_reasoning_part.md`, `design_decisions/26_PROVIDER_google_enterprise_interactions_default.md`, `design_decisions/21_PROVIDER_google_enterprise_generate_content.md` (superseded in part), `todos/completed/4_MESSAGES_replay_reasoning.md` |

## Scope of This Unit of Work

Follows `20_PROVIDER_google_adc_reauth.md` (no open next steps). The owner captured the Python
google-genai SDK's traffic (`vault/GoogleGenAI_Requests/{python,flows}`) for generateContent,
chats and Interactions, and asked for a comparison with JAIL. Two findings were acted on:
(1) send thought signatures back on every full-history request, for every provider; (2) test
whether JAIL's plain-string Interactions `function_result.result` was why Vertex Interactions
"did not handle function results", and if so make Interactions the `GoogleEnterprise` default again.

## What Changed

| File | Change |
|-------|--------|
| `src/ontology/messages.jl` | New exported `ReasoningPart(text, format::Symbol, data)`; `show`; private `_replays(part, msg, provider, format)` (same format and same provider type as `msg.model.provider`) |
| `src/JAIL.jl` | Export `ReasoningPart` |
| `src/ontology/requests.jl` | `_summary_text(items)` for Google/OpenAI summary item lists |
| `src/chat.jl` | `_fp_part(::ReasoningPart)` for the chaining fingerprint; `chat!` docstring wording for the new default |
| `src/providers/google.jl` | Interactions: `function_result.result` is now `[{"type":"text","text":…}]`; `thought` steps parsed into `ReasoningPart(:google_interactions)` and replayed in order; streaming accumulates `thought_summary` / `thought_signature` deltas; a `model_output` `step.start` that already carries text is no longer dropped. `_google_steps(m, p)` iterates parts in order. generateContent: `thoughtSignature` on any part becomes a signature-only `ReasoningPart(:google_generate_content)` before that part's content; `thought: true` parts kept whole; replay puts the signature back onto the next part (trailing one as `{"text":"","thoughtSignature":…}`); stream keeps signature-carrying chunks (including the empty final one). `_THOUGHT_SIGNATURES` removed. Default `api` is `:interactions`; docstring lists Vertex limits |
| `src/providers/anthropic.jl` | `thinking` / `redacted_thinking` blocks parsed, streamed (`thinking_delta`, `signature_delta`) and replayed in order; `_request_body(p::Anthropic, …)`, `_anthropic_blocks(m, p)` |
| `src/providers/openai.jl` | `reasoning` output items (minus `status`) parsed and replayed in order; `_responses_items!(input, m, p)` |
| `src/persistence.jl` | `{"type":"reasoning","text","format","data"}` parts; `_restore_part` → `_restore_parts!`; old `tool_call.thought_signature` lines are read as a reasoning part |
| `src/configuration.jl` | `api` persisted only when not `:interactions`; `nothing` resets to `:interactions` |
| `docs/src/guide/{chat,providers,concepts}.md`, `docs/src/index.md`, `docs/src/reference.md` | New default and Vertex Interactions limits; `ReasoningPart` in Messages and the reference; the "Google full replay drops thought steps" caveat replaced |
| `examples/reasoning.jl` | New |
| `examples/tools.jl`, `examples/providers_and_models.jl`, `examples/LocalPreferences.toml` | Stale notes and the `api` default updated |

## Design Decisions Made

- `25_MESSAGES_reasoning_part.md`: public `ReasoningPart` (rejected: hidden payload on
  `AssistantMessage`); name `ReasoningPart` (rejected `ThinkingPart`, `ThoughtPart`); replay only
  to the same provider type + wire (rejected: same model only).
- `26_PROVIDER_google_enterprise_interactions_default.md`: default back to `:interactions`
  (rejected: keep `:generate_content`), decided after the owner was told about the Gemini 2.5 /
  `europe-west1` limits.
- Agent: the generateContent signature is kept as its own part rather than as a field on
  `TextPart`/`ToolCall`, so the existing public part types are unchanged.

## Verification

A/B on Vertex Interactions (dhd-prima, `global`, `gemini-3.1-flash-lite`, tool returns 22°C):

```
# plain-string result (before the edit took effect), 6 runs, e.g.
AssistantMessage (google_enterprise/gemini-3.1-flash-lite, end_turn, 229 in / 12 out)
The current temperature in London is 10°C.
# content-array result, every run since, e.g.
>> {"input":[{"call_id":"call_1078527",…,"result":[{"text":"{\"location\": \"London\", …}","type":"text"}],"type":"function_result"}],"previous_interaction_id":"ChAx…","store":true,…}
AssistantMessage (google_enterprise/gemini-3.1-flash-lite, end_turn, 237 in / 12 out)
The current temperature in London is 22°C.
FAIL europe-west1 gemini-2.5-pro: google_enterprise API error (HTTP 400): Unsupported model interaction: gemini-2.5-pro
FAIL europe-west1 gemini-3.1-flash-lite: google_enterprise API error (HTTP 500): Internal error encountered.
```

Live full-history replays (two prompts, each with a tool round; request bodies logged, signatures
truncated):

```
== generateContent (GoogleEnterprise, global)
>> …{"parts":[{"text":"The current …","thoughtSignature":"AY89a1+V…"}],"role":"model"},{"parts":[{"text":"And in Paris?"}],"role":"user"}…
<< "The current temperature in Paris is 22°C." end_turn
== generateContent, streaming
>> …{"parts":[{"text":"The temperature in London is 22°C."},{"text":"","thoughtSignature":"AY89a191…"}],"role":"model"}…
== Vertex Interactions, full replay
>> {"input":[{…"user_input"},{"signature":"AY89a19U…","type":"thought"},{…"function_call"},{…"function_result"},{"signature":"AY89a19l…","type":"thought"},{…"model_output"},{…"And in Paris?"…}],"store":true}
<< "The temperature in Paris is also 22°C." end_turn
== Google Developer API (Interactions), store = false (also streaming)
>> {"input":[…,{"signature":"EnMKcQFp…","type":"thought"},{…"function_call"},…],"store":false}
<< "The current temperature in Paris is 22°C." end_turn
== OpenAI gpt-5-mini, store = false (also streaming)
>> {"input":[…,{"content":[],"encrypted_content":"gAAAAABq…","id":"rs_0f1bda2fd…","summary":[],"type":"reasoning"},{"arguments":"{\"location\":\"London\"}",…,"type":"function_call"},…],"store":false}
<< "The current temperature in Paris is 22 °C." end_turn
== Anthropic claude-sonnet-5 (also streaming)
>> …{"content":[{"signature":"EpQCCqQB…","thinking":"","type":"thinking"},{"id":"toolu_01Lo…",…,"type":"tool_use"}],"role":"assistant"}…
<< "22°C in Paris." end_turn
```

`gpt-6-luna` returned no reasoning items (no reasoning by default), so `gpt-5-mini` was used for
OpenAI. `store_requests = false` was set for the Google Developer API and OpenAI runs and then
removed (`J._store_requests() = true` afterwards).

Offline: mocked HAR/doc payloads parsed and re-serialised per wire; a generateContent history sent
to the Interactions wire, and OpenAI reasoning sent to Anthropic, both drop the reasoning;
persistence round trip `back.content[1].data == ra.content[1].data = true`; legacy
`thought_signature` line restores to `[ReasoningPart(:google_generate_content, ""), ToolCall(f())]`
and replays as `{"functionCall":…,"thoughtSignature":"OLD"}`.

Default flip: `GoogleEnterprise(project = "dhd-prima", location = "global").api = :interactions`,
`_to_prefs` omits `api` for it and writes `"generate_content"` otherwise; live tool round at
`global` answered 22°C.

Docs: `jd docs/make.jl` exits 0 with no warnings; `docs/build` has no `dhd-prima`/`gpt-6-luna`.

`examples/reasoning.jl` run with `LIVE = true` (Anthropic):

```
reply.content = AbstractContentPart[ReasoningPart(:anthropic, "Check the tool first."), TextPart("It's 22°C.")]
string(reply) = "It's 22°C."
m.content = AbstractContentPart[ReasoningPart(:anthropic, ""), ToolCall(get_current_temperature(location = "London"))]
MethodError: no method matching ReasoningPart(::String, ::String, ::Dict{Any, Any})
```

Not run: `examples/providers_and_models.jl` (it writes to the live LocalPreferences).

## Known Limitations

- The owner's `LocalPreferences.toml` (`google_enterprise`: `gemini-2.5-pro`, `europe-west1`, no
  `api`) now resolves to Interactions and fails; it needs `api = "generate_content"` or a Gemini 3
  model at `global`.
- Cross-provider dropping is verified offline only.
- The Interactions `model_output` `step.start` text fix is verified offline only.
- OpenAI reasoning items are replayed without `status`; replaying it unchanged was not tried.
- `ReasoningPart` uses default struct equality (its `Dict` compares by identity).
- No test suite yet (`todos/pending/1_TESTS_test_suite_setup.md`).

## Todos

- Completed: `4_MESSAGES_replay_reasoning.md`
- Created: none

## Next Steps

1. Owner: save `api = "generate_content"` for `google_enterprise` in the live preferences, or move
   to a Gemini 3 model at `global`.
2. When the test suite lands, add mocked-body tests for each reasoning format (fixtures are in the
   Verification section and `vault/GoogleGenAI_Requests/flows/`).
3. Optional: a Preference/option to request reasoning summaries and show them in the `}` mode.
