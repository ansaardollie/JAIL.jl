# TODO: Built-in tools (`execute_julia_code`, source lookup) and the `&` mode

| Field | Value |
|-------|-------|
| Artifact | `5_TOOLS_builtin_tools.md` |
| Category | todos |
| Subject | `TOOLS` |
| Date created | 2026-09-28 |
| Area/Purpose scope | tools, REPL surface, public API |
| Related | `work_history/11_TOOLS_tool_calling.md`, `design_decisions/18_TOOLS_session_tools_and_call_loop.md`, redesign notes #5 and #8 |
| Priority | high |
| Owner | any |

## What

1. `execute_julia_code`: runs model-provided code, captures all output, and asks the user to
   confirm before every run unless a Preference disables it. Ask the owner for the name, the
   module it evaluates in, and how output/errors are returned. Confirmation now exists
   generically (`design_decisions/29_TOOLS_security_approval_preview.md`,
   `30_TOOLS_auto_approvals.md`): register it with `security = :high, preview = :code` (and a
   group, e.g. `"julia"`) rather than adding a separate Preference.
2. Source lookup (`*_source_def`): given a type/method/module, return its source definition.
3. How built-ins relate to the registry: auto-registered, opt-in, or only in the `&` mode.
4. The `&` agentic REPL mode using them.

## Why

Redesign note #8 lists both built-ins as core; the loop from `11_TOOLS_tool_calling.md` now
exists to run them.

## Acceptance Criteria

- [x] Decisions recorded for names, Preferences and registration (decisions 31, 32)
- [x] Confirmation enforced before running model-written code (agent constraint)
- [ ] Mock-server tool round per provider using a built-in (Responses, Chat Completions,
      Anthropic done; Google not)
- [x] `examples/builtin_tools.jl` and docs updated
- [ ] The `&` agentic REPL mode using them (item 4)

## Update (2026-10-05)

Items 1–3 implemented as 25 built-in tools (`work_history/25_TOOLS_builtin_tools.md`, plan
`implementation_plans/1_TOOLS_builtin_tools_catalogue.md`). Remaining: item 4, the `&` mode,
which attaches the built-ins; and a Google mock round.
