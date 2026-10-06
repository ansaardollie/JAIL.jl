# Decision: Anthropic automatic prompt caching and its Preference

| Field | Value |
|-------|-------|
| Artifact | `43_MESSAGES_anthropic_prompt_cache.md` |
| Category | design_decisions |
| Subject | `MESSAGES` |
| Date | 2026-10-06 |
| Area/Purpose scope | Anthropic provider, Preferences, `Usage` |
| Related | `38_MESSAGES_anthropic_per_model_max_tokens.md`, `3_PREFERENCES_nested_layout.md` |
| Status | accepted |
| Decided by | user (caching on the whole request; Preferences to turn it off or use 1 h); agent (key name, values, `Usage` total) |

## Context

User: "add the `"cache_control": {"type": "ephemeral"}` option to the anthropic session to the
overall request (i.e. not on each message but the whole chain)", then "add preferences for
anthropic to turn off caching or use the longer 1hr version".

## Decision

- Anthropic Messages requests can carry top-level `cache_control` (automatic caching,
  `claude-docs-50-prompt-caching.md#L279-L299`); `count_tokens` doesn't send it.
- Preference `providers.anthropic.prompt_cache`: `"off"` (default, field omitted; owner: "the
  default should be off"), `"5m"` (`{"type": "ephemeral"}`) or `"1h"` (adds `"ttl": "1h"`,
  #L487-L493). Anything else throws an `ArgumentError` on the next request.
- `Usage.input_tokens` for Anthropic = `input_tokens + cache_read_input_tokens +
  cache_creation_input_tokens` (#L689-L694), so it stays a total as on other providers.

## Rejected

- A Bool plus a separate TTL key (two keys for one setting).
- Per-block breakpoints (user asked for the whole chain).
- Leaving `input_tokens` uncached-only (turn totals would collapse to the uncached tail).

## Revisit Trigger

Owner wants cache read/write counts exposed separately, per-session cache settings, or caching on
other providers.
