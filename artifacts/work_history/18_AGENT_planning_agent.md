# JAIL planning agent: plan-only workflow

| Field | Value |
|-------|-------|
| Artifact | `18_AGENT_planning_agent.md` |
| Category | work_history |
| Subject | `AGENT` |
| Date | 2026-10-04 |
| Area/Purpose scope | workspace agent workflow |
| Related | `design_decisions/22_AGENT_plan_only_output.md`, `design_decisions/23_AGENT_record_confirmed_blockers.md`, `.github/agents/jail-planner.agent.md` |

## Scope of This Unit of Work

The owner asked for a workspace custom agent based on JAIL's development instructions, with a
hard constraint that it only reads project context and creates implementation plans. The previous
work-history entry concerned GoogleEnterprise; this work adds a planning-only companion to the
existing JAIL developer and explainer agents.

## What Changed

| File | Change |
|-------|--------|
| `.github/agents/jail-planner.agent.md` | Added a user-invocable JAIL planning agent with read/search/edit tools, no execution tools, explicit write boundaries, source-of-truth guidance, design guardrails, and a plan workflow. |
| `artifacts/design_decisions/22_AGENT_plan_only_output.md` | Recorded the user's choice to create implementation plans without linked pending todos. |
| `artifacts/design_decisions/23_AGENT_record_confirmed_blockers.md` | Recorded the user's choice to write decision artifacts for user-confirmed architectural blockers. |

## Design Decisions Made

- The agent writes implementation-plan artifacts, not stage todos. The alternative was the
  existing paired plan-and-todo workflow; the user chose plan-only output. See decision 22.
- After the user resolves a blocking architecture question, the agent records the confirmed
  choice as a design decision before planning against it. The alternative was to leave the answer
  only in chat; the user chose a durable decision record. See decision 23.

## Verification

Editor diagnostics for the agent file and both decision files returned `No errors found`.
`git diff --check` completed successfully with no output. No Julia code, package load, tests, or
generated plan were run because this change only adds agent and workflow documentation.

## Known Limitations

- Tool access removes terminal, Julia, and execution tools, but the `edit` alias is not a
  path-level sandbox. The agent's allowed write paths are enforced by its instructions, not by a
  separate filesystem permission boundary.
- The agent has not yet been invoked on a sample planning request.

## Todos

- Completed: none.
- Created: none.

## Next Steps

1. Invoke `jail-planner` on a small JAIL feature request and confirm it produces a plan without
   creating todos or touching implementation files.
2. Revisit the agent's write boundary if a path-restricted tool becomes available.