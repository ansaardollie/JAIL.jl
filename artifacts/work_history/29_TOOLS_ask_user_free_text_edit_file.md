# `ask_user` free-text option and the line-based `edit_file` tool

| Field | Value |
|-------|-------|
| Artifact | `29_TOOLS_ask_user_free_text_edit_file.md` |
| Category | work_history |
| Subject | `TOOLS` |
| Date | 2026-10-05 |
| Area/Purpose scope | built-in tools, docs, examples |
| Related | `design_decisions/34_TOOLS_ask_user_free_text_and_edit_file.md`, `work_history/28_TOOLS_live_run_fixes.md` |

## Scope of This Unit of Work

Follows `28_TOOLS_live_run_fixes.md` (commit `4997932`). The `ask_user` change was committed by
the owner as `0ea49b6 save point`; this commit adds `edit_file` and a docs pass.

1. `ask_user` gains `allow_free_text::Bool = true`.
2. New `edit_file(path, edits)` with `remove` / `add` / `replace` line edits over the original
   numbering.
3. "Document the JAIL.jl changes just made" — docs pass.

## What Changed

| File | Change |
|-------|--------|
| `src/builtin_tools/repl.jl` (in `0ea49b6`) | `ask_user(question, options, allow_free_text = true)`; "Other" menu choice; `_free_text_answer`; numbered prompt re-asks when free text is not allowed |
| `src/builtin_tools/files.jl` | `LineEdit` struct, `_plan_line_edits` (validate, collect removes/replaces/adds per original line), `_apply_line_edits` (rebuild via `IOBuffer`, keep line endings), `edit_file`, `_line_edits_preview`, `_builtin!(edit_file; group = "edit", ...)`; docstring says lines count from 1 (read_file doesn't number lines) |
| `src/builtin_tools/common.jl` | `builtin_tools()` docstring lists `edit_file` |
| `docs/src/guide/tools.md`, `docs/src/builtin_tools.md`, `docs/src/index.md` | `ask_user` row (in `0ea49b6`); `edit_file` row and docstring; 26 tools |
| `examples/builtin_tools.jl`, `examples/builtin_tools_prompts.jl` | 26 tools / edit list; `edit_file` prompt; strict `ask_user` prompt (in `0ea49b6`) |

## Decisions

- `34_TOOLS_ask_user_free_text_and_edit_file.md` (names, literal replacement text, String
  `action`; rejected: capture substitution, shifting line numbers).

## Verification

`ask_user` with piped stdin:

```
(number or your own answer) > => "blue"          # "2"
(number or your own answer) > => "teal please"
(number) > Please enter a number from 1 to 2.    # "teal", "9" with allow_free_text = false
(number) > => "red"
Any["q", ["a", "b"], false]                      # model JSON converts
```

`edit_file` on `line1..line5` with six edits in one call:

```
Edited `jail_test_9zlgmo/a.jl`: 3 line(s) removed, 4 added, 1 changed; it now has 6 lines.
top / line1 / after2a / after2b / L$1 / end
... line 9 out of range / pattern matches nothing / line 1 is both removed and replaced /
    unknown action / `text` is required / invalid regular expression — all refused
read(f, String) == before = true
read(f, String) = "A\r\nb\r\nc\r\n"     # CRLF, no final newline, add after last line
read(f, String) = "first\n"             # empty file, add at 0
security_level: :medium (scratch file), :high (Project.toml)
```

Docs: `julia --project=docs docs/make.jl` exit 0, no warnings; the corrected docstring is on the
Built-in tools page. Load check: `length(builtin_tools()) = 26`, `isdefined(JAIL, :edit_file) = true`.

**Not verified:** the TTY "Other" menu choice; `edit_file` driven by a live model.

## Known Limitations

- `read_file` shows lines without numbers, so the model counts lines itself.
- Replacement `text` is literal; no capture groups.
- Built-in specs are cached per process: a session that already used them keeps old descriptions
  until restart.

## Todos

- Completed: none
- Created: none
- Updated: none

## Next Steps

1. Owner: try the "Other" choice and `edit_file` live (todo 2 item 11 covers built-ins).
2. Consider numbered `read_file` output if models misnumber lines (decision 34 revisit trigger).
3. `&` mode plan (todo 5), tests (todo 1).
