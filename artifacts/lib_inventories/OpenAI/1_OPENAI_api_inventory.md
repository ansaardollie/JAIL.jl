# OpenAI.jl API Inventory

## Scope and provenance

- Package: `OpenAI`, version `0.13.0`, Julia `1.9+`; metadata and dependencies are defined in `libs/OpenAI.jl/Project.toml`.
- The package has two public layers: handwritten convenience functions in `libs/OpenAI.jl/src/OpenAI.jl` and `libs/OpenAI.jl/src/assistants.jl`, plus a generated typed client included from `libs/OpenAI.jl/src/generated/OpenAIClient.jl`.
- Generated code is derived from `libs/OpenAI.jl/openapi/openapi.yaml`; the generator is `libs/OpenAI.jl/scripts/generate_openapi_client.sh`.
- Visibility below means exported from the relevant module unless marked semi-public or internal.

## Handwritten providers and request primitives

### Provider types

- `AbstractOpenAIProvider` - abstract type, exported indirectly by module membership but not listed in the package export block; defining file `libs/OpenAI.jl/src/OpenAI.jl`. Provider interface for authentication and URL construction.
- `OpenAIProvider <: AbstractOpenAIProvider` - `Base.@kwdef struct`; fields `api_key::String`, `base_url::String`, `api_version::String`; semi-public constructor/configuration type. Defaults are an empty key, `https://api.openai.com/v1`, and an empty version. Defining file: `libs/OpenAI.jl/src/OpenAI.jl`.
- `AzureProvider <: AbstractOpenAIProvider` - `Base.@kwdef struct`; fields `api_key::String`, `base_url::String`, `api_version::String`; semi-public Azure authentication/configuration type. Defining file: `libs/OpenAI.jl/src/OpenAI.jl`.
- `DEFAULT_PROVIDER` - constant, semi-public; chooses `OpenAIProvider(api_key=ENV["OPENAI_API_KEY"])` when the environment variable exists, otherwise an empty-key provider. Defining file: `libs/OpenAI.jl/src/OpenAI.jl`.
- `DEFAULT_EMBEDDING_MODEL_ID` - exported? No; constant `"text-embedding-ada-002"` used as the handwritten embeddings default. Defining file: `libs/OpenAI.jl/src/OpenAI.jl`.
- `OpenAIResponse{R}` - exported immutable `struct` with fields `status::Int16` and `response::R`; wrapper returned by handwritten non-streaming requests. Defining file: `libs/OpenAI.jl/src/OpenAI.jl`.

### Public/semi-public helpers

1. `auth_header(provider::AbstractOpenAIProvider)` and `auth_header(provider::AbstractOpenAIProvider, api_key::AbstractString)` - semi-public helpers. `OpenAIProvider` emits `Authorization: Bearer ...` and `Content-Type`; `AzureProvider` emits `api-key` and `Content-Type`. Empty keys throw `ArgumentError`. Defining file: `libs/OpenAI.jl/src/OpenAI.jl`.
2. `build_url(provider::OpenAIProvider, api::String)` and `build_url(provider::AzureProvider, api::String)` - semi-public URL builders; empty API paths throw `ArgumentError`. Defining file: `libs/OpenAI.jl/src/OpenAI.jl`.
3. `configure_callback!(streamcallback; kwargs...)` - semi-public; converts an IO, Channel, Function, or existing `StreamCallback` to an OpenAI-flavored callback and adds `stream=true` plus `stream_options=(include_usage=true,)`. Defining file: `libs/OpenAI.jl/src/OpenAI.jl`.
4. `print_content(f::Function, text::AbstractString; kwargs...)` - method extension on the imported `StreamCallbacks.print_content` generic; sends processed text to the function. It is not exported by the parent `OpenAI` module. Defining file: `libs/OpenAI.jl/src/OpenAI.jl`.
5. `openai_client(provider::AbstractOpenAIProvider=DEFAULT_PROVIDER; api_key::AbstractString=provider.api_key, headers::Dict{String,String}=Dict{String,String}(), kwargs...)` - exported constructor for an authenticated generated client. Forwards client options such as `timeout`, `long_polling_timeout`, `pre_request_hook`, `verbose`, and `httplib` to `OpenAPI.Clients.Client`.
6. `openai_client(api_key::AbstractString; base_url::AbstractString="https://api.openai.com/v1", headers::Dict{String,String}=Dict{String,String}(), kwargs...)` - exported convenience overload that constructs an `OpenAIProvider` first.

