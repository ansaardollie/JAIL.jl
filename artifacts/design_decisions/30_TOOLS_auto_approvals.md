# Decision: Per-tool auto-approvals (`tool_auto_approvals`)

| Field | Value |
|-------|-------|
| Artifact | `30_TOOLS_auto_approvals.md` |
| Category | design_decisions |
| Subject | `TOOLS` |
| Date | 2026-10-05 |
| Area/Purpose scope | public API, Preferences, REPL surface |
| Related | `29_TOOLS_security_approval_preview.md`, `28_TOOLS_groups_and_labels.md` |
| Status | accepted |
| Decided by | user (Preference key and meaning, Q&A below); agent (details listed) |

## Context

User: "a preference keyed `tool_auto_approvals` which have tool names (including group as
subkey) as keys and a true/false indicating whether that tool is auto approved (i.e. if
`JAIL.tool_auto_approvals.shell_command` is `true` then a shell command will always be approved
without confirmation regardless of security level)."

## Questions and Answers

| Question | Options | Chosen |
|---|---|---|
| Layout | `global` tools at top, others under their group; every tool under its group | **global at top, others nested** |
| Whole groups | `group = true` allowed; tools only | **allowed** |
| `false` | same as unlisted; always ask | **always ask** (even under `"yolo"`) |
| `true` vs `"all"` | true always wins; `"all"` still asks | **true always wins** |
| Ways to set | `tool_auto_approvals()` + `set_tool_auto_approval!`; `a` at the prompt; `|` commands | **all three** |

## Decision

```toml
[JAIL.tool_auto_approvals]
get_weather = true            # "global" tool
files = true                  # whole group
shell.run_shell = false       # tool in group "shell"
```

```julia
tool_auto_approvals() -> Dict{String,Any}                      # validated copy
set_tool_auto_approval!(tool, true | false | nothing)          # name, function, ToolSpec or "group:<g>"
```

Prompt: `run it? [y/N/a = always]`; `a` runs the call and saves `true` for that tool.
`|` mode: `tools approve <name|group:<g>>...` (true), `tools unapprove ...` (removes the entry);
`tools` marks `[auto-approved]` / `[always asks]`; `tools show` prints `approval: …`.

Agent-decided:

- Keys are `ToolSpec.name` (wire name). A tool's entry is looked up under its own group only.
- TOML can't hold both `group = true` and a `[group]` table, so a whole-group Bool and per-tool
  entries in that group are mutually exclusive; `set_tool_auto_approval!` on a tool of a group
  set as a whole throws, naming the `"group:<g>"` call to clear it. `"group:global"` throws.
  A global tool whose name is also a group with a table throws.
- Malformed tables throw `ArgumentError` at the start of a turn (`_chat!` reads the table) and
  in the helpers. The table is re-read per call so an `a` answer applies to later calls of the
  same turn.
- An auto-approved call skips the security function entirely.
- `needs_confirmation(call)` includes the override. Failing to save an `a` answer warns and still
  runs the call.
- `tools unapprove` removes the entry rather than writing `false`; `false` is set by hand or with
  `set_tool_auto_approval!(tool, false)`.

## Rejected

- `"all"` overriding `true` (user wanted the per-tool setting to win).
- `false` meaning "unlisted" (user wanted an always-ask switch).

## Consequences

- A tool's approval follows its name/group; renaming or regrouping a tool drops its entry.
- No public way to replace the whole table; examples restore entry by entry.

## Revisit Trigger

A need for exceptions inside a whole-group approval (e.g. a `"*"` key), per-session approvals, or
approval keyed by label instead of name.
