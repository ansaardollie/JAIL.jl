# OpenAI.jl Usage Guide

## Central abstractions

OpenAI.jl offers an ergonomic handwritten wrapper and a broad generated OpenAPI client. Use the handwritten layer for common model, chat, completion, embedding, image, response, and streaming calls. Use `OpenAIClient` when you need typed request/response models or an endpoint exposed by the current OpenAPI snapshot. This split is described in `libs/OpenAI.jl/AGENTS.md` and implemented by `libs/OpenAI.jl/src/OpenAI.jl`.

The handwritten layer accepts ordinary Julia dictionaries, vectors, strings, and keyword arguments, serializes keyword arguments with JSON3, sends requests through HTTP.jl, and returns `OpenAIResponse(status, response)`. The generated layer builds typed `OpenAPI.APIModel` values, groups endpoint methods under API structs, and returns parsed data together with an `OpenAPI.Clients.ApiResponse`. Sources: `libs/OpenAI.jl/src/OpenAI.jl`, `libs/OpenAI.jl/src/generated/apis/`, and `libs/OpenAI.jl/src/generated/models/`.

## Recommended processing pipelines

### 1. Handwritten non-streaming request

1. Obtain the API key from `ENV["OPENAI_API_KEY"]`.
2. Choose a model and build a Julia-native message/input value.
3. Call an endpoint such as `create_chat`, `create_completion`, `create_embeddings`, `create_images`, or `create_responses`.
4. Read `result.status` and the parsed JSON-like `result.response` object.
5. Pass `http_kwargs=(connection_timeout=...,)` when HTTP.jl request options are needed.

```julia
using OpenAI

api_key = ENV["OPENAI_API_KEY"]
messages = [Dict("role" => "user", "content" => "Say hello.")]
result = create_chat(api_key, "gpt-5-mini", messages)
println(result.response[:choices][begin][:message][:content])
```

This is the documented quick-start shape in `libs/OpenAI.jl/README.md` and the endpoint implementation is in `libs/OpenAI.jl/src/OpenAI.jl`.

### 2. Provider override

Construct `OpenAIProvider` for a compatible non-default endpoint or `AzureProvider` for Azure-style authentication, then pass the provider to the provider overloads. The provider controls the base URL and authentication headers. The README documents `OpenAIProvider`; provider definitions and header behavior are in `libs/OpenAI.jl/src/OpenAI.jl`.

```julia
using OpenAI

provider = OpenAIProvider(
    api_key = ENV["OPENAI_API_KEY"],
    base_url = ENV["OPENAI_BASE_URL_OVERRIDE"],
)
result = create_chat(provider, "gpt-5-mini", [
    Dict("role" => "user", "content" => "Write one line of poetry.")
])
```

### 3. Streaming with StreamCallbacks

Pass `streamcallback` to `create_chat`; do not manually set `stream=true` for that handwritten helper. An IO, Channel, Function, or `StreamCallback` is accepted. OpenAI.jl configures an `OpenAIStream` flavor and adds usage-aware stream options before invoking `StreamCallbacks.stream...`. Sources: `libs/OpenAI.jl/src/OpenAI.jl`, `libs/OpenAI.jl/docs/src/streaming.md`, and `libs/OpenAI.jl/examples/streamcallbacks.jl`.

```julia
using OpenAI

messages = [Dict("role" => "user", "content" => "Write a short haiku.")]
create_chat(ENV["OPENAI_API_KEY"], "gpt-5-mini", messages; streamcallback = stdout)

cb = StreamCallback()
create_chat(ENV["OPENAI_API_KEY"], "gpt-5-mini", messages; streamcallback = cb)
println(length(cb.chunks))
```

For custom processing, extend `StreamCallbacks.print_content` or `StreamCallbacks.callback`, using `extract_content` to interpret OpenAI chunks. The extension pattern is shown in `libs/OpenAI.jl/docs/src/streaming.md` and `libs/OpenAI.jl/examples/streamcallbacks.jl`.

### 4. Generated typed client

1. Call `openai_client(api_key)` or `openai_client(provider; kwargs...)`.
2. Construct an API group with the client, such as `OpenAIClient.ModelsApi(client)`.
3. Construct generated request models with keyword constructors where required.
4. Call a generated operation and destructure `(data, http_response)`.

