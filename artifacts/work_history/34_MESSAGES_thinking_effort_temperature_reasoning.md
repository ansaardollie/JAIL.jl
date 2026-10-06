# Thinking effort, temperature, and shown reasoning summaries

| Field | Value |
|-------|-------|
| Artifact | `34_MESSAGES_thinking_effort_temperature_reasoning.md` |
| Category | work_history |
| Subject | `MESSAGES` |
| Date | 2026-10-06 |
| Area/Purpose scope | chat core, all providers, Session, persistence, `}` / `|` REPL modes, docs, examples |
| Related | `design_decisions/39_MESSAGES_thinking_effort_and_temperature.md`, `design_decisions/40_STREAMING_show_reasoning.md`, `design_decisions/25_MESSAGES_reasoning_part.md`, `work_history/33_MESSAGES_anthropic_per_model_max_tokens.md`, `todos/pending/9_MESSAGES_live_check_effort_reasoning.md` |

## Scope of This Unit of Work

Follows `33_MESSAGES_anthropic_per_model_max_tokens.md`. Owner asked for three upgrades:
configurable reasoning effort, temperature, and showing reasoning summaries while streaming.
Then iterated: trace storage went per-turn JSONL → per-trace JSON with `lines` → sentence-split
`lines` → Markdown with YAML front matter (kept); session details shown in full in `show` and
`|` mode `status`; reasoning box yellow; Anthropic gets no thinking/effort fields unless
`thinking_effort` is set (after a temperature-0 400); docs pass.

## What Changed

| File | Change |
|-------|--------|
| `src/ontology/requests.jl` | `_Request` gains `thinking_effort`, `temperature`, `show_reasoning`; new `_StreamHooks(text, reasoning)` passed to `_stream_event!` |
| `src/chat.jl` | `_check_effort`, `_check_temperature`, `_thinking_effort`/`_temperature`/`_show_reasoning` (Preference fallback); `chat!`/`_chat!`/`_tool_loop!`/`_complete` take `thinking_effort`, `temperature`, `show_reasoning`, `on_reasoning`; kwarg > session > Preference; `_ReasoningSaved(paths)` step after a turn |
| `src/session.jl` | `Session` fields `thinking_effort::Union{Nothing,Symbol}`, `temperature::Union{Nothing,Float64}`; ctor/`new_session!` kwargs; exported `set_thinking_effort!`, `set_temperature!` (+ session-less forms); `_show_details` shared by `show` and `status` (provider, thinking, temperature, reasoning rows, Preference-resolved) |
| `src/persistence.jl` | session JSON stores both fields (read with `get`, old files fine); `_record_reasoning!` writes `<storage_dir>/reasoning/<session id>/<trace id>.md` (YAML front matter: version, id, session_id, reply_id, model, format, created; body verbatim); `_delete_files!` removes `reasoning/<id>/` |
| `src/providers/anthropic.jl` | `temperature`; `_anthropic_thinking!`: no effort → nothing; `:none` → `thinking: disabled`; else `output_config.effort` + `thinking: adaptive` (+ `display: summarized` with show_reasoning); `thinking_delta` → `on.reasoning` |
| `src/providers/openai.jl` | `temperature`, `reasoning.{effort,summary}`; streams `response.reasoning_summary_text.delta` / `response.reasoning_text.delta`; reasoning items without summary use raw `content` text |
| `src/providers/openai_compatible.jl` | Chat Completions `reasoning_effort`, `temperature`; `reasoning_content`/`reasoning` (UNVERIFIED per server) → `ReasoningPart(text, :chat_completions)`, never replayed |
| `src/providers/google.jl` | Interactions `generation_config.{thinking_level, thinking_summaries, temperature}`; generateContent `generationConfig.{temperature, thinkingConfig.{thinkingLevel (upper), includeThoughts}}`; `thought_summary` / `thought` parts → `on.reasoning`; consecutive streamed thought chunks merged into one part |
| `src/repl/chat_mode.jl` | streamed reasoning dim italic; yellow `Reasoning (n):` box (`RGB(0.95, 0.77, 0.06)`) with numbered `View` OSC 8 links per trace file |
| `src/repl/model_mode.jl` | `status` uses `_show_details(...; status = true)` |
| `src/tokens.jl` | `_Request` call updated (no effort/temperature/summaries in counts) |
| `src/ontology/messages.jl` | `ReasoningPart` docstring: `:chat_completions` format, summaries with `show_reasoning` |
| `docs/src/{index,reference}.md`, `docs/src/guide/{chat,concepts,providers,repl,sessions}.md`, `docs/make.jl` | new section "Thinking effort, temperature and reasoning", provider tables, Preferences keys, session section + examples, REPL Reasoning section and `status` transcript; `__clear__` list gains the 3 keys |
| `examples/reasoning.jl`, `examples/LocalPreferences.toml` | session effort/temperature usage, misuse errors, live `show_reasoning` section (gated); 3 new Preference keys |
| `artifacts/design_decisions/25_…` | note that summaries are now requested with `show_reasoning` |

