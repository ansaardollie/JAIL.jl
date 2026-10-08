# Decision: session and agent memory tools

| Field | Value |
|-------|-------|
| Artifact | `49_TOOLS_memory_session_and_agent_scopes.md` |
| Category | design_decisions |
| Subject | `TOOLS` |
| Date | 2026-10-08 |
| Area/Purpose scope | built-in tools (`memory` group); session persistence |
| Related | `41_TOOLS_http_request_memory_tool_restore.md`, `46_HARNESS_agent_mode_agents_and_skills.md` |
| Status | accepted |
| Decided by | user (two scopes, file location, tool descriptions); user answers to ask-questions round (names, `julia` agent, deletion) |

## Context

The `memory` group has one scope: a session's numbered list at
`<storage_dir>/memory/sessions/<id>.md`. The user wants a second scope for notes that outlive a
session: directives about an agent that are, explicitly or implicitly, useful for all future
sessions with that agent, stored at `<storage_dir>/memory/agents/<agent name>.memory.md`.
Session memory is for directives of the session's specific task.

## Decision

- Six tools in the `memory` group, all `:low`:
  - `read_session_memory()`, `add_session_memory(input)`, `remove_session_memory(number)`
  - `read_agent_memory()`, `add_agent_memory(input)`, `remove_agent_memory(number)`
- Both scopes keep the existing rules: Markdown numbered list, numbers stable (removal leaves a
  gap, next = max+1), line breaks in `input` become spaces.
- Agent = the session's agent name (`use_agent!`), or the built-in `julia` agent when none is
  applied, so the file is `memory/agents/julia.memory.md`.
- Agent names that can't be a file name (empty, `.`, `..`, containing `/`, `\`, or NUL) are
  rejected with an `ArgumentError`.
- `delete_session!(s; files = true)` deletes the session memory file only. Agent memory belongs
  to the agent and stays.
- Tool descriptions say which scope fits: session memory for directives of this session's task;
  agent memory for directives useful for all future sessions with this agent.

## Rejected

- Keeping `read_memory`, `add_memory`, `remove_memory` for the session scope and adding only
  `*_agent_memory`: the pair would be asymmetric and the names would not say which scope they use.
- Refusing agent memory when no agent is applied: the built-in `julia` agent already stands for
  "no agent" in agent turns, so it gets its own file.
- Deleting agent memory with the session: the file is shared by every session with the agent, and
  nothing records which sessions use it.

## Revisit Trigger

Agent memory needs to reach the system prompt automatically, a per-session opt-out is wanted, or
agent names need to be unique across folders (two agent files with one name share one memory file).
</content>
