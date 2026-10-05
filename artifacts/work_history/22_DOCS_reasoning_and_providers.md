# Docs for ReasoningPart and the GoogleEnterprise default; GoogleEnterprise in the built-in providers table

| Field | Value |
|-------|-------|
| Artifact | `22_DOCS_reasoning_and_providers.md` |
| Category | work_history |
| Subject | `DOCS` |
| Date | 2026-10-05 |
| Area/Purpose scope | docs, docstrings |
| Related | `work_history/21_MESSAGES_reasoning_replay.md`, `design_decisions/25_MESSAGES_reasoning_part.md`, `design_decisions/26_PROVIDER_google_enterprise_interactions_default.md` |

## Scope of This Unit of Work

Follows `21_MESSAGES_reasoning_replay.md` (commit `6c3a0af`). The owner asked for a documentation
pass on those changes, consistent with the design principles in
`.github/agents/jail-developer.agent.md`, and noted that the Built-in providers table did not list
`GoogleEnterprise`.

## What Changed

| File | Change |
|-------|--------|
| `docs/src/guide/providers.md` | `GoogleEnterprise` row in Built-in providers (`google_enterprise`; host from location; Google Cloud credentials, no key ENV var; links to the Vertex AI section). "Needs no setup" now excepts `GoogleEnterprise`. `providers()` sentence corrected |
| `docs/src/guide/chat.md` | New "Reasoning" section with a runnable `@example` (`ReasoningPart`, `string(reply)` excludes it), the same-provider-and-wire rule, hand-written replies never replay, chained turns don't resend, summaries not requested yet. `store_requests` sentence names `GoogleEnterprise` (Interactions) |
| `docs/src/guide/concepts.md` | One sentence: replies keep reasoning as `ReasoningPart`s |
| `docs/src/guide/sessions.md` | Session files store `ReasoningPart`s with their provider data |
| `docs/src/guide/models.md` | Model-string lookup finds `google_enterprise` only once project/location are saved |
| `src/ontology/messages.jl` | `ReasoningPart` docstring: signature shows `data = Dict()`, lists the four formats, says not to read/edit `data`, adds a `jldoctest`. `AssistantMessage` docstring mentions `ReasoningPart`s |
| `src/chat.jl` | `chat!` docstring: a full history includes reasoning, only for its provider and wire |
| `src/configuration.jl` | `providers()` docstring: includes `GoogleEnterprise` once configured |

No behavior changed.

## Design Decisions Made

None. Two principle tensions were reported to the owner instead of decided (see Todos).

## Verification

Baseline before edits:

```
$ zsh -ic 'jd docs/make.jl' > /tmp/docbuild.log 2>&1; echo exit=$?; grep -cE "Warning|Error|missing docs|no docs found|not found|failed" /tmp/docbuild.log
exit=0
0
```

After edits: `exit=0`, no warning lines; `[ Info: Doctest: running doctests.` with no failures;
`docs/build/guide/providers/index.html` has the `google_enterprise` row and
`href="#Gemini-on-Google-Cloud-(Vertex-AI)">below`; `ReasoningPart` appears in the built chat and
reference pages; `grep -rlE "dhd-prima|gpt-6-luna" docs/build` finds nothing.

REPL check of the documented examples:

```
ReasoningPart(:anthropic, "Check the units first.")
"22°C"
2-element Vector{AbstractContentPart}:
 ReasoningPart(:anthropic, "Check the units first.")
 TextPart("22°C")
4-element Vector{AbstractProvider}:
 OpenAI("https://api.openai.com/v1", "OPENAI_API_KEY")
 Anthropic("https://api.anthropic.com", "ANTHROPIC_API_KEY")
 Google("https://generativelanguage.googleapis.com", "GEMINI_API_KEY")
 GoogleEnterprise(project = "dhd-prima", location = "global")
```

Drift found and fixed in the docs: the three-provider table; `providers()` docstring and guide
(omitted `GoogleEnterprise`); model-string lookup (`google_enterprise` unknown until configured);
"constructing a provider needs no setup"; `ReasoningPart` signature missing the `data` default.

## Known Limitations

- `ReasoningPart.data` is provider JSON on a public type, against principle 6; the docs only call
  it opaque. `examples/reasoning.jl` still builds one by hand.
- Principle 4 in the agent file still doesn't mention the `GoogleEnterprise` exception.

## Todos

- Completed: none
- Created: `8_MESSAGES_reasoning_data_principle_6.md`
- Updated: `7_PROVIDER_update_principle_4.md` (note: Interactions is the default again)

## Next Steps

1. Owner: answer `8_MESSAGES_reasoning_data_principle_6.md` (keep `data` public or hide it).
2. Owner: update principle 4 per `7_PROVIDER_update_principle_4.md`.
3. Owner: save `api = "generate_content"` for `google_enterprise` if using Gemini 2.5 models
   (carried over from work history 21).
