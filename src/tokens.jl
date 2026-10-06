"""
    TokenCount

The input tokens a session's context takes up for one `model`, as counted by the model's
provider (see [`count_tokens`](@ref)): `total` and its parts `system` (the system
instructions), `tools` (the tool definitions) and `messages` (the history, plus the prompt
when one was given). `total == system + tools + messages`.

The parts come from separate counts with a part left out each time, so they are approximate:
the tokens a provider adds to frame a request land in `messages` (or in `system` when there
are no messages), and Anthropic's count is itself an estimate.
"""
struct TokenCount
    model::AbstractModel
    total::Int
    system::Int
    tools::Int
    messages::Int
end

Base.show(io::IO, c::TokenCount) = print(io, "TokenCount(", c.model, ": ", c.total, " total, ", c.system,
                                         " system, ", c.tools, " tools, ", c.messages, " messages)")

function Base.show(io::IO, ::MIME"text/plain", c::TokenCount)
    w = maximum(n -> length(string(n)), (c.total, c.system, c.tools, c.messages))
    println(io, "Input tokens for ", c.model, ":")
    for (label, n) in (("system", c.system), ("tools", c.tools), ("messages", c.messages))
        println(io, "  ", rpad(label * ":", 10), lpad(n, w))
    end
    print(io, "  ", rpad("total:", 10), lpad(c.total, w))
end

"""
    count_tokens(session::Session, prompt = nothing; model = nothing) -> TokenCount
    count_tokens(prompt = nothing; model = nothing)

Count the input tokens of `session`'s context (or the [`active_session`](@ref)'s): its system
instructions, the definitions of its [`tools`](@ref), and its message history, as the next
[`chat!`](@ref) would send them in full. With a `prompt` (a `String` or
[`UserMessage`](@ref)) it is counted as the next turn; the session is not changed.

The count comes from the provider's own counting endpoint, so it costs no output tokens but
does make up to three requests (one per part present; see [`TokenCount`](@ref)). `model` (a
[`Model`](@ref) or `"provider/model"` string) counts the context for another model instead of
the session's; tokenizers differ, so the same history counts differently per model.

| Provider | Endpoint |
|----------|----------|
| [`OpenAI`](@ref), [`OpenAICompatible`](@ref) | `POST /responses/input_tokens` |
| [`Anthropic`](@ref) | `POST /v1/messages/count_tokens` |
| [`Google`](@ref) | `POST /v1beta/models/{model}:countTokens` |
| [`GoogleEnterprise`](@ref) | `POST .../publishers/google/models/{model}:countTokens` |

Many OpenAI-compatible servers lack `/responses/input_tokens`; for them `count_tokens` throws.
Google's endpoint takes the `generateContent` format, so Gemini reasoning from the Interactions
API is not counted.

```julia
s = Session("anthropic/claude-sonnet-4-5"; system = "Be terse.")
count_tokens(s)                                  # system, tools; no messages yet
count_tokens(s, "Summarise the README")          # as if this were the next prompt
count_tokens(s; model = "openai/gpt-5").total    # the same context for another model
```
"""
function count_tokens(s::Session, prompt::Union{Nothing,AbstractString,UserMessage} = nothing;
                      model::Union{Nothing,AbstractString,AbstractModel} = nothing)
    m = model isa AbstractString ? Model(model) : something(model, Some(s.model))
    m === nothing && error(
        "session \"$(s.name)\" has no model; pass `model = \"provider/model\"` or pick one with " *
        "`set_model!(session, \"provider/model\")`")
    messages = copy(s.messages)
    if prompt !== nothing
        msg = prompt isa UserMessage ? prompt : UserMessage(prompt)
        isempty(strip(string(msg))) && throw(ArgumentError("prompt must not be empty"))
        push!(messages, msg)
    end
    loaded, deferred, _ = _request_tools(s, m.provider)
    return with(() -> _count_tokens(m, messages, s.system, loaded, deferred), _DEBUG_SESSION => s)
end

count_tokens(prompt::Union{Nothing,AbstractString,UserMessage} = nothing; kwargs...) =
    count_tokens(active_session(), prompt; kwargs...)

# Cumulative counts: messages, + system, + tools. Endpoints that need a message get a placeholder
# when there are none, and its count is subtracted.
function _count_tokens(model::AbstractModel, messages, system, specs::Vector{ToolSpec},
                       deferred::Vector{ToolSpec} = ToolSpec[])
    p = model.provider
    system = system === nothing || isempty(system) ? nothing : system
    ms = collect(AbstractMessage, _replayable(messages))
    no_tools = isempty(specs) && isempty(deferred)
    isempty(ms) && system === nothing && no_tools && return TokenCount(model, 0, 0, 0, 0)
    placeholder = isempty(ms) && _count_needs_messages(typeof(p))
    placeholder && push!(ms, UserMessage("."))
    count(sys, ts, ds = ToolSpec[]) = _count_request(p, _Request(model, ms, sys, nothing, false, nothing,
                                                                 false, ts, nothing, nothing, false, ds))
    n_messages = isempty(ms) ? 0 : count(nothing, ToolSpec[])
    n_system = system === nothing ? n_messages : count(system, ToolSpec[])
    n_total = no_tools ? n_system : count(system, specs, deferred)
    base = placeholder ? n_messages : 0
    return TokenCount(model, n_total - base, n_system - n_messages, n_total - n_system, n_messages - base)
end

function _count_request(p::AbstractProvider, req::_Request)
    url = _count_url(p, req.model)
    json = try
        _post_json(p, url, _count_body(p, req))
    catch e
        throw(_count_error(p, e, url))
    end
    return _parse_count(p, json)
end

_count_error(p::AbstractProvider, e, url) = e
_count_error(p::OpenAICompatible, e::_APIError, url) = e.status in (404, 405, 501) ?
    _APIError(e.status, string(e.msg, "\n\"", p.name, "\" has no token counting endpoint (POST ", url,
                               "); count_tokens needs a server that implements OpenAI's /responses/input_tokens")) : e
