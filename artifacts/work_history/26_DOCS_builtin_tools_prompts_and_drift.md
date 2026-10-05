# Per-tool built-in prompts example and a docs drift pass for built-in tools

| Field | Value |
|-------|-------|
| Artifact | `26_DOCS_builtin_tools_prompts_and_drift.md` |
| Category | work_history |
| Subject | `DOCS` |
| Date | 2026-10-05 |
| Area/Purpose scope | examples, docs, docstrings |
| Related | `work_history/25_TOOLS_builtin_tools.md`, `design_decisions/31_TOOLS_builtin_tools_policy.md`, `design_decisions/32_TOOLS_builtin_tools_groups_and_rules.md`, `.github/agents/jail-developer.agent.md` |

## Scope of This Unit of Work

Follows `25_TOOLS_builtin_tools.md` (same session; nothing committed in between, so this commit
also carries 25's work). User requests:

1. "create a new builtin tools examples script ... each tool to be registered seperately and
   after each registration a single prompt that would use the tool. Be as concise as possible.
   No for loops" (no session creation).
2. "Document the JAIL.jl changes just made. Keep docs consistent with the design principles in
   .github/agents/jail-developer.agent.md."

## What Changed

| File | Change |
|-------|--------|
| `examples/builtin_tools_prompts.jl` (new) | 25 × `register_builtin_tools!(:tool)` + one `chat!(...; stream = true)` prompt on the active session; edits happen in `scratch/` (left behind); `pkg_add` asks to add Example |
| `docs/src/index.md` | Status: built-in tools bullet; removed them from "Not implemented yet" (the `&` mode stays planned); links to the Tools guide and the Built-in tools page |
| `docs/src/guide/concepts.md` | Tools section mentions the opt-in built-ins; "Planned" marks only the `&` mode as planned |
| `docs/src/guide/tools.md` | group auto-approval no longer called "safe" (an auto-approval skips the security level, so `read = true` reads outside the workspace without asking); `execute_julia_code` is confirmed unless `"yolo"` or auto-approved; long values shortened |
| `src/tools.jl` | `needs_confirmation` and `tool_auto_approvals` docstrings: `ask_user` is never confirmed |
| `src/chat.jl` | `chat!` docstring: `ask_user` exception, pointer to `tool_context` |
| `artifacts/todos/pending/2_REPL_real_terminal_check.md` | item 11: built-in tools in a real terminal |

## Decisions

None new. The docs pass applied decisions 31/32 and principle 8 (confirm model code before it
runs unless a preference disables it).

## Verification

```
julia --project=docs docs/make.jl   # baseline: exit 0, no Warning/Error lines; after: exit 0, none
grep -rl "dhd-prima\|gpt-6-luna" docs/build   # nothing
needs_confirmation(c; approval = "auto") = true      # read_file("/etc/hosts")
needs_confirmation(c; approval = "all") = false      # after set_tool_auto_approval!("group:read", true)
needs_confirmation(ToolCall("c", "ask_user", ...); approval = "all") = false   # with ask_user = false
register_tool!(session_name; security = :low) = ToolSpec(session_name())       # tool_context docstring example
read("LocalPreferences.toml", String) == lp = true
```

Housekeeping load check: `length(builtin_tools()) = 25`, `isdefined(JAIL, :tool_context) = true`;
`examples/builtin_tools_prompts.jl` parses with 25 registrations. **The prompts example was not
run** (every prompt is a live model call).

## Known Limitations

- `examples/builtin_tools_prompts.jl` is unverified, leaves `scratch/`, and its `run_tests`
  prompt fails on JAIL (no `test/`).
- The docs don't link individual example scripts.
- `src_helpers_claude.jl` (owner's helper, ported into `src/builtin_tools/source.jl`) is left
  untracked at the repo root, not committed.

## Todos

- Completed: none
- Created: none
- Updated: `2_REPL_real_terminal_check.md` (item 11)

## Next Steps

1. Owner: run `examples/builtin_tools_prompts.jl` live and `examples/builtin_tools.jl` in a
   terminal (todo 2 item 11); delete or move `src_helpers_claude.jl`.
2. Plan the `&` agentic mode (todo 5 item 4).
3. Port the work-history-25 checks into `test/` (todo 1).
