# Decision: Record user-confirmed architectural blockers

| Field | Value |
|-------|-------|
| Artifact | `23_AGENT_record_confirmed_blockers.md` |
| Category | design_decisions |
| Subject | `AGENT` |
| Date | 2026-10-04 |
| Area/Purpose scope | workspace agent workflow |
| Related | `.github/agents/jail-planner.agent.md`, `22_AGENT_plan_only_output.md` |
| Status | accepted |
| Decided by | user |

## Context

The planning agent must not guess at user-owned architectural choices. Once the user answers a
blocking question, preserving that answer prevents a future plan from treating the same choice as
unsettled. A separate design-decision record is an additional write beyond the plan document.

## The Question

"When an architectural choice blocks a plan, should the agent ask you and wait, without creating
a separate design-decision record?"

## Options Considered

### Option A — Ask and wait

- How it works: Use the answer to proceed with planning but do not create a decision artifact.
- Pros: Keeps all persistent output in implementation plans.
- Cons: The architectural answer may be lost and revisited in a later session.

### Option B — Write decision records

- How it works: After the user resolves a blocking architecture question, record the answer using the project's design-decision workflow, then plan against it.
- Pros: Preserves user-owned decisions in the established source of truth.
- Cons: Allows a design-decision artifact in addition to the plan.

## Decision

The user chose **Write decision records**. The planning agent asks and waits on blocking public API,
core abstraction, module boundary, data model, or dependency choices; after the user answers, it
records the confirmed decision before writing a plan based on it.

## Consequences

The agent may write in `artifacts/design_decisions/` only to record a decision the user has
confirmed. It does not use that permission to make or record decisions on the user's behalf.

## Revisit Trigger

The owner changes whether confirmed architectural decisions should be recorded as separate
artifacts.