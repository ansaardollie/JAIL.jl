# Decision: memory tools load when an agent is applied

| Field | Value |
|-------|-------|
| Artifact | `50_TOOLS_memory_tools_loaded_for_agent_sessions.md` |
| Category | design_decisions |
| Subject | `TOOLS` |
| Date | 2026-10-08 |
| Area/Purpose scope | built-in tools (`memory` group); harness agent mode (`use_agent!`) |
| Related | `49_TOOLS_memory_session_and_agent_scopes.md`, `46_HARNESS_agent_mode_agents_and_skills.md` |
| Status | accepted |
| Decided by | user (ask-questions round, "Scope": session `loaded_tools` on `use_agent!`) |

## Context

The six memory tools (decision 49) are registered in the `memory` group but are not loaded by
default. In agent turns the model would only find them through tool search. The user wants all
memory tools available in agentic sessions, so the model sees them in full.

## Decision

- Applying a named agent with `use_agent!(s, name)` appends every registered tool in the `memory`
  group to `s.loaded_tools`, skipping names already loaded. The list is saved with the session.
- Applying the built-in `julia` agent (no agent file) does not load them, since it stands for "no
  agent".
- `use_agent!(s, nothing)` leaves them loaded. Use `unload_tools!(s, "memory")` to remove them.
- The code uses the registered `_TOOLS` entries, not the strict `load_tools!`. A session whose
  `registered_tools` excludes the memory group loads nothing and does not raise an error.

## Rejected

- Loading them only inside agent turns (`_AgentTurn`): the list would not be saved with the
  session and would have to be recomputed on every turn.
- A Preference that loads the memory tools by default (`loaded_tools` default): this would also
  change plain chat sessions, which have no agent.

## Revisit Trigger

Sessions that run `agent!` without applying an agent (the built-in `julia` agent) need the memory
tools. Or the `registered_tools` rules change so memory tools can be excluded in some other way.
