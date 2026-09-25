> **Superseded by:** `3_API_naming_and_env_config.md`

# OpenAI-Compatible Provider Configuration

| Field | Value |
|-------|-------|
| Artifact | `1_OAI_PROVIDER_key_at_url_config.md` |
| Category | design_decision |
| Subject | `OAI_PROVIDER` — local OpenAI-compatible provider configuration |
| Date | 2026-09-25 |
| Decided by | user and agent |
| Status | accepted |
| Related | `artifacts/work_history/5_OAI_PROVIDER_local_support.md` |

## Decision

Configure the OpenAI-compatible provider through the existing three-part `JAIL_config` format, placing the optional key and URL together in the third field as `key@url`:

```julia
ENV["JAIL_config"] = "openai-compatible|model|key@url"
```

The `@url` form represents an unauthenticated local server. A URL-only third field remains supported for compatibility and reads its fallback key from `ENV["JAIL_key"]`.

## Context

JAIL already parses `provider|model|apiOrURL`, while OpenAI-compatible APIs need both a base URL and an optional bearer key. Keeping both values in the third field makes a complete local-provider configuration portable as one environment variable and avoids coupling it to the development-only `AI_DEV_KEY` name.

## Alternatives Rejected

- **Keep the key in `AI_DEV_KEY` only:** rejected because the configuration is split across unrelated environment variables and the name is specific to one development gateway.
- **Add separate URL and key environment variables:** rejected because it expands the public configuration surface without improving the existing `setapi` format.
- **Add a new dependency or provider configuration object:** rejected because HTTP.jl and JSON3.jl already provide the required transport and serialization, and the existing `modelProvider` dispatch is sufficient.

## Consequences

- `setapi` splits only the OpenAI-compatible third field at the first `@`, preserving URLs that contain later `@` characters.
- Bearer authentication is omitted for an empty key.
- Existing Gemini, Ollama, and URL-only OpenAI-compatible configurations remain valid.
- Documentation must show `key@url` and identify `JAIL_key` as the fallback.

## Revisit Trigger

Reopen this decision if a supported provider requires credentials containing an unescaped `@`, if multiple authentication schemes are needed, or if configuration grows beyond the existing three-part `JAIL_config` contract.
