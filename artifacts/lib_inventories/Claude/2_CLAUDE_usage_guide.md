# Claude.jl Usage Guide

## Central abstractions

`ClaudeClient` is the package's configuration and transport object. It stores the API key, model, output-token limit, tools, base URL, and the exact headers reused for every request (`libs/Claude.jl/src/Claude.jl`). `Message` is the minimal conversation value type, containing only a role and string content. `Tool` is the optional tool declaration type, including Anthropic tool metadata and computer-use display fields. `chat` accepts either one string or a vector of `Message` values and returns the server response parsed by JSON3.

The package is a thin synchronous wrapper around Anthropic's Messages endpoint. It does not introduce a response struct, conversation state object, streaming abstraction, retry policy, or typed error hierarchy (`libs/Claude.jl/src/Claude.jl`).

## Recommended processing pipeline

### 1. Configure authentication and request defaults

Create a client with an explicit key or let the constructor read `ANTHROPIC_API_KEY`:

```julia
using Claude

client = ClaudeClient(
    api_key = ENV["ANTHROPIC_API_KEY"],
    model = "claude-3-5-sonnet-20241022",
    max_tokens = 1024,
)
```

The constructor rejects a missing or empty key and prepares the JSON content type, `x-api-key`, Anthropic version, and computer-use beta headers (`libs/Claude.jl/src/Claude.jl`). The README documents the same environment-variable workflow in `libs/Claude.jl/README.md`.

### 2. Send a single-turn request

Use the string convenience method for a single user message:

```julia
response = chat(client, "Why is Julia useful for scientific computing?")
println(response.role)
println(response.content)
```

`chat(client, message::String)` constructs `[Message("user", message)]` and delegates to the vector method (`libs/Claude.jl/src/Claude.jl`). The returned object is whatever `JSON3.read` produces from the server body, so field access should be checked against the endpoint's actual response shape.

### 3. Send a multi-turn request

Build a vector of `Message` values when preserving prior turns:

```julia
messages = [
    Message("user", "What is Julia good at?"),
    Message("assistant", "It is strong at numerical and technical computing."),
    Message("user", "Give me one practical example."),
]
response = chat(client, messages)
```

The vector method maps each message to a JSON object with `role` and `content`, without validating role names or enforcing alternation (`libs/Claude.jl/src/Claude.jl`). The multi-turn example is also documented in `libs/Claude.jl/README.md` and `libs/Claude.jl/READKR.md`.

### 4. Attach tools

Construct `Tool` values and pass them at client creation:

```julia
tool = Tool(
    type = "function",
    name = "lookup_weather",
    description = "Look up the weather for a city.",
    input_schema = Dict("type" => "object"),
)
client = ClaudeClient(api_key = ENV["ANTHROPIC_API_KEY"], tools = [tool])
response = chat(client, "What is the weather in Tokyo?")
```

Before sending, `chat` serializes each tool with `tool_to_dict`. `name` is always emitted; nonempty `type` and non-`nothing` description, schema, and display fields are emitted conditionally (`libs/Claude.jl/src/Claude.jl`).

### 5. Rotate credentials

Update an existing client's key with:

```julia
update_api_key!(client, ENV["ANTHROPIC_API_KEY_NEW"])
```

This updates both the public field and the header dictionary used by subsequent calls (`libs/Claude.jl/src/Claude.jl`).

## Extension points

- Endpoint selection: provide a custom `base_url` to `ClaudeClient`; `chat` appends `/messages` (`libs/Claude.jl/src/Claude.jl`).
- Request defaults: provide a custom `model`, `max_tokens`, or `tools` when constructing the client (`libs/Claude.jl/src/Claude.jl`).
- Payload shape: extend or replace the internal `tool_to_dict` behavior only with care, because it is used by `chat` and exercised directly by `libs/Claude.jl/test/runtests.jl`.
- Response processing: add application-level parsing around the JSON3 response; Claude.jl does not define a response type or callback hook (`libs/Claude.jl/src/Claude.jl`).
- Test transport: the existing tests mock `HTTP.post` by defining a method and return `HTTP.Response`; this is the local pattern for testing request outcomes without network access (`libs/Claude.jl/test/runtests.jl`).

## Naming and design conventions

- Public types use PascalCase (`ClaudeClient`, `Message`, `Tool`); operations use lowercase snake_case (`chat`, `update_api_key!`) (`libs/Claude.jl/src/Claude.jl`).
- Mutating operations use Julia's `!` convention; `update_api_key!` returns the mutated client (`libs/Claude.jl/src/Claude.jl`).
- Configuration is keyword-based on `ClaudeClient`, with concrete field types and defaults in the constructor (`libs/Claude.jl/src/Claude.jl`).
- HTTP and JSON concerns remain directly in the top-level module rather than behind a separate client or serializer layer (`libs/Claude.jl/src/Claude.jl`).

## Sharp edges and limitations

- The constructor requires an API key. `ClaudeClient()` only works when `ANTHROPIC_API_KEY` exists and is nonempty; otherwise it raises an `ErrorException` (`libs/Claude.jl/src/Claude.jl`).
- `chat` is synchronous and has no streaming support, timeout keyword, retry behavior, or cancellation API (`libs/Claude.jl/src/Claude.jl`).
- Non-200 responses lose the server's error body and are reduced to `ErrorException("API request failed with status ...")` (`libs/Claude.jl/src/Claude.jl`).
- `update_api_key!` mutates the header dictionary but does not validate the new key or rebuild any other client state (`libs/Claude.jl/src/Claude.jl`).
- The code sends the `anthropic-beta: computer-use-2024-10-22` header for every client, regardless of whether computer-use tools are configured (`libs/Claude.jl/src/Claude.jl`).
- The README and example access `response.content[1].text` (`libs/Claude.jl/README.md`, `libs/Claude.jl/example.jl`), but the test fixture uses string content and the implementation performs no normalization (`libs/Claude.jl/test/runtests.jl`, `libs/Claude.jl/src/Claude.jl`).
- Tool input schemas are typed as `Dict`, so callers cannot pass arbitrary typed mapping types without converting them first (`libs/Claude.jl/src/Claude.jl`).
- The tests patch the generic `HTTP.post(url, headers, body)` method globally within the test process (`libs/Claude.jl/test/runtests.jl`); this is useful for isolation but is not a production extension mechanism.

## Not covered

This guide does not claim live API compatibility, current Anthropic model availability, or production error semantics. The package contains no docs source directory, changelog, streaming implementation, or live integration test beyond the examples and README claims. Those areas would require direct server verification or additional package code (`libs/Claude.jl/README.md`, `libs/Claude.jl/src/Claude.jl`, `libs/Claude.jl/test/runtests.jl`).
