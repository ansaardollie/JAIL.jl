# Generated text of tool calls saved as files and linked from the Tool calls box

| Field | Value |
|-------|-------|
| Artifact | `43_TOOLS_generated_text_files.md` |
| Category | work_history |
| Subject | `TOOLS` |
| Date | 2026-10-08 |
| Area/Purpose scope | persistence, REPL display, docs |
| Related | `42_HARNESS_auto_approvals_workspace_only.md`, `design_decisions/47_TOOLS_generated_text_files.md` |

## Scope of This Unit of Work

Follows `42_...` (commit `18b65c6`). Owner wanted generated code / commands / file contents
readable as files rather than `\n`-escaped JSON strings, with a link in the Tool calls box. Then a
documentation pass.

## What Changed

| File | Change |
|-------|--------|
| `src/persistence.jl` | `_GENERATED`, `_GENERATED_TYPES`, `_generated_dir`, `_save_generated`, `_generated_file`; `_record_tool!` writes the file and a `generated` field; `_delete_files!` removes `generated/<type>/<session id>`; `restore_session!` docstring |
| `src/builtin_tools/{julia,process,files}.jl` | `_GENERATED` entries for `execute_julia_code` (code, `.jl`), `run_shell` (shell, `.sh`), `create_file` (file, path extension or `.txt`) |
| `src/repl/chat_mode.jl` | `_render_tool_rows` adds `View Generated <type>` after `View` |
| `src/ontology/messages.jl` | `ToolResult` docstring: `agent!` sets `id` (was `chat!`, drift), generated path |
| `docs/src/guide/{sessions,repl,tools}.md` | saved-files list, Tool calls box, tool loop |
| `examples/tools.jl`, `examples/builtin_tools.jl` | header comments |

## Design Decisions Made

`design_decisions/47_TOOLS_generated_text_files.md` (pair id as folder name; three built-ins only;
saved whatever the outcome).

## Verification

Scripted Responses server, temp `storage_dir`, `tool_approval = "yolo"` (restored), one `agent!`
turn with four calls:
```
execute_julia_code => ("code", ".../generated/code/<session>/<id>/generated.jl")
run_shell => ("shell", ".../generated/shell/<session>/<id>/generated.sh")
create_file => ("file", ".../generated/file/<session>/<id>/generated.jl")
read_file => nothing
"x = 1 + 1\nprintln(x)"
record generated: .../generated/file/.../generated.jl
true                     # tty rendering contains "View Generated code"
generated left: false    # after delete_session!(s; files = true)
true                     # LocalPreferences.toml byte-identical
```
Docs build: exit 0, no warnings. `using JAIL` loads. Links not checked on a real terminal;
`examples/builtin_tools.jl` not re-run (needs terminal answers).

## Known Limitations

- Edit fragments (`replace_in_file`, `replace_in_files`, `edit_file`) are not saved.
- User tools can't declare generated text.
- Design principle 10 ("each mode's prompt shows the active model") disagrees with the `&`
  (agent name) and `}` (bare `chat> `, decision 14 amendment) prompts; flagged to the owner.

## Todos

- Completed: none.
- Created: none (`12_HARNESS_live_checks_and_gates.md` still open).

## Next Steps

- `todos/pending/12_HARNESS_live_checks_and_gates.md`.
- Owner: update principle 10 or the prompts.
