# Tool security levels, approval modes, argument previews and per-tool auto-approvals

| Field | Value |
|-------|-------|
| Artifact | `24_TOOLS_security_approval.md` |
| Category | work_history |
| Subject | `TOOLS` |
| Date | 2026-10-05 |
| Area/Purpose scope | public API, Preferences, REPL surface, docs, examples |
| Related | `design_decisions/29_TOOLS_security_approval_preview.md`, `design_decisions/30_TOOLS_auto_approvals.md`, `design_decisions/18_TOOLS_session_tools_and_call_loop.md` (superseded in part), `work_history/23_TOOLS_call_records_groups_display.md` |

## Scope of This Unit of Work

Follows `23_TOOLS_call_records_groups_display.md` (commit `bde7017`); not from its next steps.
User requests, in order:

1. "implement tool security levels ... low, medium, high ... static level or ... a level function
   that takes as input the given arguments" with a confirmation Preference `all`/`auto`/`none`/
   `yolo` and the matrix in decision 29; defaults `:medium` / `"auto"`. Plus "which arguments
   should be displayed and how ... just display the code/command".
2. "create a new tools example which showcase these various tool levels/display".
3. Fix the preview showing twice; add public helpers; "if the tool call doesn't provide an
   argument then security/preview invocation should be done with a nothing value".
4. "a preference keyed `tool_auto_approvals` which have tool names (including group as subkey)
   as keys and a true/false".
5. Documentation pass against `.github/agents/jail-developer.agent.md`.

Also answered (no code change): with `tool_approval = "none"`, a `:low` tool runs unasked by
design (matrix); what a "tool id" is (`ToolSpec.name`, `ToolCall.id`, `ToolResult.id`).

## What Changed

| File | Change |
|-------|--------|
| `src/ontology/tools.jl` | `ToolSpec` gains `security::Union{Symbol,Function}`, `preview::Union{Nothing,String,Vector{String},Function}`; show prints them |
| `src/tools.jl` | `register_tool!(...; security = :medium, preview = nothing)` + validation (`_security_spec`, `_preview_spec`); `@tool` options `security=` / `preview=` (`_tool_option`); `tool_approval()` (warns once if `confirm_tools` is set), `set_tool_approval!`, `_needs_confirmation` matrix, `_security_level` / `_preview_text` (functions get `_padded` args: `nothing` for omitted optionals; throw/invalid ⇒ `:high`), `security_level`, `needs_confirmation`, `tool_preview` (on `ToolCall`, via `_spec_and_args`); `tool_auto_approvals()`, `set_tool_auto_approval!`, `_auto_approval`, `_confirmation_needed`; `_confirm` returns `:yes/:no/:always`, prompt `[y/N/a = always]`, one-line form when the preview was streamed; `_run_tool(c, specs; approval, before_confirm)` (`a` saves `true`) |
| `src/chat.jl` | `_chat!` reads `tool_approval()` and validates `tool_auto_approvals()` up front; `_Confirming` step event (returns `true` when the preview is on screen); `_print_tool` prints the preview under `→ label`; `chat!` docstring |
| `src/repl/chat_mode.jl` | `_Confirming` clears the transient status, returns `stream` |
| `src/repl/model_mode.jl` | `tools approve|unapprove <name|group:g>...`, `[auto-approved]`/`[always asks]` marks, `approval:` in `tools show`, completion, help |
| `src/JAIL.jl` | exports `tool_approval, set_tool_approval!, security_level, needs_confirmation, tool_preview, tool_auto_approvals, set_tool_auto_approval!` |
| `examples/tool_security.jl` | new: five demo tools (levels, previews, `nothing`-padded `overwrite`), helper table across modes, auto-approval section, scripted local Responses server driving `chat!(...; stream = true)`, restores Preferences |
| `examples/tools.jl`, `examples/LocalPreferences.toml` | header/Preferences (`tool_approval`, `tool_auto_approvals` as dotted keys); section 2c |
| `docs/src/guide/{tools,repl,chat,concepts,providers}.md`, `docs/src/{index,reference}.md`, `docs/make.jl` | security levels & approval, previews, auto-approvals, checking a call, REPL prompt and commands, Preferences table, reference entries, `__clear__` keys |

## Decisions

