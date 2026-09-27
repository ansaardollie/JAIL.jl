# JAIL.jl

JAIL (AI in Julia) gives Julia one API for talking to LLM providers. Provider APIs differ in
shape; JAIL hides that behind Julia types, so your code works the same whether the model
comes from OpenAI, Anthropic, Google, or an OpenAI-compatible server.

## Status

JAIL is an early rewrite. What works today:

- **Providers**: [`OpenAI`](@ref), [`Anthropic`](@ref), [`Google`](@ref) and
  [`OpenAICompatible`](@ref) servers, configured through Preferences.
- **Models**: typed [`Model`](@ref)s, live model listing with [`list_models`](@ref), and
  interactive selection with [`select_model!`](@ref).
- **Sessions**: [`Session`](@ref)s that hold a conversation's model and history, with a
  `"default"` session started when JAIL loads.
- **Chat**: [`chat!`](@ref) sends text turns on a session to any provider.
- **REPL modes**: `|` for listing and switching providers, models and sessions, `}` for
  chatting with the active session's model.

Not implemented yet: streaming, tool calling, images, reasoning output, the agentic (`&`) REPL
mode, and one-shot functions for text, code generation and extraction.

## Quick start

```julia
using JAIL

set_default_model!("anthropic/claude-sonnet-4-5")   # saved in Preferences
```

API keys are read from ENV (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY` by
default) and are never written to disk by JAIL.

In the Julia REPL, press `|` at an empty `julia>` prompt to open the model mode:

```text
(default: anthropic/claude-sonnet-4-5) model> models
(default: anthropic/claude-sonnet-4-5) model> use openai/gpt-5
```

Then press backspace, and `}` to chat with it:

```text
chat> What does @inbounds do?
```

## Where to go next

- [Concepts](guide/concepts.md): providers, models, sessions, and how configuration works.
- [Providers and configuration](guide/providers.md)
- [Models](guide/models.md)
- [Sessions](guide/sessions.md)
- [Chat](guide/chat.md)
- [REPL modes](guide/repl.md)
- [Reference](reference.md): every exported name.

Runnable scripts for each feature are in the repository's `examples/` folder.