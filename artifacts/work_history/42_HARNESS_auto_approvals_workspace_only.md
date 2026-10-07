# Auto-approvals stop at the workspace for built-in path tools

| Field | Value |
|-------|-------|
| Artifact | `42_HARNESS_auto_approvals_workspace_only.md` |
| Category | work_history |
| Subject | `HARNESS` — agent/skill approvals (also `TOOLS` auto-approvals) |
| Date | 2026-10-07 |
| Area/Purpose scope | tool approval, docs |
| Related | `41_HARNESS_agent_mode_agents_and_skills.md`, `design_decisions/46_HARNESS_agent_mode_agents_and_skills.md` (amendment 2026-10-07), `design_decisions/30_TOOLS_auto_approvals.md` (superseded in part) |

## Scope of This Unit of Work

Follows `41_...`. The owner's commits `0f27100` / `b9552ca` ("save point") hold the `&` prompt in
the Julia logo purple (24-bit `prompt_prefix` set after `initrepl`, shared `_rgb_escape` in
`src/repl/chat_mode.jl`). This unit: owner asked whether agent `tools` / skill `allowed-tools`
still respect protected paths and the workspace rule. They didn't (auto-approval forced level
`:low`). Owner: "auto approval for editing/writing/creating files should only be for workspace
local changes. Anything outside workspace should always need approval (unless in path_approval_list)".

## What Changed

| File | Change |
|-------|--------|
| `src/builtin_tools/common.jl` | `_PATH_GUARDS::IdDict{Function,Function}`, `_outside`, `_read_guard`, `_write_guard` |
| `src/builtin_tools/files.jl`, `src/builtin_tools/julia.jl` | guards for `read_file`, `list_dir`, `check_julia_syntax` (read) and `create_file`, `create_directory`, `replace_in_file`, `replace_in_files`, `edit_file`, `remove_file` (write) |
| `src/tools.jl` | `_approval_override`, `_path_guarded`; used by `_prepare_tool` and `_confirmation_needed` (`needs_confirmation`); `tool_auto_approvals` docstring |
| `docs/src/guide/tools.md`, `docs/src/guide/agents.md` | auto-approval sections describe the cap |
| decisions 46 (amendment), 30 (superseded-in-part line) | recorded |

## Design Decisions Made

Decision 46 amendment (2026-10-07), owner answers: protected writes also ask (rejected: only
outside writes); the cap applies to agent `tools`, skill `allowed-tools` and `tool_auto_approvals`
(rejected: agent/skill only); every built-in path tool, reads included (rejected: edit group only).
Agent-decided: a guarded call falls back to security level + `tool_approval`, so `"yolo"` still
runs it unasked; guards keyed by function, so a same-named user tool isn't guarded; a throwing
guard counts as guarded.

## Verification

`needs_confirmation(...; approval = "auto")` with `read_file` and `group:edit` auto-approved
(`true` = asks), last two with `path_allow_list = ["/tmp"]`:
```
(read_in = false, read_out = true, create_in = false, create_out = true, create_dotdot = true,
 protected = true, remove_in = false, multi_mixed = true, create_out_allowed = false, read_out_allowed = false)
read("LocalPreferences.toml", String) == before = true
```
`_prepare_tool` in an `_AgentTurn` whose `auto` is `{read_file, create_file}` (a confirmation
hook records and interrupts):
```
((true, true, true, true), ["read_file", "create_file"])
```
i.e. `src/JAIL.jl` and `scratch/new.jl` ran unasked; `/etc/hosts` and `LocalPreferences.toml`
reached the prompt. Docs build: exit 0, no warnings. `using JAIL` loads.

## Known Limitations

- Non-path tools (`run_shell`, `fetch_url`, `http_request`) keep the full bypass when approved.
- `_read_level` doesn't consult `path_allow_list`, so an unapproved read of an allow-listed outside
  path is still `:high`; only the auto-approval guard honours the list for reads.
- No example script demonstrates the cap.

## Todos

- Completed: none.
- Created: none (`12_HARNESS_live_checks_and_gates.md` still open).

## Next Steps

- `todos/pending/12_HARNESS_live_checks_and_gates.md`.
- Optionally show the cap in `examples/tool_security.jl`.
