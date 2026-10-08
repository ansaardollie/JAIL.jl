# TODO: Memory tools — follow-ups from the scopes and agent-loading unit

| Field | Value |
|-------|-------|
| Artifact | `13_TOOLS_memory_follow_ups.md` |
| Category | todos |
| Subject | `TOOLS` |
| Date created | 2026-10-08 |
| Area/Purpose scope | built-in tools (`memory` group), docs, harness agent mode |
| Related | `work_history/45_TOOLS_memory_scopes_and_agent_loading.md`, `design_decisions/49_TOOLS_memory_session_and_agent_scopes.md`, `design_decisions/50_TOOLS_memory_tools_loaded_for_agent_sessions.md` |
| Priority | normal |
| Owner | any |

## What

1. Owner decision: should the six memory tools take an explicit session argument? They currently
   act on the session of the tool call, or the active session when called directly. This conflicts
   with the explicit-instance principle in `.github/agents/jail-developer.agent.md`. If the answer
   is yes, record a new design decision that supersedes 49 (do not edit 49's decision).
2. Regenerate the `## Example` transcript in `docs/src/guide/repl.md` against a live
   OpenAI-compatible server. Its `st` fields (`system`, `thinking`, `reasoning`, `loaded`) are
   stale; the lead-in now says the transcript is illustrative.
3. Owner decision: should sessions that call `agent!` without applying a file agent (the built-in
   `julia` agent) get the memory tools? Decision 50 currently says no.

## Why

These are the open items from the memory unit. None blocks the committed behaviour, but each
changes docs or the public surface if decided otherwise.

## Acceptance Criteria

- [ ] Item 1 decided and recorded (new decision artifact or a recorded "no change")
- [ ] `docs/src/guide/repl.md` `st` output matches a live capture, or the transcript is removed
- [ ] Item 3 decided; if yes, `use_agent!` and decision 50 are updated together
- [ ] `jd docs/make.jl` reports no warnings after each change

## Notes

- Memory tools: `src/builtin_tools/memory.jl`. Loading on `use_agent!`: `src/harness/agent.jl`.
- The `repl.md` transcript was not produced by a live session; do not regenerate values by hand.