Internal request methods are `_request(api, provider, api_key=provider.api_key; method, query=nothing, http_kwargs, streamcallback=nothing, additional_headers=Pair{String,String}[], kwargs...)`, `openai_request(api, api_key; method, http_kwargs, streamcallback=nothing, kwargs...)`, `openai_request(api, provider; method, http_kwargs, streamcallback=nothing, kwargs...)`, `build_params(kwargs)`, `request_body(url, method; input, headers, query, kwargs...)`, `request_body_live(url; method, input, headers, streamcallback, kwargs...)`, and `status_error(resp, log=nothing)`. They are semi-public implementation details in `libs/OpenAI.jl/src/OpenAI.jl` and should not be treated as stable application API.

## Handwritten endpoint functions

All of these are exported from `libs/OpenAI.jl/src/OpenAI.jl` and return `OpenAIResponse` for ordinary requests. Keyword arguments named `http_kwargs` are forwarded to `HTTP.request`; endpoint keyword arguments become JSON request fields.

### Models

- `list_models(api_key::String; http_kwargs::NamedTuple=NamedTuple())` - list available models; `libs/OpenAI.jl/src/OpenAI.jl`.
- `retrieve_model(api_key::String, model_id::String; http_kwargs::NamedTuple=NamedTuple())` - retrieve one model; `libs/OpenAI.jl/src/OpenAI.jl`.

### Text and multimodal generation

- `create_completion(api_key::String, model_id::String; http_kwargs::NamedTuple=NamedTuple(), kwargs...)` - POST `/completions`; `libs/OpenAI.jl/src/OpenAI.jl`.
- `create_chat(api_key::String, model_id::String, messages; http_kwargs::NamedTuple=NamedTuple(), streamcallback=nothing, kwargs...)` - POST `/chat/completions`; `libs/OpenAI.jl/src/OpenAI.jl`.
- `create_chat(provider::AbstractOpenAIProvider, model_id::String, messages; http_kwargs::NamedTuple=NamedTuple(), streamcallback=nothing, kwargs...)` - provider overload; same file.
- `create_chat(schema, api_key::AbstractString, model::AbstractString, conversation; http_kwargs::NamedTuple=NamedTuple(), streamcallback::Any=nothing, kwargs...)` - compatibility/testing forwarding overload; same file.
- `create_responses(api_key::String, input, model="gpt-5-mini"; http_kwargs::NamedTuple=NamedTuple(), kwargs...)` - POST `/responses`; same file.
- `create_embeddings(api_key::String, input, model_id::String=DEFAULT_EMBEDDING_MODEL_ID; http_kwargs::NamedTuple=NamedTuple(), kwargs...)` - POST `/embeddings`; same file.
- `create_embeddings(provider::AbstractOpenAIProvider, input; model_id::String=DEFAULT_EMBEDDING_MODEL_ID, http_kwargs::NamedTuple=NamedTuple(), streamcallback=nothing, kwargs...)` - provider overload; same file.
- `create_images(api_key::String, prompt, n::Integer=1, size::String="256x256"; http_kwargs::NamedTuple=NamedTuple(), kwargs...)` - POST `/images/generations`; same file. Note: the current implementation forwards `prompt` and `kwargs`; `n` and `size` are positional API parameters but are not explicitly inserted into the request body in this source snapshot.

### StreamCallbacks integration

- `StreamCallback`, `OpenAIStream`, and `streamed_request!` are imported from `StreamCallbacks`; only `StreamCallback` is re-exported by `OpenAI` in `libs/OpenAI.jl/src/OpenAI.jl`.
- The intended public streaming input is `streamcallback=stdout`, an IO/Channel/Function, or a configured `StreamCallback`; `configure_callback!` supplies stream fields. See `libs/OpenAI.jl/docs/src/streaming.md` and `libs/OpenAI.jl/examples/streamcallbacks.jl`.

## Legacy handwritten Assistants/Threads surface

`libs/OpenAI.jl/src/assistants.jl` is included, but assistant exports are commented out in `libs/OpenAI.jl/src/OpenAI.jl`; the thread, message, and run functions below are exported. The implementation uses the legacy `OpenAI-Beta: assistants=v1` header and loose Julia dictionaries/keyword arguments.

