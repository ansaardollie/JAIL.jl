# PromptingTools.jl Usage Guide

## Central abstractions

PromptingTools is a thin, multiple-dispatch orchestration layer over several LLM providers. Users normally call one of the exported `ai*` functions, which resolve a model alias through `MODEL_REGISTRY`, choose a prompt schema, render typed messages, call the provider, normalize usage, and return a message wrapper. The top-level forwarding methods and schema root live in `libs/PromptingTools.jl/src/llm_interface.jl`; module composition is in `libs/PromptingTools.jl/src/PromptingTools.jl`.

The stable user-facing objects are message wrappers: `UserMessage` and `SystemMessage` carry prompt content and handlebars variables, `AIMessage` carries text output, `DataMessage` carries embeddings or extracted data, and `AIToolRequest`/`ToolMessage` represent tool calls. Their definitions and accessors are in `libs/PromptingTools.jl/src/messages.jl`.

## Processing pipeline

1. **Configure credentials and defaults.** On initialization, `load_api_keys!()` loads Preferences.jl values before environment variables. Defaults include `MODEL_CHAT = "gpt-5-mini"`, `MODEL_EMBEDDING = "text-embedding-3-small"`, and `MODEL_IMAGE_GENERATION = "dall-e-3"`; see `libs/PromptingTools.jl/src/user_preferences.jl`.
2. **Select a model and schema.** `aigenerate(prompt; model=...)` and sibling functions look up `MODEL_REGISTRY`; an unregistered model uses `PROMPT_SCHEMA`. Register custom models with `register_model!` when the schema or cost metadata differs from the default; see `user_preferences.jl`.
3. **Normalize prompt input.** Strings, `AbstractMessage`s, vectors of messages, and `AITemplate`s are accepted. `render(NoSchema(), ...)` performs handlebars replacement, injects a default system message unless disabled, filters annotation messages, and rejects multiple system messages; see `src/llm_shared.jl` and `src/templates.jl`.
4. **Render for the provider.** The selected schema transforms messages into OpenAI-compatible dictionaries, Anthropic content blocks, Google contents, Ollama payloads, ShareGPT records, or Responses API input. Provider-specific rendering is in `src/llm_openai_chat.jl`, `src/llm_openai_responses.jl`, `src/llm_anthropic.jl`, `src/llm_google.jl`, `src/llm_ollama.jl`, and `src/llm_sharegpt.jl`.
5. **Call the endpoint and normalize output.** Provider methods call OpenAI.jl, GoogleGenAI, HTTP, or the relevant native client, then build `AIMessage`, `DataMessage`, or `AIToolRequest`. `TokenUsage` standardizes token counts, cache fields, cost, and elapsed time; see `src/messages.jl`, `src/utils_usage.jl`, and provider files.
6. **Finalize the result.** With `return_all=false` the last message is returned; with `return_all=true` the rendered conversation is reconstructed with the generated message. `dry_run=true` stops after rendering; `finalize_outputs` is in `src/llm_shared.jl`.

## Idiomatic worked examples

### Basic generation and continuation

```julia
using PromptingTools

answer = aigenerate("What is the capital of France?")
println(answer.content)

answer = ai"Explain multiple dispatch in one paragraph."
followup = ai!"Now give a Julia example."
```

The string macros are defined in `libs/PromptingTools.jl/src/macros.jl`; `ai!` requires an existing conversation in `CONV_HISTORY`, while `aai` and `aai!` return spawned asynchronous tasks.

### Templated conversations

```julia
using PromptingTools

answer = aigenerate(:JuliaExpertAsk; ask = "How do I add a package?")
metadata = aitemplates("Julia")
rendered = render(AITemplate(:JuliaExpertAsk); ask = "How do I add a package?")
```

Templates are JSON files loaded from the package `templates/` paths into `TEMPLATE_STORE` during `__init__`; custom paths can be loaded with `load_templates!(path)`. Template serialization and metadata construction are implemented in `src/templates.jl` and `src/serialization.jl`.

### Explicit schemas and conversations

```julia
using PromptingTools

conversation = AbstractMessage[
    SystemMessage("You are a concise assistant."),
    UserMessage("Compare tuples and named tuples in Julia.")
]
answer = aigenerate(OpenAISchema(), conversation)
all_messages = aigenerate(OpenAISchema(), conversation; return_all = true)
preview = aigenerate(OpenAISchema(), conversation; dry_run = true)
```

Use an explicit schema when the model is not registered, when testing, or when selecting a native provider path. `OpenAIResponseSchema()` is for the OpenAI `/responses` endpoint; `AnthropicSchema()`, `GoogleSchema()`, `OllamaSchema()`, and `ShareGPTSchema()` select their corresponding formats. Definitions and provider contracts are in `src/llm_interface.jl` and `src/llm_*.jl`.

### Conversation memory

```julia
using PromptingTools

memory = ConversationMemory()
push!(memory, SystemMessage("You are helpful."))
memory("What is a Julia struct?"; model = "gpt5m")
memory("How do I construct one?"; last = 5, model = "gpt5m")
recent = get_last(memory, 5; batch_size = 5, explain = true)
```