```julia
using OpenAI

client = openai_client(ENV["OPENAI_API_KEY"])
models_api = OpenAIClient.ModelsApi(client)
models, http_response = OpenAIClient.list_models(models_api)
@assert http_response.status == 200
println(models.data)
```

For a typed request:

```julia
request = OpenAIClient.CreateChatCompletionRequest(
    model = "gpt-5-mini",
    messages = [OpenAIClient.ChatCompletionRequestUserMessage(
        content = "Hello",
        role = "user",
    )],
)
api = OpenAIClient.ChatApi(client)
response, http_response = OpenAIClient.create_chat_completion(api, request)
```

The client construction contract is implemented in `libs/OpenAI.jl/src/OpenAI.jl`; generated model validation is visible in `libs/OpenAI.jl/src/generated/models/model_CreateChatCompletionRequest.jl`; generated operation execution is visible in `libs/OpenAI.jl/src/generated/apis/api_ChatApi.jl`.

## Extension points

- Provider configuration: subtype or use `AbstractOpenAIProvider`-compatible provider data only if the existing authentication and URL method contract is preserved; built-in implementations are in `libs/OpenAI.jl/src/OpenAI.jl`.
- Streaming output: overload `StreamCallbacks.print_content` for output formatting or `StreamCallbacks.callback` for chunk processing; examples are in `libs/OpenAI.jl/examples/streamcallbacks.jl`.
- HTTP client behavior: pass supported `OpenAPI.Clients.Client` options through `openai_client(...; kwargs...)`, or HTTP.jl options through handwritten `http_kwargs`; documented in `libs/OpenAI.jl/src/OpenAI.jl` and `libs/OpenAI.jl/README.md`.
- Generated API coverage: update `openapi/openapi.yaml` and regenerate with `libs/OpenAI.jl/scripts/generate_openapi_client.sh`; generated files explicitly say not to edit them directly.

## Naming and design conventions

- Handwritten endpoint names use verbs such as `list_`, `retrieve_`, `create_`, `modify_`, `delete_`, and `cancel_`.
- Handwritten calls use an API key or provider first, then endpoint identifiers and payloads; `http_kwargs` is reserved for transport options and other keywords become request fields.
- Generated API groups end in `Api`, generated schema types are PascalCase, generated request types commonly end in `Request` or `Param`, and generated operations mirror OpenAPI operation names in snake_case. Sources: `libs/OpenAI.jl/src/generated/OpenAIClient.jl` and `libs/OpenAI.jl/src/generated/apis/`.
- Generated models are mutable keyword structs with `nothing` defaults where schemas permit optional values, and validation hooks are installed through OpenAPI.jl. Source: `libs/OpenAI.jl/src/generated/models/`.

## Sharp edges and limitations

- The API key is required at request time; empty keys trigger `ArgumentError` in the handwritten authentication helpers. Source: `libs/OpenAI.jl/src/OpenAI.jl`.
- `create_chat` streaming is configured by `streamcallback`; the docs specifically advise against manually using `stream=true` with that helper. Source: `libs/OpenAI.jl/docs/src/index.md`.
- The handwritten wrapper returns JSON3 objects with symbol/string indexing patterns, while the generated client returns typed models plus HTTP response metadata. Do not mix access patterns without checking which layer produced the value. Sources: `libs/OpenAI.jl/src/OpenAI.jl` and `libs/OpenAI.jl/src/generated/apis/`.
- The generated client reflects a committed OpenAPI snapshot, not necessarily every current server feature. Regeneration requires Docker and may emit generator warnings; source: `libs/OpenAI.jl/scripts/generate_openapi_client.sh` and `libs/OpenAI.jl/AGENTS.md`.
- Assistant helper exports are inconsistent by design in this version: assistant CRUD exports are commented out, while thread/message/run helpers remain exported; the generated `AssistantsApi` is a separate active surface. Sources: `libs/OpenAI.jl/src/OpenAI.jl` and `libs/OpenAI.jl/src/assistants.jl`.
- Most tests are live API tests and depend on `OPENAI_API_KEY`, network access, model availability, and server behavior. Source: `libs/OpenAI.jl/test/runtests.jl` and `libs/OpenAI.jl/AGENTS.md`.

## Not covered

This guide does not claim that every generated endpoint has been manually exercised. It covers the intended usage patterns and representative generated operations; the complete endpoint list is in `libs/OpenAI.jl/src/generated/apis/`, and the complete model list is in `libs/OpenAI.jl/src/generated/modelincludes.jl`.
