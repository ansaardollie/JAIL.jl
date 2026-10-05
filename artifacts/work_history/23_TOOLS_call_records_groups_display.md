# Tool call records, `}` tool display, tool groups and labels

| Field | Value |
|-------|-------|
| Artifact | `23_TOOLS_call_records_groups_display.md` |
| Category | work_history |
| Subject | `TOOLS` |
| Date | 2026-10-05 |
| Area/Purpose scope | core ontology, persistence, public API, REPL surface, docs |
| Related | `design_decisions/27_TOOLS_call_records_and_display.md`, `design_decisions/28_TOOLS_groups_and_labels.md`, `design_decisions/18_TOOLS_session_tools_and_call_loop.md`, `design_decisions/24_SESSION_persistence.md`, `work_history/22_DOCS_reasoning_and_providers.md` |

## Scope of This Unit of Work

Not from 22's next steps (those are owner actions). User requests, in order:

1. "When streaming output from the model and `confirm_tools` is set to false, none of the tool
   calls are actually displayed ... serialise the tool call requests and responses under
   `.jail/tools` ... a folder per session and JSON file per tool call/result pair ... a uuid7 id
   ... a display of all the tool calls along with hypertext links (using the OSC 8 ...)".
2. Revision after trying it: stream lines only on the streaming screen; finished turn shows tool
   calls first, then the response; link text `View`; tool groups (`@tool group=shell f`,
   `register_tool!(f; group="shell")`, default global set); a settable display name shown
   without parentheses.
3. Follow-up: an `Output:` heading between the block and the reply; underline only `View`.

## What Changed

| File | Change |
|-------|--------|
| `src/ontology/messages.jl` | `ToolResult` gains `id::Union{Nothing,UUID}` (kwarg `id = nothing`), docstring |
| `src/ontology/tools.jl` | `ToolSpec` gains `group::String`, `label::String`; text/plain show prints `group: …, label: …` |
| `src/tools.jl` | `register_tool!(f; group = "global", label = nothing)`; `_group_name` (`^[A-Za-z0-9_.-]+$`), `_label`; `@tool` parses `group=` / `label=` options (label only with one function); `tools(group)` (throws for unknown group), `_tool_groups`, `_tool_label(name)` |
| `src/persistence.jl` | `_tools_dir`, `_tool_record_path`, `_record_tool!` (assigns `uuid7()`, writes `<dir>/tools/<session id>/<pair id>.json` under `_guard`); JSONL `tool_result` part carries `"id"`, restored as `UUID`; `_delete_files!` removes the tools folder; `restore_session!` docstring |
| `src/chat.jl` | `_tool_loop!` records every result (incl. "not run" limit results); `_print_tool` shows `→ label` (cyan) / `← label: result` |
| `src/repl/chat_mode.jl` | `_chat_send` rewritten: transient status line (`thinking…` / `→ label…`) without streaming, tool lines on the alternate screen when streaming; finished turn = `_render_tool_summary` (`✓`/`✗`, label, OSC 8 `View` via `_hyperlink`/`_file_url`, path when not a TTY) + bold `Output:` + `_render_texts` (all reply texts as one Markdown doc). Removed `_render_text`, `_render_turn` |
| `src/repl/model_mode.jl` | `tools` listing grouped (label shown when ≠ name); `tools use/add/drop` accept `group:<g>` (`_expand_tool_args`); completion offers `group:<g>`; help/usage text |
| `docs/src/guide/{repl,tools,sessions}.md` | Tool display, `Groups and labels` section (runnable `list_files` example), tool record files, REPL commands and transcript |
| `examples/tools.jl` | Header; section 2b (groups, labels, misuse); `set_tools!(s, tools("files"))`; LIVE section reads a record file; unknown-group error |
| `examples/session_persistence.jl` | Header lists `tools/<id>/<pair id>.json` |
| `artifacts/todos/pending/2_REPL_real_terminal_check.md` | Item 9: terminal checks for the new display |

## Decisions

- `design_decisions/27_TOOLS_call_records_and_display.md` (+ amendment): core loop writes
  records gated by `persist_sessions` (rejected: own Preference, REPL only); pair id also on
  `ToolResult` (rejected: file only); finished turn block-then-all-texts (rejected: inline +
  summary, which the user chose first and then revised; last reply only); `View` link text
  (rejected: relative path, short id, signature); transient non-stream status (rejected: live
  lines kept); label-only call lines (rejected: label + arguments).
- `design_decisions/28_TOOLS_groups_and_labels.md`: separate display `label` (rejected: wire
  `name =` override; keywords `display_name`, `title`); groups label + snapshot selection via
  `tools(group)` / `group:<g>` (rejected: dynamic group membership on sessions; label only).

