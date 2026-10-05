# TODO: Decide whether ReasoningPart.data stays public (principle 6)

| Field | Value |
|-------|-------|
| Artifact | `8_MESSAGES_reasoning_data_principle_6.md` |
| Category | todos |
| Subject | `MESSAGES` |
| Date created | 2026-10-05 |
| Area/Purpose scope | public API, core ontology, examples |
| Related | `design_decisions/25_MESSAGES_reasoning_part.md`, `work_history/22_DOCS_reasoning_and_providers.md` |
| Priority | normal |
| Owner | owner |

## What

`ReasoningPart` (exported, `src/ontology/messages.jl`) has a public `data::Dict{String,Any}`
field holding the provider's raw record (Anthropic `thinking` block, OpenAI `reasoning` item,
Google `thought` step, or `{"thoughtSignature": …}`). Principle 6 in
`.github/agents/jail-developer.agent.md` says "User code never sees provider JSON". The docs now
call `data` opaque and say not to read or edit it, but `examples/reasoning.jl` section 1 builds a
`data` dict by hand with Anthropic wire fields.

Ask the owner (ask-questions tool) whether to:

1. keep `data` public and only drop the hand-built `data` from `examples/reasoning.jl`, or
2. rename it to a private-looking field (e.g. `_data`) and/or hide it from the constructor.

## Why

The public type contradicts a stated design principle; deciding now is cheaper than after users
depend on the field.

## Acceptance Criteria

- [ ] Owner's answer recorded (amend decision 25 or a new design_decisions artifact)
- [ ] `examples/reasoning.jl` shows no provider wire fields
- [ ] `jd docs/make.jl` builds with 0 warnings

## Notes

Persistence (`src/persistence.jl`, `_part_json(::ReasoningPart)`) writes `data` to the session
files; a rename must keep reading `"data"` from existing files.