## Decisions

- `39_MESSAGES_thinking_effort_and_temperature.md`: name `thinking_effort` (rejected `effort`, `reasoning_effort`, `thinking`); levels sent as-is (rejected clamp / throw); kwarg + session + Preference; setters; Anthropic effort ⇒ adaptive thinking.
- `40_STREAMING_show_reasoning.md`: one Bool `show_reasoning`; dim stream + box linking to saved traces (rejected trace in box, JSONL, JSON `lines`); compat servers best-effort; Anthropic summaries only with an effort; yellow box.

## Verification

Mock SSE server per provider (`_display_turn`, non-TTY, `show_reasoning = true`, `temperature = 0.4`, session effort `:low`):
```
==== anthropic/claude-opus-4-8
Let me find the GCD. Euclid works.

The GCD is **21**.
reply.content = AbstractContentPart[ReasoningPart(:anthropic, "Let me find the GCD. Euclid works."), TextPart("The GCD is **21**.")]
sent: {"output_config":{"effort":"low"},"temperature":0.4,"thinking":{"display":"summarized","type":"adaptive"}}
==== openai/gpt-6        sent: {"reasoning":{"effort":"low","summary":"auto"},"temperature":0.4}
==== google/gemini-3.8-flash  sent: {"generation_config":{"temperature":0.4,"thinking_level":"low","thinking_summaries":"auto"}}
==== mockc/qwen          sent: {"reasoning_effort":"low","temperature":0.4}
```
Vertex generateContent body: `{"generationConfig":{"maxOutputTokens":100,"temperature":0.2,"thinkingConfig":{"includeThoughts":true,"thinkingLevel":"MEDIUM"}}}`.
Precedence: Preference only → `{"output_config":{"effort":"medium"},"temperature":0.9,…}`; session `:high` + kwarg 0.1 → `effort "high"`, `temperature 0.1`.
Restore: `r2.thinking_effort = :high`, `r2.temperature = 0.25`; `delete_session!(…; files = true)` → `isdir(reasoning dir) = false`.

Anthropic body after the final change (temperature 0):
```
no effort: {"temperature":0.0}
effort low: {"output_config":{"effort":"low"},"temperature":0.0,"thinking":{"display":"summarized","type":"adaptive"}}
effort none: {"temperature":0.0,"thinking":{"type":"disabled"}}
```
Live (owner approved one; a first attempt ran stale pre-change code and returned the original
error): claude-sonnet-5, temperature 0, no thinking field →
`anthropic API error (HTTP 400): \`temperature\` is deprecated for this model.`

Trace file written by `_record_reasoning!`:
```
---
version: 1
id: "01a10ebd-9745-7ada-84f8-7ead6bcb15f4"
session_id: "01a10ebd-957c-7e48-bda6-39f8c1e31bb2"
reply_id: "resp_1"
model: "openai/gpt-6"
format: "openai_responses"
created: "2026-10-06T01:04:28.485Z"
---

**Planning**

Check "quotes": and... ellipses. Then 3.14.
```
`include("examples/reasoning.jl")` (offline parts) ran; misuse lines print
`ArgumentError: thinking_effort must be a Symbol such as :high, got 3` and
`ArgumentError: temperature must be a non-negative number, got -0.5`.
`julia --project=docs docs/make.jl`: 0 warnings; no owner Preference values in built HTML.

Not verified: any live OpenAI/Google/compatible call with these options; live streaming of
summaries; a real-terminal look at the yellow box and dim italic text; non-stream parse paths
with `show_reasoning` end to end.

## Limitations

- Levels are not validated: unsupported ones 400 at the provider.
- Extended-thinking-only Anthropic models (Haiku 4.5, Sonnet 4.5) reject the adaptive thinking any effort sends; no `budget_tokens` support.
- `show_reasoning` alone yields no summaries on Anthropic models defaulting to `display: "omitted"` (Sonnet 5, Opus 5.x).
- Newest Anthropic models reject any non-default temperature; Google temperature is DOCS-ONLY and deprecated.
- Compat-server reasoning field names UNVERIFIED.
- Earlier trace files (`.jsonl`, `.json`) in owner's `.jail/` are left as written.
- No automated tests (see `todos/pending/1_TESTS_test_suite_setup.md`).

## Next Steps

- `todos/pending/9_MESSAGES_live_check_effort_reasoning.md`: live check per provider.
- Consider `budget_tokens` mapping for extended-thinking Anthropic models if owner uses them.
- `todos/pending/8_MESSAGES_reasoning_data_principle_6.md` still open (`ReasoningPart.data` public).
