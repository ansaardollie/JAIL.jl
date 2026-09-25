# PromptingTools.jl API Inventory

## Scope and provenance

- Package: `PromptingTools`, version `0.94.0`, Julia `1.9`, `1.10`, or `1.11`; metadata and dependencies are defined in `libs/PromptingTools.jl/Project.toml`.
- The module include order and actual top-level exports are defined in `libs/PromptingTools.jl/src/PromptingTools.jl`.
- This is a static inventory of the vendored source snapshot. Provider methods are heavily multiple-dispatched, so exact method families are grouped by schema where listing every overload would obscure the public contract.
- Visibility means exported by `PromptingTools`, exported by an explicitly imported submodule, or semi-public/internal when users are expected to access it by qualified name or extension.

## Top-level exported API

### Message and usage types

- `AIMessage` - exported `struct`; defining file `libs/PromptingTools.jl/src/messages.jl`; fields include `content`, `status`, legacy `tokens`, `elapsed`, `cost`, standardized `usage::Union{Nothing,TokenUsage}`, `extras`, finish/run/sample metadata. Returned by text-generation, classification, and vision calls.
- `TokenUsage` - exported `@kwdef struct`; defining file `libs/PromptingTools.jl/src/messages.jl`; fields are `input_tokens`, `output_tokens`, cache read/write tokens, reasoning/audio tokens, `model_id`, `cost`, `elapsed`, and provider `extras`.
- `total_tokens(u::TokenUsage)` - exported function, `libs/PromptingTools.jl/src/messages.jl`; sums input, output, cache, and reasoning token fields. `+(::TokenUsage,::TokenUsage)` and equality are Base extensions in the same file.

### AI task functions

All seven are exported from `libs/PromptingTools.jl/src/PromptingTools.jl` and have default-model forwarding methods in `libs/PromptingTools.jl/src/llm_interface.jl`.

1. `aigenerate(prompt; model=MODEL_CHAT, kwargs...)` and `aigenerate(schema::AbstractPromptSchema, prompt::ALLOWED_PROMPT_TYPE; ...)` - general text generation; normally returns `AIMessage`, or a full conversation when `return_all=true`.
2. `aiembed(doc_or_docs, args...; model=MODEL_EMBEDDING, kwargs...)` and schema-specific methods - embedding generation; normally returns `DataMessage`.
3. `aiclassify(prompt; model=MODEL_CHAT, kwargs...)` and schema-specific methods - constrained classification over `choices`.
4. `aiextract(prompt; model=MODEL_CHAT, kwargs...)` and schema-specific methods - structured extraction into a requested return type or generated data type.
5. `aitools(prompt; model=MODEL_CHAT, kwargs...)` and schema-specific methods - tool/function-calling workflows returning `AIToolRequest` and tool messages.
6. `aiscan(prompt; model=MODEL_CHAT, kwargs...)` and schema-specific methods - image/vision input with text output.
7. `aiimage(prompt; model=MODEL_IMAGE_GENERATION, kwargs...)` and schema-specific methods - image generation, typically returning `DataMessage`.

Common keyword contract across the interface is documented in `libs/PromptingTools.jl/README.md` and implemented through `libs/PromptingTools.jl/src/llm_interface.jl`: `model`, `verbose`, `return_all`, `dry_run`, `conversation`, `api_kwargs`, `http_kwargs`, and placeholder replacement keywords. Exact provider methods add provider-specific keywords.

### Templates, memory, code, and macros

