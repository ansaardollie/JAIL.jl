
<a href="https://aibiolab.github.io/JAIL" target="_blank" rel="noopener noreferrer">
    <img alt="Static Badge" src="https://img.shields.io/badge/docs-0.1.2-green">
</a>

JAIL.jl, as its name suggests (AI in JL), is a straightforward tool for querying Large Language Models inside Julia.
It supports Ollama, Google's Gemini API, Anthropic models, and OpenAI-compatible APIs, including locally hosted models. It is designed to be simple and direct: send prompts and questions to an AI provider, and optionally execute the included code within a sandboxed "playground" to avoid affecting the main scope.

The main macro, `@ai`, retrieves results from a large language model, while `@AI` executes the code within the "playground" scope and displays the output(or any errors.)

a REPL mode was also support. Press `}` to enter and backspace to exit

## Configuration

Set these environment variables before `using JAIL` (e.g. in `startup.jl` or your shell):

| Variable | Meaning |
|---|---|
| `JAIL_PROVIDER` | `gemini`, `ollama`, `anthropic`, `openai` or `openai-compatible` |
| `JAIL_MODEL` | model name, e.g. `claude-3-5-sonnet-20241022` or `gpt-oss-20b` |
| `JAIL_BASE_URL` | server URL, with or without `/v1`; optional for `ollama`, `openai`, and `anthropic` |
| `JAIL_API_KEY` | API key; optional for local servers. OpenAI providers also read `OPENAI_API_KEY`, then `OPENAPI_API_KEY`; `gemini` reads `GEMINI_API_KEY`; `anthropic` reads `ANTHROPIC_API_KEY` |
| `JAIL_CHAT_COMPLETIONS` | `true` to use `/v1/chat/completions` instead of the default `/v1/responses` API (`openai`, `openai-compatible` only) |

```julia
ENV["JAIL_PROVIDER"] = "openai-compatible"
ENV["JAIL_MODEL"] = "gpt-oss-20b"
ENV["JAIL_BASE_URL"] = "http://localhost:8000"

using JAIL
available_models()
@ai "Explain Julia multiple dispatch in one sentence."
```

For Anthropic, set `ANTHROPIC_API_KEY` and select an Anthropic model. The default API URL is
`https://api.anthropic.com`; `JAIL_BASE_URL` is only needed for a compatible proxy or custom endpoint:

```julia
ENV["JAIL_PROVIDER"] = "anthropic"
ENV["JAIL_MODEL"] = "claude-3-5-sonnet-20241022"
ENV["ANTHROPIC_API_KEY"] = "your-anthropic-api-key"

using JAIL
available_models()
@ai "Explain Julia multiple dispatch in one sentence."
```

or at runtime, where omitted keywords fall back to the variables above:

```julia
setapi("ollama", "qwen2.5:72b")
setapi("openai-compatible", "gpt-oss-20b"; url = "http://localhost:8000", api = "local-key")
setapi("anthropic", "claude-3-5-sonnet-20241022"; api = "your-anthropic-api-key")
```

The old `ENV["JAIL_config"] = "provider|model|key@url"` form still works but is deprecated.
Use `JAIL.Brain.stream = false` to make a non-streaming request.
JAIL also includes the current terminal dimensions in each prompt and asks the model to wrap
output to the available width (disable with `JAIL.Brain.terminal_hint = false`).
When a Markdown table is still too wide, the terminal renderer converts it to wrapped labeled
entries instead of allowing it to overflow.

## Overview
![JAIL](./overview.png)

## Screenshot
![screenshot](./docs/src/result3.png)
