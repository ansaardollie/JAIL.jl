# Decision: The planning agent creates plan documents without stage todos

| Field | Value |
|-------|-------|
| Artifact | `22_AGENT_plan_only_output.md` |
| Category | design_decisions |
| Subject | `AGENT` |
| Date | 2026-10-04 |
| Area/Purpose scope | workspace agent workflow |
| Related | `.github/agents/jail-planner.agent.md` |
| Status | accepted |
| Decided by | user |

## Context

The JAIL planning workflow normally pairs each implementation plan with one pending todo per
stage. The owner requested a planning-only agent and clarified that its permitted planning output
is the implementation plan itself, not the separate todo records.

## The Question

"Should this agent create the per-stage todo files required by the current planning workflow
alongside each implementation plan?"

## Options Considered

### Option A — Plan plus todos

- How it works: Write one plan and a linked pending todo for each stage.
- Pros: Follows the existing implementation-planning workflow and makes stage work independently trackable.
- Cons: Creates artifacts beyond the implementation plan requested by the owner.

### Option B — Plan only

- How it works: Write a single implementation-plan artifact containing all stages and verification details; create no todo artifacts.
- Pros: Keeps the agent's output within the owner's requested planning boundary.
- Cons: Stages are not independently listed in the pending-todo queue.

## Decision

The user chose **Plan only**. The agent writes implementation plans without per-stage todo
artifacts. This owner-specific rule overrides the todo-emission step in the general planning
workflow for this agent.

## Consequences

Plan stages, deliverables, file lists, and verification commands must be self-contained in the
plan. Todo artifacts remain untouched.

## Revisit Trigger

The owner asks the planning agent to emit pending todos or changes its permitted artifact scope.