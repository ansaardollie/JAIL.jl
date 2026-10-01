# Providers and model selection
#
# What: pick an LLM provider (the API vendor) and a model (the provider's choice of LLM),
# configure provider connections, register OpenAI-compatible servers, and persist a default
# model. All configuration lives in Preferences (the active project's LocalPreferences.toml)
# and applies immediately, without restarting Julia. API keys stay in ENV; JAIL only stores
# the *name* of the ENV var.
#
# Providers: OpenAI, Anthropic, Google, GoogleEnterprise (Vertex AI), and any OpenAI-compatible
# server.
#
# Open / tentative:
# - The session type (per-conversation state, active model) doesn't exist yet;
#   `default_model()` is what it will start from.
# - `Model` holds only provider + id; listing metadata (display name, context window) is dropped.
# - Google `list_models` keeps only models that support `generateContent`; GoogleEnterprise's
#   catalog (Google's own models only) has no such capability field, so it comes back unfiltered
#   (includes embeddings, TTS, etc.).
# - GoogleEnterprise speaks generateContent by default (full history every turn) and the
#   Interactions API only with `api = :interactions`. Vertex AI partner models (Anthropic,
#   Mistral, xAI) are not supported yet.

using JAIL

function show_error(f)
    try
        f()
    catch e
        println("  ", sprint(showerror, e))
    end
end

const LIVE = true   # set to true to call the providers' list-models endpoints

# --- 1. Providers are values; defaults need no setup ---------------------------------------

@show OpenAI()
@show Anthropic()
@show Google()

# An ad-hoc override, not persisted:
@show Anthropic(base_url = "https://my-proxy.example.com")

# GoogleEnterprise (Vertex AI on GCP) is a distinct provider, not a flag on Google: different
# base URL, different auth (an OAuth2 access token, never an API key), and by default a different
# wire format (generateContent). Unlike the other providers it has no built-in default
# project/location.
@show GoogleEnterprise(project = "example-project", location = "us-central1")
@show GoogleEnterprise(project = "example-project", location = "us-central1", api = :interactions)

# The access token is fetched lazily on first use and cached on the instance (refreshed a little
# before its ~1h lifetime is up): `service_account_path`, then `GOOGLE_APPLICATION_CREDENTIALS`,
# then Application Default Credentials (`gcloud auth application-default login`), then the
# GCE/GKE metadata server.

# --- 2. Models: typed, or "provider/model-id" -----------------------------------------------

m = Model(Anthropic(), "claude-sonnet-4-5")
@show m
@show m == Model("anthropic/claude-sonnet-4-5")
@show m.provider m.id string(m)

# --- 3. Persist provider settings ----------------------------------------------------------

# Read the Anthropic key from a different ENV var (the key itself is never stored):
@show configure_provider!(Anthropic(); api_key_env = "MY_ANTHROPIC_KEY")
@show Anthropic()     # now picks up the saved setting

# `nothing` resets a setting to its default:
@show configure_provider!(Anthropic(); api_key_env = nothing)

# GoogleEnterprise has no built-in default project/location, so constructing it before one is
# saved throws instead of silently picking something:
show_error(() -> GoogleEnterprise())

@show configure_provider!(GoogleEnterprise(project = "example-project", location = "us-central1"))
@show GoogleEnterprise()   # now loads project/location from Preferences

# `project` and `location` can't be reset to `nothing` (there's no default to fall back to);
# `service_account_path` can:
show_error(() -> configure_provider!(GoogleEnterprise(); project = nothing))
@show configure_provider!(GoogleEnterprise(); service_account_path = "/path/to/key.json")
@show configure_provider!(GoogleEnterprise(); service_account_path = nothing)

# Opt in to the Interactions API (server-side chaining; tool results are unreliable on Vertex),
# and back to the generateContent default:
@show configure_provider!(GoogleEnterprise(); api = :interactions)
@show configure_provider!(GoogleEnterprise(); api = nothing)
show_error(() -> GoogleEnterprise(api = :chat_completions))

# --- 4. OpenAI-compatible servers ----------------------------------------------------------

lmstudio = register_provider!(
    OpenAICompatible("lmstudio", "http://localhost:1234/v1"; api = :chat_completions))
@show lmstudio

register_provider!(
    OpenAICompatible("openrouter", "https://openrouter.ai/api/v1"; api_key_env = "OPENROUTER_API_KEY"))

@show OpenAICompatible("openrouter")          # load a registered endpoint by name
@show Model("openrouter/openai/gpt-5")        # split on the first '/': id is "openai/gpt-5"
@show Model("lmstudio/qwen3:8b")
@show Model("google_enterprise/gemini-2.5-flash")

println("\nConfigured providers:")
foreach(p -> println("  ", p), providers())

# --- 5. Default model ----------------------------------------------------------------------

set_default_model!("anthropic/claude-sonnet-4-5")
@show default_model()

set_default_model!(Model("lmstudio/qwen3:8b"))
@show default_model()

# --- 5b. Each provider can also have its own default model ---------------------------------
#
# Separate from the global default above: `use_provider!` (and the REPL's `use provider`, no
# model id) switch a session straight to *that provider's* saved default.

set_default_model!(Anthropic(), "claude-sonnet-4-5")
@show default_model(Anthropic())          # this provider's own default, not the global one

use_provider!(Anthropic())                # active session -> Anthropic's saved default
show_error(() -> use_provider!(lmstudio)) # ...unless nothing is saved for it yet

# --- 6. Misuse -----------------------------------------------------------------------------

println("\nErrors:")
show_error(() -> Model("claude-sonnet-4-5"))                          # no provider prefix
show_error(() -> Model("mistral/large"))                              # unknown provider
show_error(() -> OpenAICompatible("vllm"))                            # not registered
show_error(() -> OpenAICompatible("anthropic", "http://localhost"))   # reserved name
show_error(() -> configure_provider!(OpenAI(); api_key_env = "sk-proj-abc123"))  # a key, not a name
show_error(() -> configure_provider!(OpenAI(); model = "gpt-5"))      # model isn't provider config

# --- 7. Listing models (network; needs API keys in ENV / a live GCP project) ---------------

if LIVE
    for p in (OpenAI(), Anthropic(), Google())
        models = list_models(p)
        println("\n$(length(models)) models from $(p):")
        foreach(m -> println("  ", m), first(models, 5))
    end

    # GoogleEnterprise: real project + location required; unfiltered Google catalog (see the
    # note above), so this includes non-text models.
    ent = configure_provider!(GoogleEnterprise(project = "my-real-project", location = "global"))
    ent_models = list_models(ent)
    println("\n$(length(ent_models)) models from $(ent):")
    foreach(m -> println("  ", m), first(ent_models, 5))
end

# Missing key:
show_error(() -> list_models(Google(api_key_env = "JAIL_EXAMPLE_UNSET_VAR")))