`ConversationMemory` keeps a typed conversation, preserves the system and first user message during truncation, and can align truncation to batches for provider caching. Its methods are in `src/memory.jl`.

### Structured extraction and tools

```julia
using PromptingTools

struct Recipe
    name::String
    servings::Int
end

result = aiextract(Recipe, "Extract the recipe name and servings from: ...")
```

For callable tools, construct `Tool` or `ToolRef` and pass them through `aitools` using the provider-supported `api_kwargs`. Schema generation uses type fields and docstrings; `to_json_schema` and tool execution helpers are in `src/extraction.jl`. Exact keyword shape varies by provider, so inspect the provider renderer before composing advanced tool calls.

### Local and compatible providers

```julia
using PromptingTools

local_answer = aigenerate(LocalServerOpenAISchema(), "Say hi";
    model = "local", api_kwargs = (; url = "http://127.0.0.1:10897/v1"))

mistral_answer = aigenerate(MistralOpenAISchema(), "Say hi";
    model = "mistral-small")
```

OpenAI-compatible providers are separate schema types in `src/llm_interface.jl`; their URL, API-key, and endpoint behavior is implemented in `src/llm_openai_schema_defs.jl`. Native Google and Anthropic use their own schemas and dependencies.

## Extension points

- **New provider:** define a subtype of `AbstractPromptSchema`, then implement `render`, provider request methods, `response_to_message`, `extract_usage`, and the required `ai*` methods. The intended file boundary is `src/llm_<provider>.jl`, documented in `libs/PromptingTools.jl/CLAUDE.md`.
- **New model:** define or reuse a schema and call `register_model!(; name, schema, cost_of_token_prompt, cost_of_token_generation, description)`. Registration is runtime-only; startup scripts are recommended for persistence, per `src/user_preferences.jl`.
- **Tracing and persistence:** wrap an existing schema with `TracerSchema` and/or `SaverSchema`; extend `initialize_tracer` and `finalize_tracer` for custom observability in `src/llm_tracer.jl`.
- **Streaming:** pass a `StreamCallback` or IO/Channel through the provider-supported streaming keyword path. `configure_callback!` selects the callback flavor and stream flags; callback implementation belongs to StreamCallbacks.jl, as stated in `src/streaming.jl`.
- **Messages and annotations:** define `AbstractMessage` subtypes for application metadata, or use `AnnotationMessage` when content should be kept in local history but filtered from the LLM prompt; see `src/messages.jl`.
- **Template library:** store JSON message templates, load them with `load_templates!`, and expose searchable metadata through `aitemplates`; see `src/templates.jl`.

## Naming conventions

- User-facing task functions start with `ai`: `aigenerate`, `aiembed`, `aiclassify`, `aiextract`, `aitools`, `aiscan`, and `aiimage`; this is stated in `README.md` and enforced by the top-level export list.
- Schema types use provider or format names plus `Schema`, for example `OpenAISchema`, `AnthropicSchema`, `OllamaSchema`, and `ShareGPTSchema`.
- Message types end in `Message`; model configuration is represented by `ModelSpec` and `ModelRegistry`.
- API-specific model keywords go in `api_kwargs`; transport keywords go in `http_kwargs`; placeholder values remain ordinary keyword arguments. This separation is used throughout `src/llm_interface.jl` and the README.

## Sharp edges and limitations

- `ai!` and `aai!` assert that conversation history already exists. Start with `ai"..."` or `aai"..."`; see `src/macros.jl`.
- Provider schemas do not have identical capabilities. Anthropic requires a user message and handles system content separately; Ollama managed mode does not support streaming; Google behavior depends on the optional `GoogleGenAI` extension. Sources: `src/llm_anthropic.jl`, `src/streaming.jl`, and `ext/GoogleGenAIPromptingToolsExt.jl`.
- `dry_run` is useful for inspecting rendered requests but does not exercise authentication, network behavior, or provider response parsing; finalization is in `src/llm_shared.jl`.
- `AICode` executes model-produced Julia code. Its default constructor enables safe checks but still represents an execution surface; package operations and missing imports are blocked only under the safety path. See `src/code_eval.jl`.
- `PromptingTools.Experimental` is explicitly unstable. AgentTools uses lazy calls, sample trees, retries, and experimental self-fixing; RAG functionality has moved to the separate RAGTools.jl package, as stated in `README.md` and `src/Experimental/Experimental.jl`.
- Preferences take precedence over environment variables and can include API keys. Do not synchronize `LocalPreferences.toml`; the warning and allowed keys are in `src/user_preferences.jl`.
- The vendored package has optional weak dependencies for Markdown and GoogleGenAI. Extension behavior is only active when those packages are available; see `Project.toml` and `ext/`.

## Not covered

This guide does not claim live compatibility with any provider, current model pricing, or network behavior. It also does not walk every provider-specific keyword or every experimental AgentTools/APITools operation. The source files named above are authoritative for those narrower contracts; the package's test and setup commands are in `libs/PromptingTools.jl/CLAUDE.md`.
