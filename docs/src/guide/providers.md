# Providers and configuration

## Built-in providers

| Provider | `provider_name` | Default base URL | Default key ENV var |
|---|---|---|---|
| [`OpenAI`](@ref) | `openai` | `https://api.openai.com/v1` | `OPENAI_API_KEY` |
| [`Anthropic`](@ref) | `anthropic` | `https://api.anthropic.com` | `ANTHROPIC_API_KEY` |
| [`Google`](@ref) | `google` | `https://generativelanguage.googleapis.com` | `GEMINI_API_KEY` |
| [`GoogleEnterprise`](@ref) | `google_enterprise` | none: `https://aiplatform.googleapis.com` for location `"global"`, else `https://<location>-aiplatform.googleapis.com` | none: Google Cloud credentials (see [below](@ref "Gemini on Google Cloud (Vertex AI)")) |

Constructing a provider needs no setup, except `GoogleEnterprise`, which needs a project and
a location. Unset settings come from Preferences, then from these defaults:

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
- `api` is `:responses` (default) or `:chat_completions` for servers that lack the Responses API.
- Registering a name again replaces the saved endpoint.
- Names may contain letters, digits, `.`, `_` and `-`, and can't be a built-in provider name.

Load a registered endpoint by name:

```@example providers
OpenAICompatible("openrouter")
```

[`providers`](@ref) lists `OpenAI`, `Anthropic` and `Google`, then `GoogleEnterprise` once its
project and location are saved, then every registered endpoint:

```@example providers
providers()
```

## Gemini on Google Cloud (Vertex AI)

[`GoogleEnterprise`](@ref) reaches Gemini through a Google Cloud project (the Gemini Enterprise
Agent Platform, also called Vertex AI) instead of the Gemini Developer API that
[`Google`](@ref) uses. It is a separate provider, `google_enterprise` in model strings, because
it connects, authenticates and (by default) sends requests differently.

It has no default project or location, so it can't be built until both are known:

```@example providers
try
    GoogleEnterprise()
catch e
    showerror(stdout, e)
end
```

Pass them for one value, or save them:

```@example providers
configure_provider!(GoogleEnterprise(project = "my-project", location = "us-central1"))
```

```@example providers
GoogleEnterprise()
```

`location` is a Google Cloud region such as `"us-central1"`, or `"global"`.

There is no API key. JAIL gets a Google Cloud access token from the first of these that
exists:

1. the service-account key file at `service_account_path`
2. the key file named by `ENV["GOOGLE_APPLICATION_CREDENTIALS"]`
3. Application Default Credentials, as set up by `gcloud auth application-default login`
4. the metadata server, when running on Google Cloud (GCE/GKE)

Preferences store the *path* to a key file, never its contents. The token is fetched on first
use and fetched again shortly before it expires; it is never saved.

```julia
configure_provider!(GoogleEnterprise(); service_account_path = "/path/to/key.json")
configure_provider!(GoogleEnterprise(); service_account_path = nothing)   # back to the lookup order
```

### Choosing the API

`api` picks how requests are sent:

