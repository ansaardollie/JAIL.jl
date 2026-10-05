# Allow-lists, `remove_file`, and the `Response (...)` / `Prompt:` turn display

| Field | Value |
|-------|-------|
| Artifact | `30_TOOLS_allow_lists_remove_file_display.md` |
| Category | work_history |
| Subject | `TOOLS` |
| Date | 2026-10-05 |
| Area/Purpose scope | built-in tools, chat display, docs, examples |
| Related | `design_decisions/35_TOOLS_allow_lists_remove_file_response_header.md`, `work_history/29_TOOLS_ask_user_free_text_edit_file.md` |

## Scope of This Unit of Work

Follows `29_TOOLS_ask_user_free_text_edit_file.md` (commit `0e4d63b`; `4918cc6` is an owner save
point). Two user requests:

1. `remove_file` tool; `path_allow_list` and `command_allow_list` Preferences lowering
   edit/remove and `run_shell` calls to `:low`.
2. `Output:` → `Response (<model>; N in; M out):`; `Prompt:` section when not interactive;
   no duplicated question when `ask_user` streams.

## What Changed

| File | Change |
|-------|--------|
| `src/builtin_tools/common.jl` | `_real_path`, `_allow_listed` (Preference `path_allow_list`, protected wins, real-path compare); `_write_level` returns `:low` when allow-listed; `builtin_tools()` table lists `remove_file` |
| `src/builtin_tools/files.jl` | `remove_file(path)`; `_builtin!(remove_file; group = "edit", label = "Delete file", security = path -> _write_level(path, :high))` |
| `src/builtin_tools/process.jl` | `_SHELL_CONTROL`, `_shell_level` (Preference `command_allow_list`); `run_shell` security = `_shell_level` |
| `src/builtin_tools/repl.jl` | `ask_user` registered without `preview` |
| `src/repl/chat_mode.jl` | `_render_response_header` (model of last reply, tokens summed over the turn), `_render_prompt`; `_display_turn` prints `Prompt:` first when `output && !isinteractive()`, and the header on every rendered turn |
| `src/chat.jl` | `chat!` docstring mentions the header and `Prompt:` |
| `docs/make.jl` | `path_allow_list`, `command_allow_list` in `__clear__` |
| `docs/src/guide/tools.md` | `remove_file` row, `run_shell` "low if allow-listed", new "Allow-listed paths and commands" section, Preferences list |
| `docs/src/guide/providers.md` | Preference table rows |
| `docs/src/guide/repl.md` | `Response (...)` heading text and example |
| `docs/src/builtin_tools.md` | `remove_file` docstring |
| `examples/LocalPreferences.toml`, `examples/builtin_tools.jl`, `examples/tools.jl`, `examples/tool_security.jl` | new Preferences commented; 27 tools; `Response (...)` wording |

Not part of this commit (found in the tree, not made by this session): `Project.toml` gained an
`Example` dependency, and `scratch/hello.jl` exists — likely from live tool runs (`pkg_add`,
`create_file`). Left uncommitted for the owner.

## Decisions

- `35_TOOLS_allow_lists_remove_file_response_header.md`.

## Verification

REPL (prefs set with `_save_pref!`, then deleted; both were `nothing` before):

```
r1 = (:medium, :medium, :high, :high, :medium, :high)   # no allow list
r2 = (:low, :low, :low, :high, :high, :high, :high, :low)
#   allow ["scratch","src/x.jl",<tmp>/ok,"."]: scratch/x.txt, src/x.jl, <tmp>/ok/a.txt,
#   <tmp>/ok/link/hosts (link→/etc) :high, Project.toml/.git/config/.jail/x :high, docs/x.md :low
r3 = (:medium, :low, :medium, :low, :high)   # src/y.jl, src/x.jl, scratchy/a, remove_file scratch/z, remove_file src/z
"git status" => :low   "git status --short" => :low   "git statusx" => :high   "git stash" => :high
"  ls -la" => :low     "ls; rm x" => :high   "git status && rm x" => :high   "ls $(pwd)" => :high
"ls > f" => :high      "git status\nrm x" => :high   "julia --version" => :low   "lsof" => :high
```

`remove_file`: deleted a file; "no file" for missing; "is a folder" refused; removing a symlink
to `/etc` left `/etc` intact.

Display helpers on hand-built messages:

```
Prompt:
  What is x?
    •  a
    •  b

Response (anthropic/claude-sonnet-4-5; 250 in; 50 out):
Response:                       # reply with no model/usage
  Done now.
```

`builtin_tools()` has 27 entries; `ask_user` preview is `nothing`. Docs:
`julia --project=docs docs/make.jl` — 0 warnings/errors. `Pkg.test()` passes (suite is empty).

**Not verified:** a full `chat!(...; stream = true)` from `julia script.jl` (the owner skipped the
mock-server script); the streamed `ask_user` line in a real terminal; Windows control chars.

## Known Limitations

- With streaming to a non-TTY, the text is streamed raw and no `Response (...)` header is shown.
- `command_allow_list` allows any arguments after the prefix (e.g. `git -c ...` for `"git"`).
- `path_allow_list` has no globs; `_allow_listed` reads the Preference on every call.
- Token sums are per turn, not per session.

## Todos

- Completed: none
- Created: none
- Updated: none

## Next Steps

1. Owner: run a script with `chat!(...; stream = true)` via `julia script.jl` to see `Prompt:`
   and `Response (...)`; try `ask_user` streamed in a terminal.
2. Decide what to do with the `Example` dependency in `Project.toml` and `scratch/`.
3. Tests for `_shell_level` / `_write_level` allow-lists when the suite is set up (todo 1).