- Assistant functions, semi-public/unexported: `create_assistant(api_key::String, model_id::String; name::String="", description::String="", instructions::String="", tools::Vector=[], file_ids::Vector=[], metadata::Dict=Dict(), http_kwargs::NamedTuple=NamedTuple())`; `get_assistant(api_key::String, assistant_id::String; http_kwargs::NamedTuple=NamedTuple())`; `list_assistants(api_key::AbstractString; limit::Union{Integer,AbstractString}=20, order::AbstractString="desc", after::AbstractString="", before::AbstractString="", http_kwargs::NamedTuple=NamedTuple())`; `modify_assistant(api_key::AbstractString, assistant_id::AbstractString; model=nothing, name=nothing, description=nothing, instructions=nothing, tools=nothing, file_ids=nothing, metadata=nothing, http_kwargs::NamedTuple=NamedTuple())`; `delete_assistant(api_key::AbstractString, assistant_id::AbstractString; http_kwargs::NamedTuple=NamedTuple())`.
- Thread functions, exported: `create_thread(api_key::AbstractString, messages=nothing; http_kwargs::NamedTuple=NamedTuple())`; `retrieve_thread(api_key::AbstractString, thread_id::AbstractString; http_kwargs::NamedTuple=NamedTuple())`; `delete_thread(api_key::AbstractString, thread_id::AbstractString; http_kwargs::NamedTuple=NamedTuple())`; `modify_thread(api_key::AbstractString, thread_id::AbstractString; metadata=nothing, http_kwargs::NamedTuple=NamedTuple())`.
- Message functions, exported: `create_message(api_key::AbstractString, thread_id::AbstractString, content::AbstractString; file_ids=nothing, metadata=nothing, http_kwargs::NamedTuple=NamedTuple())`; `retrieve_message(api_key::AbstractString, thread_id::AbstractString, message_id::AbstractString; http_kwargs::NamedTuple=NamedTuple())`; `delete_message(api_key::AbstractString, thread_id::AbstractString, message_id::AbstractString; http_kwargs::NamedTuple=NamedTuple())`; `modify_message(api_key::AbstractString, thread_id::AbstractString, message_id::AbstractString; metadata=nothing, http_kwargs::NamedTuple=NamedTuple())`; `list_messages(api_key::AbstractString, thread_id::AbstractString; limit::Union{Integer,AbstractString}=20, order::AbstractString="desc", after::AbstractString="", before::AbstractString="", http_kwargs::NamedTuple=NamedTuple())`.
- Run functions, exported: `create_run(api_key::AbstractString, thread_id::AbstractString, assistant_id::AbstractString, instructions=nothing; tools=nothing, metadata=nothing, model=nothing, http_kwargs::NamedTuple=NamedTuple())`; `retrieve_run(api_key::AbstractString, thread_id::AbstractString, run_id::AbstractString; http_kwargs::NamedTuple=NamedTuple())`; `modify_run(api_key::AbstractString, thread_id::AbstractString, run_id::AbstractString; metadata=nothing, http_kwargs::NamedTuple=NamedTuple())`; `list_runs(api_key::AbstractString, thread_id::AbstractString; limit::Union{Integer,AbstractString}=20, order::AbstractString="desc", after::AbstractString="", before::AbstractString="", http_kwargs::NamedTuple=NamedTuple())`; `cancel_run(api_key::AbstractString, thread_id::AbstractString, run_id::AbstractString; http_kwargs::NamedTuple=NamedTuple())`; `create_thread_and_run(api_key::AbstractString, assistant_id::AbstractString; thread=nothing, model=nothing, instructions=nothing, tools=nothing, metadata=nothing, http_kwargs::NamedTuple=NamedTuple())`. Defining file for all: `libs/OpenAI.jl/src/assistants.jl`.

## Generated OpenAIClient module

`OpenAI.OpenAIClient` is exported from the parent module and is generated code included by `libs/OpenAI.jl/src/OpenAI.jl`. The generated module declares `API_VERSION = "2.3.0"`, imports `OpenAPI`, `OpenAPI.Clients`, `Dates`, and `TimeZones`, then includes `modelincludes.jl` and every `apis/api_*.jl` file.

### Generated API group types and operations

Each API group is a `struct <: OpenAPI.APIClientImpl` with field `client::OpenAPI.Clients.Client`, a `basepath(::Type{...})` method, one exported operation per endpoint, and a second overload accepting `response_stream::Channel`. The exact signatures and return models are in the corresponding generated file.