## Verification

Mock Anthropic server (`HTTP.serve!` on 127.0.0.1:8765, SSE and JSON fixtures, temp
`storage_dir`), `JAIL._chat_send(IOContext(buf, :color => …), prompt; tty)`:

```
== stream, tty:
"thinking…\r\e[2K\e[?1049h\e[H\e[2Jchat> Rome?\n\nLet me check.\n→ get_weather\n← get_weather: Sunny in Rome\n→ Shell command\n← Shell command error: `run_shell_bang` threw an error: not allowed: ls\nSunny in **Rome**.\e[?1049lTool calls (2):\n  ✓ get_weather    \e]8;;file:///…/01a1099d-03aa-….json\e\\View\e]8;;\e\\\n  ✗ Shell command  \e]8;;file:///…\e\\View\e]8;;\e\\\n\n  Let me check.\n\n  Sunny in Rome.\n"
== no stream, tty:
"thinking…\r\e[2K→ get_weather…\r\e[2Kthinking…\r\e[2K→ Shell command…\r\e[2Kthinking…\r\e[2KTool calls (2): …"
```

After the `Output:` / underline follow-up (colour on):

```
… \e[36mlist_files  \e[39m\e[90m\e[4m\e]8;;file:///…/01a109a4-bf7c-….json\e\\View\e]8;;\e\\\e[24m\e[39m\n\n\e[0m\e[1mOutput:\e[22m\n  The directory contains \e[1mfiles\e[22m.\n
```

Record file (abridged): `{"version":1,"id":"01a1099d-04bf-…","session_id":"01a1099c-eb16-…","model":"anthropic/claude-x","started":"2026-10-05T01:10:47.729Z","finished":"…743Z","duration_ms":14,"tool":{"name":"run_shell_bang","label":"Shell command","group":"shell"},"call":{"id":"toolu_2","name":"run_shell_bang","arguments":{"cmd":"ls"}},"result":{"content":"`run_shell_bang` threw an error: not allowed: ls","is_error":true}}`.
JSONL `tool_result` lines carry `"id"`; `_load_session` restores the same UUIDs.

Also checked: not-a-TTY (path instead of `View`), `persist_sessions = false` (no path, `id`
still set), `max_tool_rounds = 0` (two `✗` records, `[stop reason: tool_use]`),
`delete_session!(s; files = true)` → `isdir(tools dir) = false`; model mode:

```
Session "mock" uses every registered tool:
  global
  * get_weather     Weather for a city.
  shell
  * run_shell_bang  Run a shell command. ("Shell command")
Session "mock" tools: run_shell_bang          # tools use group:shell
JAIL._complete_model_mode("tools use gr") = (["group:global", "group:shell"], "gr")
ArgumentError: no tools in group "nope" (groups: global, shell)
```

`@tool` misuse: `label=` with two functions, `group="bad name"`, `colour=red`, no function →
`ArgumentError`s; blank label → `a tool label must not be empty`. `examples/tools.jl` offline
parts ran in a fresh REPL (LIVE section **not run**). Docs built with no warnings
(`julia --project=docs docs/make.jl`). Housekeeping load check:

```
fieldnames(ToolSpec) = (:name, :description, :parameters, :f, :group, :label)
fieldnames(ToolResult) = (:call_id, :name, :content, :is_error, :id)
hasmethod(register_tool!, Tuple{Function}, (:group, :label)) = true
```

`LocalPreferences.toml` confirmed back to the owner's content after each test run.
**No live provider calls; nothing seen in a real terminal.**

## Known Limitations

- The original "tool calls not displayed" report was not reproduced (Anthropic SSE mock showed
  the lines); dim `light_black` on the owner's theme is a guess. Google Interactions streaming
  with tools was not mocked.
- Results rolled back with a failed later turn leave orphan record files.
- `duration_ms` includes the `confirm_tools` prompt time.
- Re-registering replaces the whole spec: relabelling without `group=` moves a tool to `global`.
- `set_tools!(s, tools(g))` is a snapshot; tools added to the group later are not included.
- No public accessor for a record's path; `examples/tools.jl` assumes `.jail`.
- `chat!(...; stream = true)` prints labelled lines but no `Tool calls` block.

## Todos

- Completed: none
- Created: none
- Updated: `2_REPL_real_terminal_check.md` (item 9)

## Next Steps

1. Owner: run `}` with a tool in VS Code's terminal (todo 2, item 9) to confirm OSC 8 `View`
   and that calls now show with Google Enterprise streaming.
2. `5_TOOLS_builtin_tools.md`: built-in tools can now use groups (e.g. `group = "julia"`).
3. `1_TESTS_test_suite_setup.md`: port the mock-server checks above.
