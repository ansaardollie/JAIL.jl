
<a href="https://aibiolab.github.io/AskAI" target="_blank" rel="noopener noreferrer">
    <img alt="Static Badge" src="https://img.shields.io/badge/docs-0.1.2-green">
</a>

AskAI.jl, as its name suggests, is a straightforward tool for querying Large Language Models.
It supports Ollama, Google's Gemini API, and OpenAI-compatible chat-completions APIs, including locally hosted models. It is designed to be simple and direct: send prompts and questions to an AI provider, and optionally execute the included code within a sandboxed "playground" to avoid affecting the main scope.

The main macro, `@ai`, retrieves results from a large language model, while `@AI` executes the code within the "playground" scope and displays the output(or any errors.)

a REPL mode was also support. Press `}` to enter and backspace to exit

## Local OpenAI-compatible models

For a local server exposing `/v1/chat/completions` and `/v1/models`, set the server URL in
`AskAI_config`, using `key@url` in its third field:

```julia
ENV["AskAI_config"] = "openai-compatible|gpt-oss-20b|your-local-api-key@http://localhost:8000"

using AskAI
AskAI.avaliableModels()
@ai "Explain Julia multiple dispatch in one sentence."
```

Put the optional key and URL together as `key@url` in the third field. For an unauthenticated
server, use `@url`. A URL-only third field is also supported and falls back to `AskAI_key`.
The provider accepts a bare hostname as well as a full URL and appends `/v1` automatically.
Use `AskAI.Brain.stream = false` to make a non-streaming request.
AskAI also includes the current terminal dimensions in each prompt and asks the model to wrap
output to the available width.
When a Markdown table is still too wide, the terminal renderer converts it to wrapped labeled
entries instead of allowing it to overflow.

## Overview
![AskAI](./overview.png)

## Screenshot
![screenshot](./docs/src/result3.png)
