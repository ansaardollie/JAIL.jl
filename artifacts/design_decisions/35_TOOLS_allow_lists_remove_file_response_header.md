# Decision: path/command allow-lists, `remove_file`, and the `Response (...)` turn header

| Field | Value |
|-------|-------|
| Artifact | `35_TOOLS_allow_lists_remove_file_response_header.md` |
| Category | design_decisions |
| Subject | `TOOLS` |
| Date | 2026-10-05 |
| Area/Purpose scope | built-in tool security levels; `}` mode / `chat!(; stream = true)` display |
| Related | `29_TOOLS_security_approval_preview.md`, `32_TOOLS_builtin_tools_groups_and_rules.md`, `33_STREAMING_chat_uses_chat_mode_display.md`, `34_TOOLS_ask_user_free_text_and_edit_file.md` |
| Status | accepted |
| Decided by | user (features); agent (details listed) |

## Context

User asked for: a `remove_file` tool; a `path_allow_list` Preference making edit/replace/remove
calls `:low` for listed files/dirs; a `command_allow_list` Preference of prefixes making
`run_shell` `:low`; the `Output:` line replaced by
`Response (<model>; <cumulative input> in; <cumulative output> out):`; a `Prompt:` section when
Julia is not interactive; no duplicated question for streamed `ask_user`.

## Decision

Agent-decided:

- `remove_file(path)`: group `edit`, label "Delete file", files only (folders refused; a symlink
  deletes the link). Base level **`:high`** (irreversible), `:low` when allow-listed.
- `path_allow_list` applies to every `edit` tool via `_write_level`. Entries are root-relative
  or absolute (so dirs outside the workspace can be allowed). **Protected paths always win.**
  Matching is on real paths (`_real_path` resolves links for the existing prefix) for both the
  entry and the protected list, so links can't escape an allowed dir or reach a protected file.
- `command_allow_list`: match = stripped command starts with the stripped entry, followed by
  whitespace or end (`"git status"` ≠ `git statusx`/`git stash`). Any shell control char makes
  it `:high`: POSIX `\n \r ; & | ` $ < >`; Windows `\n \r & | < > ^ %`. Otherwise `:high`.
- Response header shown on every finished turn (not only after tool calls); model as
  `provider/id` of the last reply with a model; tokens summed over the replies **of the turn**;
  parts omitted when unknown.
- `Prompt:` printed before the turn starts (so it precedes text streamed to a non-TTY), only
  when `output = true` and `!isinteractive()`.
- `ask_user` registered without `preview` (never confirmed, so the preview was only the
  duplicate streamed line).

## Rejected

- Plain prefix matching without control-char check (`git status; rm -rf x` would be `:low`).
- Allow-list overriding protected paths (`"."` would make `LocalPreferences.toml` `:low`).
- Session-cumulative tokens (with server-side chaining each request's input already counts the
  history, so a session sum overstates).
- Skipping only the streamed preview for `_never_confirm` tools (more code, same effect).

## Revisit Trigger

Users want globs in `path_allow_list`, regex/argument-aware command rules, or session totals.
