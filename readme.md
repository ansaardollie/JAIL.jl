
<a href="https://aibiolab.github.io/AskAI" target="_blank" rel="noopener noreferrer">
    <img alt="Static Badge" src="https://img.shields.io/badge/docs-0.1.2-green">
</a>

AskAI.jl, as its name suggests, is a straightforward tool for querying Large Language Models.
It supports Ollama, Google's Gemini API, and OpenAI-compatible chat-completions APIs, including locally hosted models. It is designed to be simple and direct: send prompts and questions to an AI provider, and optionally execute the included code within a sandboxed "playground" to avoid affecting the main scope.

The main macro, `@ai`, retrieves results from a large language model, while `@AI` executes the code within the "playground" scope and displays the output(or any errors.)

a REPL mode was also support. Press `}` to enter and backspace to exit

## Configuration

Set these environment variables before `using AskAI` (e.g. in `startup.jl` or your shell):

| Variable | Meaning |
|---|---|
| `ASK_AI_PROVIDER` | `gemini`, `ollama`, `openai` or `openai-compatible` |
| `ASK_AI_MODEL` | model name, e.g. `gpt-oss-20b` |
| `ASK_AI_BASE_URL` | server URL, with or without `/v1`; optional for `ollama` and `openai` |
| `ASK_AI_API_KEY` | API key; optional for local servers. `openai` also reads `OPENAI_API_KEY`, `gemini` reads `GEMINI_API_KEY` |
| `ASK_AI_CHAT_COMPLETIONS` | `true` to use `/v1/chat/completions` instead of the default `/v1/responses` API (`openai`, `openai-compatible` only) |

```julia
ENV["ASK_AI_PROVIDER"] = "openai-compatible"
ENV["ASK_AI_MODEL"] = "gpt-oss-20b"
ENV["ASK_AI_BASE_URL"] = "http://localhost:8000"

using AskAI
available_models()
@ai "Explain Julia multiple dispatch in one sentence."
```

or at runtime, where omitted keywords fall back to the variables above:

```julia
setapi("ollama", "qwen2.5:72b")
setapi("openai-compatible", "gpt-oss-20b"; url = "http://localhost:8000", api = "local-key")
```

The old `ENV["AskAI_config"] = "provider|model|key@url"` form still works but is deprecated.
Use `AskAI.Brain.stream = false` to make a non-streaming request.
AskAI also includes the current terminal dimensions in each prompt and asks the model to wrap
output to the available width (disable with `AskAI.Brain.terminal_hint = false`).
When a Markdown table is still too wide, the terminal renderer converts it to wrapped labeled
entries instead of allowing it to overflow.

## Overview
![AskAI](./overview.png)

## Screenshot
![screenshot](./docs/src/result3.png)
