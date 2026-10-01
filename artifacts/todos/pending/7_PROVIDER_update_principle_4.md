# TODO: Update design principle 4 for the GoogleEnterprise generateContent default

| Field | Value |
|-------|-------|
| Artifact | `7_PROVIDER_update_principle_4.md` |
| Category | todos |
| Subject | `PROVIDER` |
| Date created | 2026-10-01 |
| Area/Purpose scope | agent customization, design principles |
| Related | `design_decisions/21_PROVIDER_google_enterprise_generate_content.md` |
| Priority | low |
| Owner | owner |

## What

Principle 4 in `.github/agents/jail-developer.agent.md` says "Google Interactions (not
generateContent)" and names `OpenAICompatible` as the single exception. Decision 21 made
`GoogleEnterprise` default to generateContent, a second exception. The docs already describe it
that way (`docs/src/guide/concepts.md`). Without the update, a future developer session may read
the principle as forbidding the current default.

## Acceptance Criteria

- [ ] Principle 4 names `GoogleEnterprise` (`api = :generate_content` default, Interactions opt-in) as an exception, with the reason