- `ConversationMemory` - exported mutable struct with `conversation::Vector{AbstractMessage}`; defining file `libs/PromptingTools.jl/src/memory.jl`. Supports `push!`, `append!`, `get_last`, `last_message`, `last_output`, and callable generation.
- `aitemplates` - exported overloaded search function; `aitemplates(::Symbol; limit=10, metadata_store=TEMPLATE_METADATA)`, `aitemplates(::AbstractString; ...)`, and `aitemplates(::Regex; ...)`; defining file `libs/PromptingTools.jl/src/templates.jl`.
- `AITemplate` - exported immutable struct with `name::Symbol`; defining file `libs/PromptingTools.jl/src/templates.jl`. Used by `aigenerate`, `aiclassify`, `aiextract`, `aitools`, `aiscan`, and `aiimage` dispatch.
- `AICode` - exported mutable struct for parsed/evaluated Julia code; defining file `libs/PromptingTools.jl/src/code_eval.jl`. Constructor signatures are `AICode(code::AbstractString; auto_eval=true, safe_eval=true, skip_unsafe=false, capture_stdout=true, verbose=false, prefix="", suffix="", expression_transform=:nothing, execution_timeout=60)` and `AICode(msg::AIMessage; verbose=false, skip_invalid=false, kwargs...)`.
- `@ai_str`, `@aai_str`, `@ai!_str`, `@aai!_str` - exported string macros defined in `libs/PromptingTools.jl/src/macros.jl`; synchronous/asynchronous first-turn generation and continuation generation, with optional model flags and global `CONV_HISTORY`.

## Core message model (semi-public, imported explicitly)

Defining file: `libs/PromptingTools.jl/src/messages.jl`.

- `AbstractMessage` - abstract root for all conversation messages; semi-public.
- `AbstractChatMessage <: AbstractMessage` - text-based messages; semi-public.
- `AbstractDataMessage <: AbstractMessage` - data/tool/embedding messages; semi-public.
- `AbstractAnnotationMessage <: AbstractMessage` and `AbstractTracerMessage{T} <: AbstractMessage` - non-LLM annotations and wrapped messages; semi-public.
- `SystemMessage{T<:AbstractString}` - `@kwdef struct`; fields `content`, inferred `variables`, and `_type`.
- `UserMessage{T<:AbstractString}` - `@kwdef struct`; fields `content`, inferred `variables`, optional `name`, and `_type`.
- `UserMessageWithImages{T<:AbstractString}` - `@kwdef struct`; fields `content`, `image_url::Vector{String}`, variables, name, and `_type`.
- `DataMessage{T}` - `@kwdef struct`; structured/data response wrapper with content, status, legacy and standardized usage metadata, extras, finish/run/sample metadata.
- `ToolMessage` - mutable `@kwdef struct`; tool-call result/request record with `tool_call_id`, raw JSON, arguments, name, and content.
- `AIToolRequest` - `@kwdef struct`; AI response containing `tool_calls::Vector{ToolMessage}` plus normal response metadata.
- `AnnotationMessage{T<:AbstractString}` - `@kwdef struct`; metadata that is filtered before provider rendering.
- `MetadataMessage{T<:AbstractString}` - `@kwdef struct`; template metadata used by serialization and template indexing.
- `TracerMessage{T}` and `TracerMessageLike{T}` - mutable wrappers carrying object/message, sender/recipient, parent/thread IDs, timestamps, model, run ID, and metadata.

Important accessor and predicate methods in `messages.jl` include `tool_calls`, `last_message`, `last_output`, `unwrap`, `meta`, `align_tracer!`, `attach_images_to_user_message`, `isusermessage`, `isusermessagewithimages`, `issystemmessage`, `isdatamessage`, `isaimessage`, `istoolmessage`, `isaitoolrequest`, `isabstractannotationmessage`, and `istracermessage`. These are semi-public because they are not exported by the parent module.

## Prompt schemas and provider dispatch

Defining file: `libs/PromptingTools.jl/src/llm_interface.jl`; provider implementations are in `src/llm_openai_schema_defs.jl`, `src/llm_openai_chat.jl`, `src/llm_openai_responses.jl`, `src/llm_anthropic.jl`, `src/llm_google.jl`, `src/llm_ollama.jl`, `src/llm_ollama_managed.jl`, `src/llm_sharegpt.jl`, and `src/llm_tracer.jl`.

