# <Feature> — Provider Review

- **Date:** YYYY-MM-DD
- **Providers:** OpenAI | OpenAICompatible | Anthropic | Google
- **Sub-features:** ...
- **Doc snapshot:** artifacts/provider_docs (date)

## Summary

2 to 4 sentences: what the feature is, how uniform it is across providers, and the biggest divergence.

## Per Provider

### <Provider>

- **Endpoint:** `METHOD path` · headers: ... · cite
- **Request fields:**

  | Field (wire name) | Type | Required | Notes | Source |
  |---|---|---|---|---|

- **Response location:** where the feature appears and how to detect it · cite
- **Multi-turn:** how results go back; what must be echoed verbatim · cite
- **Streaming:** event sequence, accumulation, terminal event · cite
- **Termination:** stop/finish reasons · cite
- **Limits / gotchas:** ... · cite
- **Fixture:** minimal request/response JSON (from docs) · cite

(Repeat per provider.)

## Concept Mapping

| Concept | OpenAI | Anthropic | Google | OpenAICompatible | Proposed JAIL concept |
|---|---|---|---|---|---|

Extensions (provider-unique, not in the common abstraction):

- ...

## Conflicts (spec vs docs, or docs vs docs)

- ...

## Recommendation

- Canonical approach per provider.
- Ontology types / interface functions touched.

## Open Questions

- Questions for the user (public API), each with the cheapest check that would settle it.
