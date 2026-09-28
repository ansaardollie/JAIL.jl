# Providers and configuration

## Built-in providers

| Provider | `provider_name` | Default base URL | Default key ENV var |
|---|---|---|---|
| [`OpenAI`](@ref) | `openai` | `https://api.openai.com/v1` | `OPENAI_API_KEY` |
| [`Anthropic`](@ref) | `anthropic` | `https://api.anthropic.com` | `ANTHROPIC_API_KEY` |
| [`Google`](@ref) | `google` | `https://generativelanguage.googleapis.com` | `GEMINI_API_KEY` |

Constructing a provider needs no setup. Unset settings come from Preferences, then from these
defaults:

```@example providers
using JAIL

OpenAI()
```

Keyword arguments override a setting for that value only; nothing is saved:

```@example providers
Anthropic(base_url = "https://my-proxy.example.com")
```

A trailing `/` is removed, and the URL must start with `http://` or `https://`.

## Saving provider settings

[`configure_provider!`](@ref) saves settings in Preferences and returns the reloaded
provider. Afterwards every `Anthropic()` picks them up:

```@example providers
configure_provider!(Anthropic(); api_key_env = "MY_ANTHROPIC_KEY")
```

```@example providers
Anthropic()
```

Passing `nothing` removes the saved value, so the default applies again:

```@example providers
configure_provider!(Anthropic(); api_key_env = nothing)
```

Only settings that differ from the defaults are written, so future changes to JAIL's defaults
still reach you.

## OpenAI-compatible servers

An [`OpenAICompatible`](@ref) endpoint has a `name`, which is how you refer to it in model
strings (`"lmstudio/qwen3:8b"`). Save it with [`register_provider!`](@ref):

```@example providers
register_provider!(OpenAICompatible("lmstudio", "http://localhost:1234/v1"; api = :chat_completions))
```

```@example providers
register_provider!(OpenAICompatible("openrouter", "https://openrouter.ai/api/v1";
                                    api_key_env = "OPENROUTER_API_KEY"))
```

- `api_key_env = nothing` (the default) means the server needs no key.
- `api` is `:responses` (default) or `:chat_completions`. It is saved now but only matters
  once requests are implemented.
- Registering a name again replaces the saved endpoint.
- Names may contain letters, digits, `.`, `_` and `-`, and can't be a built-in provider name.

Load a registered endpoint by name:

```@example providers
OpenAICompatible("openrouter")
```

[`providers`](@ref) lists the built-in providers followed by every registered endpoint:

```@example providers
providers()
```

## Common errors

```@example providers
try
    OpenAICompatible("anthropic", "http://localhost:8000/v1")
catch e
    showerror(stdout, e)
end
```

```@example providers
try
    configure_provider!(OpenAI(); api_key_env = "sk-proj-abc123")   # a key, not a var name
catch e
    showerror(stdout, e)
end
```

A missing API key is reported when the provider is first used, before anything is sent:

```@example providers
try
    list_models(Google(api_key_env = "JAIL_DOCS_UNSET_VAR"))
catch e
    showerror(stdout, e)
end
```

## Preferences keys

All keys live under `[JAIL]` in the active project's `LocalPreferences.toml`. Use the functions
above rather than editing by hand, though hand edits are picked up without a restart.

| Key | Type | Written by | Meaning |
|---|---|---|---|
| `default_model` | `"provider/model-id"` | [`set_default_model!`](@ref) | Model for new sessions and for the `"default"` session at load |
| `providers.<name>.default_model` | model id | [`set_default_model!`](@ref)`(p, id)` | That provider's own default, used by [`use_provider!`](@ref) and the REPL's `use provider` (no model id) |
| `providers.<name>.base_url` | string | [`configure_provider!`](@ref), [`register_provider!`](@ref) | Base URL override (built-in) or endpoint URL (compatible) |
| `providers.<name>.api_key_env` | string | same | Name of the ENV var holding the API key |
| `providers.<name>.type` | `"openai_compatible"` | [`register_provider!`](@ref) | Marks a registered compatible endpoint |
| `providers.<name>.api` | `"chat_completions"` | same | Only written when not `:responses` |
| `repl_modes` | `false` | by hand | Disables JAIL's REPL modes; read when JAIL loads |
| `max_tokens` | positive integer | by hand | Default reply cap for [`chat!`](@ref) on every provider (unset: Anthropic 8192, others none) |
| `store_requests` | `true` / `false` | by hand | OpenAI and Google store replies and continue from them (default `true`); `false` sends `store = false` and the full history |
| `system_prompt` | string | by hand | Replaces the built-in instructions for sessions created without `system`; `""` gives them none |
| `stream` | `true` / `false` | by hand | Stream replies in the `}` chat mode (default `false`) |
| `max_tool_rounds` | non-negative integer | by hand | Tool rounds per [`chat!`](@ref) call before further calls are answered "not run" (default 10) |
| `confirm_tools` | `true` / `false` | by hand | Ask `[y/N]` on the terminal before each tool call (default `false`) |

For example:

```toml
[JAIL]
default_model = "anthropic/claude-sonnet-4-5"

[JAIL.providers.anthropic]
api_key_env = "MY_ANTHROPIC_KEY"

[JAIL.providers.lmstudio]
type = "openai_compatible"
base_url = "http://localhost:1234/v1"
api = "chat_completions"
```

Preferences belong to the active project, so switching projects switches configuration.
