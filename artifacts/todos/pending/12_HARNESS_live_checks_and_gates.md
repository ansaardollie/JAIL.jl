# TODO: Agent mode — live provider checks and open gates G1–G3

| Field | Value |
|-------|-------|
| Artifact | `12_HARNESS_live_checks_and_gates.md` |
| Category | todos |
| Subject | `HARNESS` |
| Date created | 2026-10-06 |
| Area/Purpose scope | providers, public API |
| Related | `implementation_plans/2_HARNESS_agent_mode_agents_and_skills.md`, `design_decisions/46_HARNESS_agent_mode_agents_and_skills.md`, `work_history/41_HARNESS_agent_mode_agents_and_skills.md` |
| Priority | high |
| Owner | any |

## What

1. Live, per provider (OpenAI, Anthropic, Google, GoogleEnterprise both `api`s, one
   OpenAI-compatible server): `agent!(s, …)` with one tool call, then `chat!(s, …)` on the same
   session. The chat request carries the history's tools with `tool_choice` "none" (Anthropic
   `{"type":"none"}` is docs-only; the local spec lacks it).
2. Owner decisions: G1 (what `count_tokens` counts with two modes), G2 (plain `*.md` Claude
   subagents in `.claude/agents`), G3 (accept `disallowed-tools`/`disallowedTools` spellings on both).
3. Real-terminal check of `&`: prompt shows the agent, Tab completes `/skills`, duplicate menus
   render, streaming with tool lines.

## Acceptance Criteria

- [ ] Each provider accepts the chat-after-agent request (paste request/response or REPL output)
- [ ] G1–G3 answered and recorded (decision 46 amendment or a new decision)
- [ ] `&` checked on a real terminal
