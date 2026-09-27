function _max_tokens(p::AbstractProvider, kw)
    n = something(kw, _load_pref("max_tokens"), default_max_tokens(typeof(p)), Some(nothing))
    n === nothing || (n isa Integer && n > 0) || throw(ArgumentError(
        "max_tokens must be a positive integer, got $(repr(n))"))
    return n
end

function _store_requests()
    v = _load_pref("store_requests", false)
    v isa Bool || throw(ArgumentError(
        "Preference `store_requests` must be true or false, got $(repr(v))"))
    return v
end

# The core every surface calls: one request with the full history, no session involved.
function _complete(model::Model, messages::AbstractVector{<:AbstractMessage},
                   system::Union{Nothing,AbstractString}; max_tokens = nothing)
    p = model.provider
    req = _Request(model, messages, system, _max_tokens(p, max_tokens), _store_requests())
    json = _post_json(p, _request_url(p), _request_body(p, req))
    return _parse_reply(p, req, json)
end

"""
    chat!(session::Session, prompt; max_tokens = nothing) -> AssistantMessage
    chat!(prompt; max_tokens = nothing)

Send `prompt` (a `String` or [`UserMessage`](@ref)) as the next turn of `session`, or of the
[`active_session`](@ref) when no session is given. The whole history is sent along with the
session's `system` instructions; the prompt and the reply are appended to `session.messages`
and the reply is returned. If the request fails, the history is left as it was.

`max_tokens` caps the reply length. Without it the `max_tokens` Preference is used if set,
else the provider's default (Anthropic requires one and uses 8192; others let the model decide).

Set the Preference `store_requests = true` to let OpenAI and Google keep requests server-side;
JAIL sends `store = false` by default since it keeps the history itself.

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
