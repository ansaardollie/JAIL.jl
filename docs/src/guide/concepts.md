# Concepts

## Provider and model are different things

A **provider** is the API vendor: OpenAI, Anthropic, Google, or a server that speaks the
OpenAI wire format. A **model** is one of that provider's choices, such as a GPT, Claude or
Gemini model. JAIL keeps them separate:

- A provider is a value such as `Anthropic()` that carries connection settings (base URL and
  the name of the ENV var holding the API key).
- A [`Model`](@ref) pairs a provider with a provider-specific model id.

```@example concepts
using JAIL

m = Model(Anthropic(), "claude-sonnet-4-5")
```

The short string form is `"provider/model-id"`. It splits on the first `/`, so model ids that
contain `/` (common on OpenRouter) still work:

```@example concepts
m == Model("anthropic/claude-sonnet-4-5")
```

[`OpenAI`](@ref) and [`OpenAICompatible`](@ref) are separate provider types. They share code
through a common parent type, [`AbstractOpenAIProvider`](@ref), rather than a flag on one type.

## Sessions

A [`Session`](@ref) holds one conversation: a name, the active model, optional system
instructions, and the message history. Any number can exist. When JAIL loads it starts a
session called `"default"`, which is the **active session**: the one the REPL modes and
session-less calls like `select_model!()` act on. See [Sessions](sessions.md).

History is stored as typed messages, not strings, and is independent of the provider, so a
session can switch model (even provider) mid-conversation. Concrete message types don't exist
yet, so history is currently always empty.

## Configuration lives in Preferences

JAIL's settings are stored with [Preferences.jl](https://github.com/JuliaPackaging/Preferences.jl)
in the active project's `LocalPreferences.toml`, under a `[JAIL]` table. They are read each
time they're needed, so changes, including hand edits to the file, take effect without
restarting Julia.

API keys are the exception. They stay in environment variables; JAIL stores only the *name*
of the variable to read (for example `api_key_env = "MY_ANTHROPIC_KEY"`). A value that doesn't
look like an ENV var name is rejected, which catches most attempts to paste a key itself.

The full list of keys is in [Preferences keys](providers.md#Preferences-keys).

## Planned: one core, two surfaces

JAIL will be used in two ways that share the same code:

- **REPL modes**: `|` for model selection (available now), `}` for asking questions and `&`
  for agentic work with tools and code generation (both planned). Each mode's prompt shows the
  model it is using.
- **Functions** for one-shot text, generated Julia code, and extracting Julia objects from
  natural language (planned).

Requests will use each provider's multi-turn API: OpenAI Responses, Anthropic Messages and
Google Interactions. `OpenAICompatible` servers default to Responses and can be switched to
Chat Completions for servers that lack it.
