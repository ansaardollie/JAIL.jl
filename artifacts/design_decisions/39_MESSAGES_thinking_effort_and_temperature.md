# Decision: `thinking_effort` and `temperature` as chat! kwargs, session fields and Preferences

| Field | Value |
|-------|-------|
| Artifact | `39_MESSAGES_thinking_effort_and_temperature.md` |
| Category | design_decisions |
| Subject | `MESSAGES` |
| Date | 2026-10-06 |
| Area/Purpose scope | public API (`chat!`, `Session`, setters), Preferences, provider request bodies |
| Related | `12_MESSAGES_types_and_chat.md`, `9_SESSION_session_type.md`, `40_STREAMING_show_reasoning.md` |
| Status | accepted |
| Decided by | user (name, unsupported-level policy, surfaces, Anthropic thinking, setters); agent (wire mapping, validation) |

## Context

Owner asked for "support for configuring the level of effort/reasoning/thinking the model does"
and "support for setting model temperature". Providers name and scope effort differently:
OpenAI `reasoning.effort` (`none`..`max`, api_spec.yaml#L66769), Anthropic `output_config.effort`
(`low`..`max`, claude-docs-10-effort.md#L237), Google `thinking_level` (`minimal`..`high`,
interactions.openapi.json#L8654), Vertex generateContent `thinkingConfig.thinkingLevel` (upper case).

## Decision

User-decided:

- Name: `thinking_effort` (offered: `effort`, `reasoning_effort`, `thinking`). A `Symbol`; the
  Preference is a string.
- Levels a provider lacks are **sent as-is** and the API rejects them (rejected: clamp to
  nearest; throw before sending).
- Surfaces: `chat!` kwargs + Preferences (`thinking_effort`, `temperature`) **and** per-session
  override fields. Precedence: kwarg > session > Preference > not sent.
- Session API: `Session(...; thinking_effort, temperature)`, `new_session!` likewise,
  `set_thinking_effort!(s, x)` / `set_temperature!(s, x)` plus session-less forms; `nothing`
  clears. Saved in the session JSON.
- Anthropic: an effort other than `:none` also sends `thinking: {type: "adaptive"}` (Opus
  4.6–4.8 / Sonnet 4.6 have thinking off by default).

Agent-decided:

- Anthropic `:none` → `thinking: {type: "disabled"}` with no `output_config` (there is no
  `none` effort level; claude-docs-21-thinking.md#L301-L314).
- Chat Completions: `reasoning_effort` (api_spec.yaml#L42365). Google: `generation_config.temperature`
  is DOCS-ONLY (gemini-docs-027-text-generation.md#L343-L355; absent from the spec's GenerationConfig).
- Validation: effort must be a Symbol or non-empty string (any value, no level list);
  temperature a finite non-negative real, no upper bound (OpenAI 0–2, Anthropic 0–1).
- Kwarg/session values are validated in `_chat!` before the turn starts; Preference fallback
  happens in `_complete` (like `max_tokens`).
- Session display shows `thinking:` / `temperature:` lines only when set; labels widened.

## Rejected

- Clamping levels per provider (user: send as-is).
- Session-free design (Preferences only), which left no per-conversation control.

## Consequences

- Extended-thinking-only Anthropic models (Haiku 4.5, Sonnet 4.5, ...) reject adaptive thinking,
  so a global `thinking_effort` Preference breaks them; `budget_tokens` is not supported.
- The newest Anthropic models reject non-default temperature; Google deprecated it.

## Revisit Trigger

- Users hit 400s from a global `thinking_effort` on mixed-model setups (consider per-model
  mapping or `budget_tokens` for extended-thinking models).
- Anthropic per-message effort (beta) or a provider adds levels JAIL should map.