- `29_TOOLS_security_approval_preview.md` (+ amendment): new key `tool_approval` (rejected:
  reuse `confirm_tools` with or without boolean mapping); `security` keyword (rejected: `risk`,
  `level`); functions take `f`'s args (rejected: Dict) with `nothing` for omitted optionals;
  `preview` with three forms (rejected names: `display`, `show_args`), shown in prompt + stream
  (rejected: in the Tool calls block); Preference-only control (rejected: per-call kwarg and
  `/confirm`); helpers on `ToolCall` only (rejected: `(spec, args...)` too).
- `30_TOOLS_auto_approvals.md`: global tools at top level, others under their group (rejected:
  always nested); whole-group Bool allowed; `false` = always ask (rejected: same as unlisted);
  `true` wins over `"all"`; `set_tool_auto_approval!`, `a` at the prompt, `tools approve` all
  added.
- `18_TOOLS_...` marked superseded in part (`confirm_tools`).

## Verification

Matrix and runner (REPL, piped stdin):

```
low    Bool[1, 0, 0, 0]
medium Bool[1, 1, 0, 0]
high   Bool[1, 1, 1, 0]
== non-stream (no hook): "Julia code [high]\n    1 + 1\nRun it? [y/N] "
== stream hook returns true: "Julia code [high]: run it? [y/N] "
== junk level ("low" String), none → counts as :high with a warning
```

Auto-approvals (all/auto/none/yolo for get_weather low, run_shell high, list_files medium):

```
no entries:               [1,0,0,0]  [1,1,1,0]  [1,1,0,0]
get_weather = true:       [0,0,0,0]  [1,1,1,0]  [1,1,0,0]
shell.run_shell = false:  [0,0,0,0]  [1,1,1,1]  [1,1,0,0]
files = true:             [0,0,0,0]  [1,1,1,1]  [0,0,0,0]
"run_shell [high]\n    ls\nRun it? [y/N/a = always] " => ran; tool_auto_approvals() = shell => {run_shell => true}
next call: printed "" => ran without asking
```

`examples/tool_security.jl` run with answers `a y n y` (MODE `"auto"`), excerpt:

```
ToolCall(copy_file(dst = "backup/a.txt", src = "a.txt"))   medium  ask   ask   -     -     a.txt → backup/a.txt
save_note, approved:        -     -     -     -
current_time, always ask:   ask   ask   ask   ask
→ Julia code
    total = sum(1:10)
    total * 2
Julia code [high]: run it? [y/N/a = always] ← Julia code: 110
read(lp, String) == old_lp = true
```

`examples/tools.jl` offline parts ran in a fresh REPL. Docs: baseline and final builds both 0
warnings (`julia --project=docs docs/make.jl`; grep for Warning/Error/missing docs/not found/failed
empty; no owner values in `docs/build`). Housekeeping load check:

```
isdefined(JAIL, :set_tool_auto_approval!) = true
fieldnames(ToolSpec) = (:name, :description, :parameters, :f, :group, :label, :security, :preview)
hasmethod(needs_confirmation, Tuple{ToolCall}) = true
```

`LocalPreferences.toml` compared byte-for-byte after each test that wrote Preferences.
**No live provider calls; nothing seen in a real terminal.**

## Known Limitations

- With the defaults (`"auto"`, `:medium`) every call of an unannotated tool is confirmed; the
  owner's `confirm_tools = false` is ignored with a warning.
- Tool record JSON files don't store the security level or how the call was approved.
- A whole-group auto-approval can't have per-tool exceptions (TOML); no `"*"` key.
- `@tool security=typo f` gives `UndefVarError` (non-level names are treated as functions).
- No public way to replace the whole `tool_auto_approvals` table, or to tell an unset
  `tool_approval` from an explicit `"auto"`.
- `tools unapprove` removes the entry; `false` only via `set_tool_auto_approval!` or by hand.
- The scripted model in `examples/tool_security.jl` only answers its six prompts.

## Todos

- Completed: none
- Created: none
- Updated: `2_REPL_real_terminal_check.md` (item 10), `5_TOOLS_builtin_tools.md` (use
  `security = :high, preview = :code` for `execute_julia_code`)

## Next Steps

1. Owner: run `examples/tool_security.jl` in a terminal REPL per todo 2 item 10.
2. Owner: decide whether tool records should include `security` and approval outcome.
3. `5_TOOLS_builtin_tools.md`: `execute_julia_code` on the new approval machinery.
4. `1_TESTS_test_suite_setup.md`: port the matrix / prompt / auto-approval checks above.