- `AbstractPromptSchema` - dispatch root; semi-public.
- `NoSchema` - first-pass message replacement schema.
- `AbstractOpenAISchema` and concrete schemas `OpenAISchema`, `CustomOpenAISchema`, `LocalServerOpenAISchema`, `MistralOpenAISchema`, `DatabricksOpenAISchema`, `AzureOpenAISchema`, `FireworksOpenAISchema`, `TogetherOpenAISchema`, `GroqOpenAISchema`, `DeepSeekOpenAISchema`, `OpenRouterOpenAISchema`, `CerebrasOpenAISchema`, `SambaNovaOpenAISchema`, `XAIOpenAISchema`, `GoogleOpenAISchema`, `MiniMaxOpenAISchema`, and `MoonshotOpenAISchema`. These select OpenAI-compatible rendering and transport; concrete definitions are in `llm_interface.jl` and endpoint/provider methods in `llm_openai_schema_defs.jl`.
- `AbstractOpenAIResponseSchema`, `OpenAIResponseSchema` - `/responses` endpoint schema; `llm_interface.jl` and `llm_openai_responses.jl`.
- `AbstractOllamaSchema`, `OllamaSchema`; `AbstractOllamaManagedSchema`, `OllamaManagedSchema`; `AbstractChatMLSchema`, `ChatMLSchema` - local/model-specific rendering families in `llm_interface.jl`, `llm_ollama.jl`, `llm_ollama_managed.jl`, and `llm_shared.jl`.
- `AbstractGoogleSchema`, `GoogleSchema`; `AbstractAnthropicSchema`, `AnthropicSchema`; `AbstractShareGPTSchema`, `ShareGPTSchema` - native Google, Anthropic, and ShareGPT rendering families in `llm_interface.jl` and their provider files.
- `AbstractTracerSchema`, `TracerSchema`, `SaverSchema` - middleware schemas that wrap another schema for metadata tracing and persistence; defining and operational methods are in `llm_interface.jl` and `llm_tracer.jl`.
- `TestEchoOpenAISchema`, `TestEchoOpenAIResponseSchema`, `TestEchoOllamaSchema`, `TestEchoOllamaManagedSchema`, `TestEchoGoogleSchema`, and `TestEchoAnthropicSchema` - mutable test schemas that return configured fake responses; semi-public test fixtures defined in `llm_interface.jl`.

Core dispatch signatures include `render(schema, messages; kwargs...)`, `render(schema, tools; kwargs...)`, `role4render(schema, message)`, `response_to_message(schema, MSG, choice, response; kwargs...)`, `extract_usage(schema, response; model_id="", elapsed=0.0)`, and `finalize_outputs(prompt, rendered, message; return_all=false, dry_run=false, conversation=..., no_system_message=false, kwargs...)`. They are extension points rather than stable standalone functions.

## Tool extraction and structured output

Defining file: `libs/PromptingTools.jl/src/extraction.jl`.

- `AbstractTool` - abstract tool contract; `Tool` is a concrete `@kwdef struct` with `name`, `parameters`, `description`, `strict`, and `callable`; `ToolRef` is a symbolic `@kwdef struct` with `ref`, `callable`, and string-keyed `extras`.
- `AbstractToolError`, `ToolNotFoundError`, `ToolExecutionError`, and `ToolGenericError` - error hierarchy for tool discovery/execution.
- Semi-public functions include `to_json_schema`, `to_json_type`, `generate_struct`, `parse_tool`, `execute_tool`, `tool_calls`, `tool_call_signature`, `get_method`, `get_function`, `get_arg_names`, `get_arg_types`, `extract_docstring`, `is_concrete_type`, `is_not_union_type`, `is_required_field`, `remove_null_types`, and `isabstracttool`.
- `aiextract` uses this machinery to encode Julia structs/functions as schemas and deserialize tool or JSON responses. The code explicitly rejects unsupported typed dictionaries and unsupported union forms; see `libs/PromptingTools.jl/src/extraction.jl`.

## Model registry and preferences

Defining file: `libs/PromptingTools.jl/src/user_preferences.jl`.