- `AssistantsApi`, `AudioApi`, `AuditLogsApi`, `BatchApi`, `CertificatesApi`, `ChatApi`, `CompletionsApi`, `ConversationsApi`, `DefaultApi`, `EmbeddingsApi`, `EvalsApi`, `FilesApi`, `FineTuningApi`, `GroupOrganizationRoleAssignmentsApi`, `GroupUsersApi`, `GroupsApi`, `ImagesApi`, `InvitesApi`, `ModelsApi`, `ModerationsApi`, `ProjectGroupRoleAssignmentsApi`, `ProjectGroupsApi`, `ProjectUserRoleAssignmentsApi`, `ProjectsApi`, `RealtimeApi`, `ResponsesApi`, `RolesApi`, `SkillsApi`, `UploadsApi`, `UsageApi`, `UserOrganizationRoleAssignmentsApi`, `UsersApi`, `VectorStoresApi`, and `VideosApi` - generated API group structs. Defining files: `libs/OpenAI.jl/src/generated/apis/api_<Name>.jl`.
- Representative exact signatures: `ModelsApi(client)`, `list_models(_api::ModelsApi; _mediaType=nothing)`, `retrieve_model(_api::ModelsApi, model::String; _mediaType=nothing)`, `delete_model(_api::ModelsApi, model::String; _mediaType=nothing)` in `api_ModelsApi.jl`; `create_chat_completion(_api::ChatApi, create_chat_completion_request::CreateChatCompletionRequest; _mediaType=nothing)` and stored-completion operations in `api_ChatApi.jl`; `create_response(_api::ResponsesApi, create_response_param::CreateResponse; _mediaType=nothing)`, `get_response`, `delete_response`, `cancel_response`, and `list_input_items` in `api_ResponsesApi.jl`; file upload/download/list/retrieve/delete operations in `api_FilesApi.jl`.
- Generated operations return `OpenAPI.Clients.exec(_ctx)` as `(parsed_model, api_response)` in ordinary mode, or execute through the supplied `Channel` overload. Internal `_oacinternal_*` methods build request contexts and are internal, not user-facing.

### Generated models

- Every model included from `libs/OpenAI.jl/src/generated/models/model_*.jl` is an exported generated `Base.@kwdef mutable struct <: OpenAPI.APIModel` or a generated enum/union-like model. `libs/OpenAI.jl/src/generated/modelincludes.jl` is the authoritative complete include list; `libs/OpenAI.jl/src/generated/OpenAIClient.jl` is the authoritative export list.
- Model constructors use keyword defaults and generated positional constructors that call `OpenAPI.validate_properties`; required fields are checked by `OpenAPI.check_required`. Fields and exact types are defined in each model file. Examples: `Model(; id=nothing, created=nothing, object=nothing, owned_by=nothing)` in `model_Model.jl`; `CreateChatCompletionRequest(; metadata=nothing, ..., model=nothing, messages=nothing, ...)` in `model_CreateChatCompletionRequest.jl`; `CreateResponse(; metadata=nothing, ..., model=nothing, input=nothing, stream=false, ...)` in `model_CreateResponse.jl`.
- Model families are organized by generated schema concern rather than handwritten abstraction: chat/completions, responses and streaming events, assistants/threads/runs/messages, audio/transcription/speech, embeddings, images, files/uploads, batches, fine tuning, vector stores, realtime, moderation, evals, administration/projects/groups/users/roles, skills/videos, and shared error/annotation/resource types. Exact public names are the `export` lines in `OpenAIClient.jl`; exact fields are the corresponding `model_*.jl` files.

### Generated visibility summary

The generated model and operation exports are public within `OpenAIClient`; generated `_oacinternal_*`, `_returntypes_*`, and `_property_types_*` names are internal implementation details. The parent `OpenAI` module exports only `OpenAIClient`, not every generated model or operation.

## Not covered

- I did not reproduce hundreds of generated model names and every generated operation signature inline. The complete static catalog is intentionally preserved in `libs/OpenAI.jl/src/generated/OpenAIClient.jl`, `libs/OpenAI.jl/src/generated/modelincludes.jl`, `libs/OpenAI.jl/src/generated/models/`, and `libs/OpenAI.jl/src/generated/apis/`; this artifact gives the public grouping, constructor/operation conventions, and exact handwritten API surface.
- Live API behavior, rate limits, authentication validity, and current server-side endpoint availability are not inferable from static source. The test suite is mostly live-API oriented and expects `OPENAI_API_KEY`; see `libs/OpenAI.jl/test/runtests.jl` and `libs/OpenAI.jl/AGENTS.md`.
