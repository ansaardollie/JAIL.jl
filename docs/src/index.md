# JAIL.jl

JAIL (AI in Julia) gives Julia one API for talking to LLM providers. Provider APIs differ in
shape; JAIL hides that behind Julia types, so your code works the same whether the model
comes from OpenAI, Anthropic, Google (directly or through Google Cloud), or an OpenAI-compatible
server.

## Status

JAIL is an early rewrite. What works today:

- **Providers**: [`OpenAI`](@ref), [`Anthropic`](@ref), [`Google`](@ref),
  [`GoogleEnterprise`](@ref) (Gemini on Google Cloud) and [`OpenAICompatible`](@ref) servers,
  configured through Preferences.
- **Models**: typed [`Model`](@ref)s, live model listing with [`list_models`](@ref), and
  interactive selection with [`select_model!`](@ref).
- **Sessions**: [`Session`](@ref)s that hold a conversation's model and history, with a
  `"default"` session started when JAIL loads.
- **Chat**: [`chat!`](@ref) sends text-only turns on a session to any provider, optionally streamed,
  with a thinking effort and temperature per call, per session or in Preferences, and reasoning
  summaries shown as they stream.
- **Agents**: [`agent!`](@ref) runs a turn in agent mode: the model calls tools until it is done,
  shaped by an agent file (`*.agent.md`, `AGENTS.md`, `CLAUDE.md`) and skills (`SKILL.md`) found
  in the workspace, home and storage folders.
- **Tools**: Julia functions registered with [`register_tool!`](@ref) or [`@tool`](@ref);
  `agent!` runs the calls the model makes, asking first according to each tool's security level
  and your Preferences, and sends the results back. With tool search the model sees only the
  tools a session has loaded and finds the rest when it needs them.
- **Built-in tools**: tools for reading, searching and editing files, looking up Julia source
  and docs, running Julia code and shell commands, fetching web pages and asking you questions;
  all registered when JAIL loads (choose with the Preference `registered_tools`).
- **REPL modes**: `|` for listing and switching providers, models, sessions, tools, agents and
  skills, `}` for chatting with the active session's model, `&` for agent turns and `/skill`
  commands.

Not implemented yet: images, and one-shot functions for text, code
generation and extraction.

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

or `&` to let it work with tools:

```text
(julia) agent> Find the slowest test in test/ and explain why.
```

## Where to go next

- [Concepts](guide/concepts.md): providers, models, sessions, and how configuration works.
- [Providers and configuration](guide/providers.md)
- [Models](guide/models.md)
- [Sessions](guide/sessions.md)
- [Chat](guide/chat.md)
- [Tools](guide/tools.md), including the [built-in tools](guide/tools.md#Built-in-tools)
- [Agents and skills](guide/agents.md)
- [REPL modes](guide/repl.md)
- [Reference](reference.md): every exported name.
- [Built-in tools](builtin_tools.md): the docstrings the model sees for each built-in tool.

Runnable scripts for each feature are in the repository's `examples/` folder.