- `ModelSpec` - mutable `@kwdef struct` with `name`, `schema`, prompt/generation token costs, and description.
- `ModelRegistry` - registry abstraction backed by model specs and aliases; it provides `getindex`, `setindex!`, `haskey`, `get`, `delete!`, `show`, and `model_docs` methods.
- `MODEL_REGISTRY`, `MODEL_ALIASES`, `MODEL_CHAT`, `MODEL_EMBEDDING`, `MODEL_IMAGE_GENERATION`, `PROMPT_SCHEMA`, `MAX_HISTORY_LENGTH`, `LOCAL_SERVER`, `LOG_DIR`, and provider API-key globals - runtime configuration values initialized from Preferences.jl and environment variables.
- `register_model!(registry=MODEL_REGISTRY; name, schema=nothing, cost_of_token_prompt=0.0, cost_of_token_generation=0.0, description="")` and `register_model!(spec::ModelSpec; registry=MODEL_REGISTRY)` - add or replace model specs.
- `set_preferences!(pairs::Pair{String,<:Any}...)` and `get_preferences(key::String)` - persist/read allowed preference keys. `load_api_keys!()` reloads provider keys; these functions are semi-public and not top-level exports.
- Cost helpers in `utils_usage.jl` include `call_cost`, `call_cost_with_cache`, and `CACHE_DISCOUNTS`; they calculate standardized usage cost from registry data.

## Serialization and streaming

- `save_template(io_or_file, messages; content="Template Metadata", description="", version="1", source="")`, `load_template(io_or_file)`, `save_conversation(io_or_file, messages)`, `load_conversation(io_or_file)`, and `save_conversations(schema, filename, conversations)` are semi-public JSON/JSONL persistence functions in `libs/PromptingTools.jl/src/serialization.jl`.
- `configure_callback!(callback::AbstractStreamCallback, schema::AbstractPromptSchema; api_kwargs...)` and `configure_callback!(output_stream::Union{IO,Channel}, schema::AbstractPromptSchema)` are semi-public streaming setup methods in `libs/PromptingTools.jl/src/streaming.jl`. They select `OpenAIStream`, `OpenAIResponsesStream`, `AnthropicStream`, or `OllamaStream` and add stream request options where supported.
- Actual stream callback types and `streamed_request!` are imported from `StreamCallbacks`, not implemented by PromptingTools; see imports in `src/PromptingTools.jl`.

## Experimental submodules

`PromptingTools.Experimental` is not included in the parent export surface; explicitly load it with `using PromptingTools.Experimental`. It exports `APITools` and `AgentTools`, as defined in `libs/PromptingTools.jl/src/Experimental/Experimental.jl`.

- `Experimental.AgentTools` exports/re-exports `AICode`, `last_output`, `last_message`, `print_tree`, `PreOrderDFS`, `PostOrderDFS`, `print_samples`, `find_node`, `aicodefixer_feedback`, `error_feedback`, `score_feedback`, `AICall`, `AIGenerate`, `AIExtract`, `AIEmbed`, `AIClassify`, `AIScan`, `RetryConfig`, `AICodeFixer`, `run!`, and `airetry!`; definitions are in `src/Experimental/AgentTools/`.
- `AICall{F}` stores a lazy AI function, optional schema, conversation, kwargs, sample tree, retry configuration, success, and error. Its central signatures are `AICall(func::F, args...; kwargs...)`, `run!(aicall::AICallBlock; verbose=1, catch_errors=nothing, return_all=true, kwargs...)`, and callable forms with `String` or `UserMessage`.
- `AIGenerate`, `AIExtract`, `AIEmbed`, `AIClassify`, and `AIScan` are lazy constructors that wrap the corresponding top-level `ai*` function. `RetryConfig` stores retry/sample/scoring controls. `AICodeFixer` and `airetry!` implement experimental self-fixing workflows.
- `Experimental.APITools` exports the module's external API helpers, including Tavily search support; definitions are in `src/Experimental/APITools/`. This subsystem is experimental and API-key dependent.

## Not covered

- I did not reproduce every provider overload or every generated/internal helper method. The authoritative method bodies are `libs/PromptingTools.jl/src/llm_*.jl`, `src/extraction.jl`, and `src/Experimental/`; this artifact records the public shape and extension points.
- I did not enumerate every model alias or cost entry. The live registry and alias map are defined in `libs/PromptingTools.jl/src/user_preferences.jl`.
- Live API responses, pricing, provider availability, and optional extension behavior cannot be established from static source. Tests and provider credentials are required; package test commands are documented in `libs/PromptingTools.jl/CLAUDE.md`.
