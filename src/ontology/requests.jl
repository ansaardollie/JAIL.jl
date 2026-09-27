# Everything a provider needs to build one request, already resolved from kwargs and Preferences.
# With `previous_id` set, `messages` holds only the turns after that stored reply.
struct _Request
    model::Model
    messages::Vector{AbstractMessage}
    system::Union{Nothing,String}
    max_tokens::Union{Nothing,Int}
    store::Bool
    previous_id::Union{Nothing,String}
end

# Request interface: each provider implements these.
#   _request_url(p)                  -> URL of the multi-turn endpoint
#   _request_body(p, req::_Request)  -> Dict serialized as the JSON body
#   _parse_reply(p, req, json)       -> AssistantMessage
function _request_url end
function _request_body end
function _parse_reply end

# Reference data. `nothing` means the field is left out of the request.
default_max_tokens(::Type{<:AbstractProvider}) = nothing
# Whether the wire format has a `store` field that JAIL should send.
_has_store_field(::Type{<:AbstractProvider}) = false
# Whether a stored reply's id can continue the conversation server-side.
_supports_chaining(::Type{<:AbstractProvider}) = false

_has_store_field(p::AbstractProvider) = _has_store_field(typeof(p))
_supports_chaining(p::AbstractProvider) = _supports_chaining(typeof(p))

# Messages with no text (e.g. a reply that only hit max_tokens) are skipped when replaying.
_replayable(messages) = (m for m in messages if !isempty(string(m)))

_usage(::Nothing, _, _) = nothing
_usage(u, input_key, output_key) =
    Usage(something(get(u, input_key, 0), 0), something(get(u, output_key, 0), 0))
