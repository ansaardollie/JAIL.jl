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
    tools::Vector{ToolSpec}
end

# Request interface: each provider implements these.
#   _request_url(p)                  -> URL of the multi-turn endpoint
#   _request_body(p, req::_Request)  -> Dict serialized as the JSON body (`stream: true` if req.stream,
#                                       `tools` when req.tools is non-empty)
#   _parse_reply(p, req, json)       -> AssistantMessage (ToolCall parts => stop_reason :tool_use)
# Streaming (SSE), for providers with _supports_streaming:
#   _stream_state(p, req)                        -> mutable accumulator
#   _stream_event!(state, data::String, on_text) -> handle one event's `data`, on_text(delta) for text
#   _stream_finish(state, req)                   -> AssistantMessage (throws on a stream error)
function _request_url end
function _request_body end
function _parse_reply end
function _stream_state end
function _stream_event! end
function _stream_finish end

# Reference data. `nothing` means the field is left out of the request.
default_max_tokens(::Type{<:AbstractProvider}) = nothing
# Whether the wire format has a `store` field that JAIL should send.
_has_store_field(::Type{<:AbstractProvider}) = false
# Whether a stored reply's id can continue the conversation server-side.
_supports_chaining(::Type{<:AbstractProvider}) = false
# Whether replies can be streamed as server-sent events.
_supports_streaming(::Type{<:AbstractProvider}) = false

_has_store_field(p::AbstractProvider) = _has_store_field(typeof(p))
_supports_chaining(p::AbstractProvider) = _supports_chaining(typeof(p))
_supports_streaming(p::AbstractProvider) = _supports_streaming(typeof(p))

# Messages with no text and no tool calls (e.g. a reply that only hit max_tokens) are skipped.
_replayable(messages) = (m for m in messages if m isa ToolResultMessage || !isempty(string(m)) ||
                                               !isempty(_tool_calls(m)))

# Replies that call tools stop for :tool_use whatever the provider reported.
_stop_reason(parts, reason) = any(p -> p isa ToolCall, parts) ? :tool_use : reason

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
