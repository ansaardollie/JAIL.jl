# Everything a provider needs to build one request, already resolved from kwargs and Preferences.
# With `previous_id` set, `messages` holds only the turns after that stored reply.
struct _Request
    model::Model
    messages::Vector{AbstractMessage}
    system::Union{Nothing,String}
    max_tokens::Union{Nothing,Int}
    store::Bool
    previous_id::Union{Nothing,String}
    stream::Bool
    tools::Vector{ToolSpec}                  # loaded: sent as plain tools
    thinking_effort::Union{Nothing,Symbol}   # sent as-is; the provider rejects levels it lacks
    temperature::Union{Nothing,Float64}
    show_reasoning::Bool                     # ask for readable reasoning summaries
    # Registered but not loaded: sent with `defer_loading` plus the provider's tool search tool.
    # Only non-empty for providers whose _tool_search_mode is :hosted.
    deferred::Vector{ToolSpec}
    # false: ask for at most one tool call per reply (only sent when false, the providers' default is true)
    parallel_tool_calls::Bool
    # :auto (field not sent) or :none (tools are sent only so replayed calls are valid; none may be called)
    tool_choice::Symbol
end

# What a stream reports as it arrives: `text(delta)` for reply text, `reasoning(delta)` for
# reasoning summary text.
struct _StreamHooks
    text::Any
    reasoning::Any
end

# Request interface: each provider implements these.
#   _request_url(p)                  -> URL of the multi-turn endpoint
#   _request_body(p, req::_Request)  -> Dict serialized as the JSON body (`stream: true` if req.stream,
#                                       `tools` when req.tools is non-empty)
#   _parse_reply(p, req, json)       -> AssistantMessage (ToolCall parts => stop_reason :tool_use)
# Streaming (SSE), for providers with _supports_streaming:
#   _stream_state(p, req)                        -> mutable accumulator
#   _stream_event!(state, data::String, on::_StreamHooks) -> handle one event's `data`: on.text(delta)
#                                                for text, on.reasoning(delta) for reasoning summaries
#   _stream_finish(state, req)                   -> AssistantMessage (throws on a stream error)
function _request_url end
# For wire formats whose URL depends on the request (model id, streaming); most ignore it.
_request_url(p::AbstractProvider, ::_Request) = _request_url(p)
function _request_body end
function _parse_reply end
function _stream_state end
function _stream_event! end
function _stream_finish end

# Reference data. `nothing` means the field is left out of the request.
default_max_tokens(::Type{<:AbstractProvider}) = nothing
default_max_tokens(m::AbstractModel) = default_max_tokens(typeof(m.provider))
# Whether the wire format has a `store` field that JAIL should send.
_has_store_field(::Type{<:AbstractProvider}) = false
# Whether a stored reply's id can continue the conversation server-side.
_supports_chaining(::Type{<:AbstractProvider}) = false
# Whether replies can be streamed as server-sent events.
_supports_streaming(::Type{<:AbstractProvider}) = false
# Whether the provider can search deferred tools itself (`defer_loading` + a tool search tool).
_supports_hosted_tool_search(::Type{<:AbstractProvider}) = false

# Token counting interface (src/tokens.jl), each provider implements:
#   _count_url(p, model)           -> URL of the provider's input-token counting endpoint
#   _count_body(p, req::_Request)  -> Dict body counting req's system, tools and messages
#   _parse_count(p, json)          -> Int input tokens
function _count_url end
function _count_body end
function _parse_count end
# Whether the counting endpoint requires at least one message.
_count_needs_messages(::Type{<:AbstractProvider}) = false

_has_store_field(p::AbstractProvider) = _has_store_field(typeof(p))
_supports_chaining(p::AbstractProvider) = _supports_chaining(typeof(p))
_supports_streaming(p::AbstractProvider) = _supports_streaming(typeof(p))

# :hosted (the provider searches the deferred tools) or :client (JAIL's tool_search / tool_load
# tools). Providers with hosted search read the Preference `providers.<name>.tool_search`.
function _tool_search_mode(p::AbstractProvider)
    _supports_hosted_tool_search(typeof(p)) || return :client
    name = provider_name(p)
    v = get(_provider_prefs(name), "tool_search", "hosted")
    v in ("hosted", "client") || throw(ArgumentError(
        "Preference `providers.$name.tool_search` must be \"hosted\" or \"client\", got $(repr(v))"))
    return Symbol(v)
end

# Messages with no text and no tool calls (e.g. a reply that only hit max_tokens) are skipped.
_replayable(messages) = (m for m in messages if m isa ToolResultMessage || !isempty(string(m)) ||
                                               !isempty(_tool_calls(m)))

# Replies that call tools stop for :tool_use whatever the provider reported.
_stop_reason(parts, reason) = any(p -> p isa ToolCall, parts) ? :tool_use : reason

# Readable text of a reasoning summary given as `{type, text}` items (Google, OpenAI).
_summary_text(items) = join((i["text"] for i in something(items, ()) if get(i, "text", nothing) isa AbstractString), "\n\n")

# Tool arguments arrive as a JSON string (OpenAI) or object (Anthropic, Google); "" means none.
_arguments(x::AbstractDict) = x
_arguments(::Nothing) = Dict{String,Any}()
function _arguments(s::AbstractString)
    isempty(strip(s)) && return Dict{String,Any}()
    v = try
        JSON.parse(s)
    catch
        nothing
    end
    # Kept so the loop can report the bad arguments back to the model.
    return v isa AbstractDict ? v : Dict{String,Any}(_BAD_ARGUMENTS => s)
end
const _BAD_ARGUMENTS = "__invalid_json__"

_usage(::Nothing, _, _) = nothing
_usage(u, input_key, output_key) =
    Usage(something(get(u, input_key, 0), 0), something(get(u, output_key, 0), 0))
