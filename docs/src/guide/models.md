# Models

```@setup models
using JAIL
register_provider!(OpenAICompatible("openrouter", "https://openrouter.ai/api/v1";
                                    api_key_env = "OPENROUTER_API_KEY"))
```

## Writing a model

A [`Model`](@ref) is a provider plus a model id. Build one from values or from a
`"provider/model-id"` string:

```@example models
using JAIL

Model(Google(), "gemini-3.8-flash")
```

With an `openrouter` endpoint registered (see [Providers](providers.md)):

```@example models
m = Model("openrouter/openai/gpt-5")
```

Only the first `/` separates provider from id:

```@example models
m.id
```

`string` gives back the short form:

```@example models
string(Model(OpenAI(), "gpt-5"))
```

The provider in a string is looked up by name among the built-in providers (`google_enterprise`
only once its project and location are saved) and registered
[`OpenAICompatible`](@ref) endpoints (see [Providers](providers.md)):

```@example models
try
    Model("mistral/large")
catch e
    showerror(stdout, e)
end
```

```@example models
try
    Model("claude-sonnet-4-5")
catch e
    showerror(stdout, e)
end
```

## Listing models

[`list_models`](@ref) asks the provider's API which models are available. It needs network
access and the API key in the configured ENV var:

```julia
list_models(Anthropic())                          # Vector{Model{Anthropic}}
list_models(OpenAICompatible("lmstudio"))
```

Results are sorted by id: alphabetical, ignoring case, with numbers compared numerically so
versions in a family ascend. For example `claude-opus-4-9` comes before `claude-opus-4-10`,
and `gpt-5` before `gpt-10`.

Provider-specific notes:

- **OpenAI / OpenAI-compatible**: every model the server lists, including non-chat models
  (embeddings, speech, images).
- **Anthropic**: all pages are fetched.
- **Google**: all pages are fetched, and only models whose `supportedGenerationMethods`
  include `generateContent` are kept.
- **GoogleEnterprise**: all pages of Google's own Vertex AI models are fetched. The listing has
  no capability field, so non-chat models (embeddings, speech, images) are included. Partner
  models are not listed.

## Choosing a model interactively

[`select_model!`](@ref) shows a provider menu, then a menu of that provider's models (fetched
live). Arrow keys move, Enter picks, `q` cancels:

```julia
select_model!()                   # active session: provider menu, then model menu
select_model!(Anthropic())        # active session: skip the provider menu
select_model!(s)                  # a specific session
select_model!(s, Anthropic())
```

- The provider menu notes providers whose key ENV var is unset.
- The model menu marks the session's current model with `*` and starts on it.
- It returns the chosen `Model`, or `nothing` if you cancel or the models can't be listed.
  In the second case the error is printed rather than thrown.
- It changes a session's model only. To change what new sessions start with, use
  [`set_default_model!`](@ref).

If listing fails, nothing is selected:

```@example models
select_model!(Google(api_key_env = "JAIL_DOCS_UNSET_VAR"))
```

## The default model

The default model is saved in Preferences. New sessions start with it, and so does the
`"default"` session the next time JAIL loads:

```@example models
set_default_model!("anthropic/claude-sonnet-4-5")
```

```@example models
default_model()
```

Only the provider name and model id are stored. The id isn't checked against the provider.

## Per-provider default models

Separate from the model above, each provider can have its own default, used by
[`use_provider!`](@ref) and the REPL's `use provider` (no model id):

```@example models
set_default_model!(Anthropic(), "claude-sonnet-4-5")
```

```@example models
default_model(Anthropic())
```

```@example models
use_provider!(Anthropic())   # active session -> Anthropic's saved default
```

Calling either on a provider with nothing saved throws, rather than falling back to the global
default model:

```@example models
try
    default_model(OpenAICompatible("openrouter"))
catch e
    showerror(stdout, e)
end
```
