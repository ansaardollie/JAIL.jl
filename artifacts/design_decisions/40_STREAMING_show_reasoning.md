# Decision: `show_reasoning` requests summaries, streams them, and links saved JSON traces

| Field | Value |
|-------|-------|
| Artifact | `40_STREAMING_show_reasoning.md` |
| Category | design_decisions |
| Subject | `STREAMING` |
| Date | 2026-10-06 |
| Area/Purpose scope | `chat!` / `}` mode display, Preferences, persistence, provider request bodies |
| Related | `25_MESSAGES_reasoning_part.md` (its revisit trigger), `36_STREAMING_boxed_turn_display.md`, `27_TOOLS_call_records_and_display.md`, `39_MESSAGES_thinking_effort_and_temperature.md` |
| Status | accepted |
| Decided by | user (one Bool, display, file layout, compatible servers); agent (wire mapping, rendering details) |

## Context

Owner: "support for showing model reasoning/thinking summaries/deltas when streaming responses".
Summaries must be requested: Anthropic `thinking.display = "summarized"`
(claude-docs-21-thinking.md#L449-L455), OpenAI `reasoning.summary = "auto"` (api_spec.yaml#L66706),
Google `generation_config.thinking_summaries = "auto"` (interactions.openapi.json#L8676), Vertex
`thinkingConfig.includeThoughts` (ai-platform-spec.json#L57800).

## Decision

User-decided:

- One Bool `show_reasoning`: `chat!` kwarg + Preference (default `false`). It requests
  summaries and shows them when streaming; summaries fill `ReasoningPart.text`.
- Display: streamed dimmed above the reply, plus a `Reasoning` box in the finished turn that
  does **not** show the trace but links to the saved traces: one Markdown file per reasoning
  trace (`ReasoningPart` with text), `<storage_dir>/reasoning/<session id>/<trace id>.md`, with
  YAML front matter (user: "save it as a markdown file instead with a YAML front matter",
  after per-turn JSONL, then per-trace JSON with `lines` split by line and sentence).
- OpenAI-compatible Chat Completions: read `reasoning_content` / `reasoning` best-effort
  (UNVERIFIED per server), never replayed.

Agent-decided:

- Internal hook `_StreamHooks(text, reasoning)` replaces the bare `on_text` in
  `_stream_event!`. Stream events: Anthropic `thinking_delta`; OpenAI
  `response.reasoning_summary_text.delta` and `response.reasoning_text.delta` (summary parts
  separated by a blank line on `reasoning_summary_part.added`); Google `thought_summary`;
  generateContent `thought: true` parts (consecutive chunks now merged into one part).
- Anthropic: `display: "summarized"` is added only to the adaptive `thinking` that an effort
  sends; with no effort nothing thinking-related is sent (user, after a temperature-0 400:
  "if thinking_effort is not set ... then no effort options are provided"), so `show_reasoning`
  alone yields no summaries on models defaulting to `display: "omitted"`. With effort `:none`
  no display (invalid with disabled, #L481). Live check, claude-sonnet-5, temperature 0, no
  thinking field: HTTP 400 "`temperature` is deprecated for this model".
- Chat Completions reasoning becomes `ReasoningPart(text, :chat_completions)`.
- OpenAI reasoning items with no summary use raw `content` text (api_spec.yaml#L66853-L66858).
- Trace file: front matter `version, id, session_id, reply_id, model, format, created` (no
  opaque `data`; it's in messages), values as JSON-quoted strings (valid YAML double-quoted
  scalars; `null` when absent), then the summary verbatim (providers already write Markdown,
  so the sentence splitting of the JSON version was dropped). Written after a
  successful turn only, through `_guard` (skipped with
  `persist_sessions = false`; then no box). Box: yellow `RGB(0.95, 0.77, 0.06)` (user; first grey), title
  `Reasoning (n):`, one numbered `View` OSC 8 link per trace on a TTY, else the paths; placed
  after Prompt, before Tool calls; also drawn when `response = false`.
- `_chat!` reports the files through `on_step(_ReasoningSaved(paths))`.
- `delete_session!(...; files = true)` removes `reasoning/<id>/`.

## Rejected

- Two keys (`reasoning_summaries` + `show_reasoning`).
- Showing the trace inside the box, or only live (gone from a TTY after the alt screen).
- One JSONL per session; one JSONL per turn with a line per summary (first shipped, replaced
  the same day: a JSON string per line is hard to read); one JSON file per trace with `lines`
  (replaced the same day by Markdown).

## Revisit Trigger

- Users want reasoning without streaming shown inline, or a `/reasoning` command to open the file.
- Anthropic `display: "updates"` (beta) or OpenAI `concise` summaries become wanted.
- A compatible server documents a different reasoning field.
