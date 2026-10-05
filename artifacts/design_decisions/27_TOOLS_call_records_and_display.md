# Decision: Tool call records on disk and their display in the `}` mode

| Field | Value |
|-------|-------|
| Artifact | `27_TOOLS_call_records_and_display.md` |
| Category | design_decisions |
| Subject | `TOOLS` |
| Date | 2026-10-05 |
| Area/Purpose scope | core ontology, persistence, REPL surface |
| Related | `18_TOOLS_session_tools_and_call_loop.md`, `24_SESSION_persistence.md`, `16_STREAMING_repl_and_chat.md` |
| Status | accepted |
| Decided by | user (Q&A below, file layout, UUID v7, OSC 8); agent (record format, colours, details) |

## Context

User: "When streaming output from the model and `confirm_tools` is set to false, none of the tool
calls are actually displayed. Can we please implement the ability to see tool calls in the chat
repl mode streamed response as well as the final output. It should be clear what tools were
called. Also let's serialise the tool call requests and responses under `.jail/tools` there
should be a folder per session and JSON file per tool call/result pair. The tool call/result pair
should have a uuid7 id as well. And then in the final output of the chat repl mode there should
be a display of all the tool calls along with hypertext links (using the OSC 8 ... ANSI escape
sequence) to the json call/result pair".

## Questions and Answers

| Question | Options | Chosen |
|---|---|---|
| Final turn layout | inline + summary block; summary only; inline lines with links | **inline + summary block** |
| Link text | relative path; short id; call signature | **relative path** (readable without OSC 8) |
| Who writes the files | core loop, gated by `persist_sessions`; core + own Preference; `}` only | **core loop, `persist_sessions`** |
| Pair id in history | file only; also on `ToolResult` + JSONL | **also on `ToolResult`** |

## Decision

```julia
ToolResult(call_id, name, content; is_error = false, id = nothing)  # id::Union{Nothing,UUID}
```

- `_tool_loop!` gives every result (including "not run" limit results) `id = uuid7()` and writes
  `<storage_dir>/tools/<session id>/<id>.json`; the JSONL `tool_result` part carries `"id"`.
- Record (agent-decided): `{"version":1,"id","session_id","model","started","finished",
  "duration_ms","call":{"id","name","arguments"},"result":{"content","is_error"}}`; `content`
  uses the same JSON-value-if-identical rule as the messages file. `started` is taken before
  confirmation, so a confirmed call's duration includes the prompt.
- `}` mode: call lines `→ sig` in cyan (were dim), results unchanged; after the turn, a
  `Tool calls (n):` block, one line per call: `✓`/`✗`, signature, path. Path is relative to
  `pwd()`, or `~`-contracted absolute when outside it; wrapped in OSC 8 (`file://` URL, empty
  host, percent-encoded) only when the output is a TTY. No path when the file doesn't exist.
- `delete_session!(s; files = true)` and a failed first turn remove `tools/<session id>/`.
- `chat!(...; stream = true)` prints the cyan call lines but no summary block (user scoped the
  block to the REPL).

## Rejected

- Summary only (loses where calls happened between reply texts); links on inline lines only (no
  single overview).
- Short-id or signature link text (useless in terminals without OSC 8).
- Separate `persist_tool_calls` Preference (one switch for everything on disk is simpler).
- File-only pair id (history couldn't point at its record).

## Consequences

- `ToolResult` gained a field; `ToolResult(...)` without `id` still works.
- Results rolled back with a failed later turn leave their record files behind.
- The original "not displayed" report was not reproduced with an Anthropic SSE mock (lines did
  show); dim (`light_black`) call lines on some themes is a likely cause, hence cyan.

## Revisit Trigger

A need to look records up from code (a public path accessor), records growing large (binary or
huge outputs), or terminals mis-rendering OSC 8.

## Amendment (2026-10-05, user revision after trying it)

User: "in the streaming mode it should appear in the stream output when it happens but after
displaying the final output we can remove the `<-` & `->` from the streamed response. Also in the
final finished output the tool calls should be displayed first and then the final response.
secondly the hyperlink display should not be the relative path but rather just say `View`."

| Question | Options | Chosen |
|---|---|---|
| Text after the block | all reply texts of the turn; last reply only | **all reply texts** (joined as one Markdown document) |
| Non-stream progress | transient status line, same final layout; live lines kept | **transient** (`thinking…` / `→ label…`, erased) |
| Call line content | label only; label + arguments | **label only** (arguments are behind `View`) |

Supersedes the "inline + summary" layout and the relative-path link text above:

- Finished turn (terminal, streamed or not): `Tool calls (n):` block (`✓`/`✗`, label, `View`
  OSC 8 link), blank line, rendered reply texts. Streamed `→ label` / `← label: result` lines
  stay on the alternate screen only.
- Not a terminal: `View` is replaced by the `~`-contracted path; a streamed turn keeps its raw
  text and lines and appends the block.
- With `confirm_tools = true` and no streaming, no transient call line is shown so the
  confirmation prompt has the line.
- Records gained `"tool": {"name", "label", "group"}` (see `28_TOOLS_groups_and_labels.md`).
- Follow-up (user: "more of a visible seperation ... Like `Output: `"; "I only want the underline
  underneath the `View`"): a bold `Output:` heading follows the block (only when there is one);
  the underline covers `View` only.
