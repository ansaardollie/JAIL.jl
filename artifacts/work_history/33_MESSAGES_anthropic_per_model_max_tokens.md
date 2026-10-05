# Anthropic per-model default `max_tokens`

| Field | Value |
|-------|-------|
| Artifact | `33_MESSAGES_anthropic_per_model_max_tokens.md` |
| Category | work_history |
| Subject | `MESSAGES` |
| Date | 2026-10-06 |
| Area/Purpose scope | Anthropic provider, chat core, docs, examples |
| Related | `design_decisions/38_MESSAGES_anthropic_per_model_max_tokens.md`, `work_history/32_TOKENS_count_tokens.md` |

## Scope of This Unit of Work

Follows `32_TOKENS_count_tokens.md`. Owner wanted to stop the 8192 cap limiting Claude replies.
Tried in order: omit `max_tokens` (owner: fails live), default 0 (reverted by owner untried),
flat 128000, then per-model maximum (kept).

## What Changed

| File | Change |
|-------|--------|
| `src/providers/anthropic.jl` | `default_max_tokens(::Type{Anthropic}) = 128000`; `default_max_tokens(::Model{Anthropic})`: `3-5` → 4096, `haiku-4-5` → 64000, else 128000 |
| `src/ontology/requests.jl` | `default_max_tokens(m::AbstractModel)` falls back to the provider type |
| `src/chat.jl` | `_max_tokens(model, kw)` (was provider); `_complete` passes the model |
| `docs/src/guide/chat.md`, `docs/src/guide/providers.md`, `examples/chat.jl`, `examples/LocalPreferences.toml` | describe the per-model Anthropic default |

## Decisions

- `38_MESSAGES_anthropic_per_model_max_tokens.md`.

## Verification

```julia
[(id, JAIL._max_tokens(JAIL.Model(a, id), nothing)) for id in ("claude-opus-4-6","claude-haiku-4-5","claude-3-5-sonnet-20241022")], JAIL._max_tokens(JAIL.Model(JAIL.OpenAI(), "gpt-5"), nothing)
```
```
([("claude-opus-4-6", 128000), ("claude-haiku-4-5", 64000), ("claude-3-5-sonnet-20241022", 4096)], nothing)
```

Not verified: any live Anthropic call with the new defaults; non-streaming with 128000 (the API
may require streaming for large `max_tokens`).

## Limitations

- Substring matching on model id; 3.7 / Opus 4 / 4.1 / Sonnet 4 get 128000 and will likely 400.
- 3.5 limited to 4096 (no beta header).
- No automated tests.

## Next Steps

- Live check `chat!` on an Opus/Sonnet 4.6+ model, streaming and non-streaming.
- Add caps for older families if used, or derive limits from model metadata.
