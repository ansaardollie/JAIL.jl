# TODO: Live-check thinking effort, temperature and show_reasoning per provider

| Field | Value |
|-------|-------|
| Artifact | `9_MESSAGES_live_check_effort_reasoning.md` |
| Category | todos |
| Subject | `MESSAGES` |
| Date created | 2026-10-06 |
| Area/Purpose scope | providers, streaming display |
| Related | `work_history/34_MESSAGES_thinking_effort_temperature_reasoning.md`, `design_decisions/39_MESSAGES_thinking_effort_and_temperature.md`, `design_decisions/40_STREAMING_show_reasoning.md` |
| Priority | normal |
| Owner | any |

## What

Only mock servers verified the new options. With the owner's permission, run one streamed
`chat!(s, "What is the GCD of 1071 and 462?"; stream = true, show_reasoning = true, thinking_effort = :low)`
per provider: OpenAI (a reasoning model), Anthropic (Opus 4.6+ / Sonnet 5), Google, GoogleEnterprise
(both `api` settings), and a compatible Chat Completions server if available. Also a
non-streamed `chat!` with `show_reasoning = true` on each.

## Why

Wire mappings for `output_config.effort`, `reasoning.summary`, `thinking_summaries`,
`includeThoughts`, and the Google `temperature` (DOCS-ONLY) are untested live; the dim stream and
yellow box are unseen in a real terminal.

## Acceptance Criteria

- [ ] Each provider returns a reply with non-empty `ReasoningPart.text` (or the 400 is recorded)
- [ ] Trace `.md` files written and linked from the `Reasoning` box
- [ ] Results recorded in a work_history artifact; doc fixes for any mismatch

## Notes

Live calls need owner approval each time. The owner's Preferences set `show_reasoning = true`
and `temperature = 0.0`; Sonnet 5 rejects that temperature (HTTP 400 "deprecated for this model").