| `api` | Endpoint | History |
|---|---|---|
| `:interactions` (default) | The Interactions API, as used by `Google` | Continues from the stored reply (see [What gets sent](chat.md#What-gets-sent)) |
| `:generate_content` | Vertex AI `generateContent` | The full history is sent every turn |

On Vertex AI the Interactions API serves Gemini 3 models only: Gemini 2.5 models are rejected
(HTTP 400, "Unsupported model interaction"), and it is not available in every location
(`"global"` works). Use `:generate_content` for those.

```@example providers
configure_provider!(GoogleEnterprise(); api = :generate_content)
```

```@example providers
configure_provider!(GoogleEnterprise(); api = nothing)   # back to :interactions
```

Only Google's own Gemini models are supported. Vertex AI also offers partner models (from
Anthropic, Mistral, xAI and others), but those use other endpoints and JAIL does not support
them.

Save `project` and `location` before saving a default model for `google_enterprise` with
[`set_default_model!`](@ref)`(p, id)`: a saved default with no project makes
[`providers`](@ref) throw.

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
| `providers.google_enterprise.project` | string | [`configure_provider!`](@ref) | Google Cloud project for [`GoogleEnterprise`](@ref) |
| `providers.google_enterprise.location` | string | same | Region such as `"us-central1"`, or `"global"` |
| `providers.google_enterprise.service_account_path` | string | same | Path to a service-account key file (optional) |
| `providers.google_enterprise.api` | `"generate_content"` | same | Only written when not `:interactions` |
| `providers.openai.tool_search`, `providers.anthropic.tool_search` | `"hosted"` / `"client"` | by hand | How the model finds tools that are registered but not loaded: the provider's own tool search (default `"hosted"`; needs `gpt-5.4` or later, or Claude 4.5 or later) or JAIL's `tool_search`/`tool_load` tools. Other providers always use JAIL's |
| `providers.anthropic.prompt_cache` | `"off"` / `"5m"` / `"1h"` | by hand | Automatic prompt caching of each Anthropic request (`cache_control` on the whole request): none (default), a 5-minute cache, or a 1-hour one (cache writes cost 2× input); see [Chat](chat.md#What-gets-sent) |
| `repl_modes` | `false` | by hand | Disables JAIL's REPL modes; read when JAIL loads |
| `max_tokens` | positive integer | by hand | Default reply cap for [`chat!`](@ref) and [`agent!`](@ref) on every provider (unset: Anthropic the model's max output, others none) |
| `thinking_effort` | string such as `"low"`, `"high"` | by hand | Reasoning effort for [`chat!`](@ref), [`agent!`](@ref) and the `}`/`&` modes when neither the call nor the session sets one, sent as-is (unset: not sent) |
| `temperature` | non-negative number | by hand | Sampling temperature, likewise (unset: not sent) |
| `show_reasoning` | `true` / `false` | by hand | Ask for reasoning summaries, show them while streaming, save them under `storage_dir/reasoning` (default `false`) |
| `store_requests` | `true` / `false` | by hand | OpenAI, Google, and `GoogleEnterprise` (unless `api = :generate_content`) store replies and continue from them (default `true`); `false` sends `store = false` and the full history |
| `system_prompt` | string | by hand | Replaces the built-in instructions for sessions created without `system`; `""` gives them none |
| `stream` | `true` / `false` | by hand | Stream replies in the `}` chat and `&` agent modes (default `false`) |
| `max_tool_rounds` | non-negative integer | by hand | Tool rounds per [`agent!`](@ref) call before further calls are answered "not run" (default 50) |
| `parallel_tool_calls` | `true` / `false` | by hand | Let the model call several tools per reply and run them at the same time (default `true`); `false` asks OpenAI, OpenAI-compatible servers and Anthropic for one call per reply and runs calls one by one; see [Tools](tools.md#Parallel-tool-calls) |
| `providers.<name>.parallel_tool_calls` | `true` / `false` | by hand | Overrides `parallel_tool_calls` for that provider |
| `tool_approval` | `"all"` / `"auto"` / `"none"` / `"yolo"` | by hand | Which tool security levels are confirmed with `[y/N]` before running (default `"auto"`: medium and high) |
| `tool_auto_approvals` | table of tool name (or group) → `true` / `false` | [`set_tool_auto_approval!`](@ref), `a` at a prompt, `tools approve` | `true`: never ask for that tool; `false`: always ask (default empty) |
| `registered_tools` | list of built-in group or tool names | by hand | Built-in tools registered when JAIL loads (default: every built-in; `[]` for none). The older `builtin_tools` is no longer read |
| `loaded_tools` | list of tool or group names | by hand | Tools a new session loads, so the model sees them in full; the others are found through tool search (default empty; see [`load_tools!`](@ref)) |
| `julia_code_module` | `"main"` / `"sandbox"` | by hand | Where the built-in `execute_julia_code` runs: `Main`, or a module per session (default `"main"`) |
| `protected_paths` | list of paths | by hand | Paths, relative to the workspace folder, whose writes by built-in tools are always `:high`, besides `LocalPreferences.toml`, `Project.toml`, `.git` and `storage_dir` (default empty) |
| `scrub_env_vars` | list of ENV var names | by hand | Removed from the built-in tools' child processes, besides names ending in `_KEY`, `_CREDENTIALS`, `_CREDENTIAL` (default empty) |
| `path_allow_list` | list of paths | by hand | Files and folders, relative to the workspace folder or absolute, whose writes by the built-in `edit` tools are `:low` unless protected (default empty) |
| `command_allow_list` | list of command prefixes | by hand | `run_shell` commands starting with one of them (and free of `;`, `&`, `\|`, `` ` ``, `$`, `<`, `>`, line breaks) are `:low` (default empty) |
| `url_allow_list` | list of URL prefixes | by hand | `http_request` calls to URLs starting with one of them (at a `/`, `?`, `#` or the end) are `:low` instead of `:high` (default empty) |
| `persist_sessions` | `true` / `false` | by hand | Save sessions to disk from their first message on (default `true`) |
| `storage_dir` | path | by hand | Folder for saved sessions, session memories, and the agents and skills made with `new_agent`/`new_skill` (`agents/`, `skills/`; default `".jail"`, relative to the working directory) |

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

[JAIL.providers.google_enterprise]
project = "my-project"
location = "global"
```

Preferences belong to the active project, so switching projects switches configuration.
