# Claude.jl API Inventory

## Scope and provenance

- Package: `Claude`, version `0.1.0`; Julia compatibility `1.6`; metadata and dependencies are defined in `libs/Claude.jl/Project.toml`.
- The package has one source module, `libs/Claude.jl/src/Claude.jl`, and does not include subordinate source files.
- Runtime dependencies are `HTTP.jl` and `JSON3.jl`; the test-only dependency is `Test`, as declared in `libs/Claude.jl/Project.toml`.
- The public export list is `ClaudeClient`, `chat`, `Message`, `Tool`, and `update_api_key!`, from `libs/Claude.jl/src/Claude.jl`.
- Visibility below means exported from `Claude` unless marked semi-public or internal.

## Core data types

### `Tool`

- Kind: immutable `struct`; exported.
- Defining file: `libs/Claude.jl/src/Claude.jl`.
- Declaration: `struct Tool`.
- Fields, in order:
  1. `type::String` — optional Anthropic tool type; the keyword constructor stores `""` when omitted.
  2. `name::String` — required tool name.
  3. `description::Union{String,Nothing}` — optional description.
  4. `input_schema::Union{Dict,Nothing}` — optional input schema dictionary.
  5. `display_width_px::Union{Int,Nothing}` — optional computer-use display width.
  6. `display_height_px::Union{Int,Nothing}` — optional computer-use display height.
  7. `display_number::Union{Int,Nothing}` — optional computer-use display number.
- Purpose: represent a tool that can be serialized into the request's `tools` array by `tool_to_dict`.

### `Message`

- Kind: immutable `struct`; exported.
- Defining file: `libs/Claude.jl/src/Claude.jl`.
- Declaration: `struct Message`.
- Fields: `role::String`, `content::String`.
- Constructor: `Message(role::String, content::String)`.
- Purpose: represent one conversation turn for the multi-message `chat` method.

### `ClaudeClient`

- Kind: mutable `struct`; exported.
- Defining file: `libs/Claude.jl/src/Claude.jl`.
- Fields:
  1. `api_key::String` — Anthropic API key.
  2. `model::String` — model identifier.
  3. `max_tokens::Int` — request output-token limit.
  4. `tools::Vector{Tool}` — tools attached to requests.
  5. `base_url::String` — API base URL.
  6. `headers::Dict{String,String}` — prebuilt request headers.
- Keyword constructor: `ClaudeClient(; api_key::Union{String,Nothing}=nothing, model::String="claude-3-5-sonnet-20241022", max_tokens::Int=1024, tools::Vector{Tool}=Tool[], base_url::String="https://api.anthropic.com/v1")`.
- Constructor behavior: when `api_key` is `nothing`, reads `ENV["ANTHROPIC_API_KEY"]`; an absent or empty value raises `ErrorException`. It builds `content-type`, `x-api-key`, `anthropic-version="2023-06-01"`, and `anthropic-beta="computer-use-2024-10-22"` headers.
- Purpose: hold authentication, request defaults, endpoint configuration, and reusable headers for `chat`.

## Client mutation and serialization

### `update_api_key!`

- Kind: function; exported.
- Defining file: `libs/Claude.jl/src/Claude.jl`.
- Methods:
  1. `update_api_key!(client::ClaudeClient, new_key::String)`
- Purpose: mutate both `client.api_key` and `client.headers["x-api-key"]`; returns the same client.

### `tool_to_dict`

- Kind: function; internal/semi-public, not exported.
- Defining file: `libs/Claude.jl/src/Claude.jl`.
- Methods:
  1. `tool_to_dict(tool::Tool)`
- Purpose: create a `Dict{String,Any}` containing `name` and any nonempty/non-`nothing` tool fields. The `type` field is omitted when its stored value is empty.
- Note: `libs/Claude.jl/test/runtests.jl` calls `Claude.tool_to_dict` directly, so the test suite treats this non-exported helper as an observable module API even though the export list does not.

## Chat operations

### `chat`

- Kind: function; exported.
- Defining file: `libs/Claude.jl/src/Claude.jl`.
- Methods:
  1. `chat(client::ClaudeClient, messages::Vector{Message})`
     - POSTs to `"$(client.base_url)/messages"` with `HTTP.post`.
     - Sends a JSON body containing `model`, `max_tokens`, and `messages`; each message becomes `Dict("role" => m.role, "content" => m.content)`.
     - Adds `tools` as serialized dictionaries when `client.tools` is nonempty.
     - On HTTP status `200`, returns `JSON3.read(response.body)`.
     - On any other status, raises `ErrorException("API request failed with status $(response.status)")` and discards the response body.
  2. `chat(client::ClaudeClient, message::String)`
     - Convenience method that calls the vector method with `[Message("user", message)]`.
- Purpose: issue a synchronous Anthropic Messages API request for either one user message or a typed conversation.
- Response contract in implementation: a JSON3 object with fields determined by the server response. The source does not normalize content, usage, or metadata into Claude.jl structs.

## Module visibility and package structure

- Module: `Claude`, defined entirely in `libs/Claude.jl/src/Claude.jl`.
- Imports: `HTTP`, `JSON3`, and `Base.Iterators`; the current source does not use an `include` chain.
- Exported symbols: `ClaudeClient`, `chat`, `Message`, `Tool`, `update_api_key!`.
- No macros, constants, abstract types, streaming types, callback types, or generated client layer are defined in the inspected source.

## Not covered

- There is no `libs/Claude.jl/docs/` directory, `NEWS.md`, or `CHANGELOG.md` in the package tree, so no separate documentation or release-history API claims could be checked.
- Live Anthropic behavior, authentication validity, rate limits, model availability, and actual response schemas are not inferable from static source. The package's own tests replace `HTTP.post` with a mock and do not contact Anthropic; see `libs/Claude.jl/test/runtests.jl`.
- The README and `libs/Claude.jl/example.jl` show `response.content[1].text`, while the test mock uses a string-valued `content` and asserts `response.content == "Hello!"`. The implementation simply returns parsed JSON and does not enforce either shape; consumers must follow the actual server response.
