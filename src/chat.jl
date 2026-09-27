function _max_tokens(p::AbstractProvider, kw)
    n = something(kw, _load_pref("max_tokens"), default_max_tokens(typeof(p)), Some(nothing))
    n === nothing || (n isa Integer && n > 0) || throw(ArgumentError(
        "max_tokens must be a positive integer, got $(repr(n))"))
    return n
end

function _store_requests()
    v = _load_pref("store_requests", true)
    v isa Bool || throw(ArgumentError(
        "Preference `store_requests` must be true or false, got $(repr(v))"))
    return v
end

# Stored reply id => fingerprint of the history the server holds for it (up to that reply), so a
# history edited since then is replayed in full instead of chained.
const _CHAIN_STATE = Dict{String,UInt}()

# Text-only for now: extend when content parts other than TextPart are replayed.
_fingerprint(messages) = hash([(_role(m), string(m)) for m in messages])

_same_endpoint(a::AbstractProvider, b::AbstractProvider) =
    typeof(a) === typeof(b) && a.base_url == b.base_url

# (previous_id, index of that reply) when the history can continue server-side, else nothing.
function _chain_point(p::AbstractProvider, messages, store::Bool)
    (store && _supports_chaining(p)) || return nothing
    k = findlast(m -> m isa AssistantMessage, messages)
    k === nothing && return nothing
    reply = messages[k]
    (reply.id === nothing || reply.model === nothing ||
     !_same_endpoint(reply.model.provider, p)) && return nothing
    get(_CHAIN_STATE, reply.id, nothing) == _fingerprint(view(messages, 1:k)) || return nothing
    return (reply.id, k)
end

function _send(p::AbstractProvider, req::_Request)
    json = _post_json(p, _request_url(p), _request_body(p, req))
    return _parse_reply(p, req, json)
end

# The core every surface calls: one request for the given history, no session involved.
# Continues from a stored reply (previous_response_id / previous_interaction_id) when possible.
function _complete(model::Model, messages::AbstractVector{<:AbstractMessage},
                   system::Union{Nothing,AbstractString}; max_tokens = nothing)
    p = model.provider
    n, store = _max_tokens(p, max_tokens), _store_requests()
    full = _Request(model, messages, system, n, store, nothing)
    chain = _chain_point(p, messages, store)
    reply = if chain === nothing
        _send(p, full)
    else
        id, k = chain
        try
            _send(p, _Request(model, messages[k+1:end], system, n, store, id))
        catch e
            # The stored reply expired or was deleted: fall back to replaying everything.
            (e isa _APIError && e.status in (400, 404)) || rethrow()
            @debug "JAIL: previous id $id rejected, replaying full history" exception = e
            _send(p, full)
        end
    end
    if store && _supports_chaining(p) && reply.id !== nothing
        _CHAIN_STATE[reply.id] = _fingerprint([messages; reply])
    end
    return reply
end

"""
    chat!(session::Session, prompt; max_tokens = nothing) -> AssistantMessage
    chat!(prompt; max_tokens = nothing)

Send `prompt` (a `String` or [`UserMessage`](@ref)) as the next turn of `session`, or of the
[`active_session`](@ref) when no session is given, with the session's `system` instructions.
The prompt and the reply are appended to `session.messages` and the reply is returned. If the
request fails, the history is left as it was.

OpenAI and Google store replies server-side, and the next turn continues from the last one
(`previous_response_id` / `previous_interaction_id`) so only the new turns are sent. The full
history is sent instead when the history was edited since that reply, the model's provider
changed, or the stored reply has expired. Other providers always get the full history. Set the
Preference `store_requests = false` to send `store = false` and always replay the full history.

`max_tokens` caps the reply length. Without it the `max_tokens` Preference is used if set,
else the provider's default (Anthropic requires one and uses 8192; others let the model decide).

```julia
s = Session("anthropic/claude-sonnet-4-5"; system = "Be terse.")
reply = chat!(s, "Name a prime number.")
string(reply)        # the text
reply.stop_reason    # :end_turn
```
"""
function chat!(s::Session, prompt::Union{AbstractString,UserMessage}; max_tokens = nothing)
    s.model === nothing && error(
        "session \"$(s.name)\" has no model; pick one with `set_model!(session, \"provider/model\")` " *
        "or `select_model!()`")
    msg = prompt isa UserMessage ? prompt : UserMessage(prompt)
    isempty(strip(string(msg))) && throw(ArgumentError("prompt must not be empty"))
    push!(s.messages, msg)
    reply = try
        _complete(s.model, s.messages, s.system; max_tokens)
    catch
        pop!(s.messages)
        rethrow()
    end
    push!(s.messages, reply)
    return reply
end

chat!(prompt::Union{AbstractString,UserMessage}; kwargs...) = chat!(active_session(), prompt; kwargs...)
