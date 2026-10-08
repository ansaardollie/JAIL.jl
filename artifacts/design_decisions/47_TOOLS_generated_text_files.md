# Decision: Tool calls' generated text saved as files under `<storage_dir>/generated/`

| Field | Value |
|-------|-------|
| Artifact | `47_TOOLS_generated_text_files.md` |
| Category | design_decisions |
| Subject | `TOOLS` |
| Date | 2026-10-08 |
| Area/Purpose scope | persistence, REPL display |
| Related | `27_TOOLS_call_records_and_display.md`, `24_SESSION_persistence.md`, `36_STREAMING_boxed_turn_display.md` |
| Status | accepted |
| Decided by | user (layout, types, extensions, link label); agent (id used, tool set, details below) |

## Context

User: "When the tool is run the serialised tool call only as JSON displays the code as single
string with `\n` newlines ... whenever a tool call generates some wall of text (i.e. julia code /
file contents / shell commands / etc) ... also add that text to the storage dir.
`<storage_dir>/generated/<type>/<session id>/<tool call id>/generated.<extension>` where <type>
is either `file` / `code` / `shell` and extension is the tool call file extension / `.jl` / `.sh`
... show up as hyperlink in the tool calls output ... next to the `View` link and be called
`View Generated <type>`".

## Decision

| Tool | Type | Text | Extension |
|---|---|---|---|
| `execute_julia_code` | `code` | `code` | `.jl` |
| `run_shell` | `shell` | `command` | `.sh` |
| `create_file` | `file` | `content` | the path's extension, else `.txt` |

Agent-decided:

- `<tool call id>` is JAIL's pair id (`ToolResult.id`, UUID v7, the name of the
  `tools/<session id>/<id>.json` record), not the provider's call id: the two files pair up, and
  provider ids are not guaranteed file-name safe. Rejected: provider call id.
- Only those three built-ins (internal `_GENERATED::IdDict` keyed by tool function); edit tools
  that carry fragments (`replace_in_file`, `replace_in_files`, `edit_file`) are not saved.
  Rejected: saving fragments as `.diff` (no matching type).
- Saved whatever the outcome (success, error, declined); not saved when `persist_sessions = false`.
- The call record gains `generated` (path or `null`); `delete_session!(s; files = true)` removes
  the session's generated folders.
- Link only on terminals (OSC 8); off a terminal the path is printed.

## Consequences

Generated text is stored twice (record JSON and file). User tools cannot opt in (no public API).

## Revisit Trigger

Owner wants edit fragments saved, user tools to declare generated text, or provider call ids as
folder names.
