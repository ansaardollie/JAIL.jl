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

# Everything that is replayed: text, tool calls and tool results.
_fp_part(p::TextPart) = p.text
_fp_part(c::ToolCall) = (c.id, c.name, c.arguments)
_fp_part(r::ToolResult) = (r.call_id, r.content, r.is_error)
_fp_part(r::ReasoningPart) = (r.format, r.text, r.data)
_fp_part(p::AbstractContentPart) = p
_fingerprint(messages) = hash([(_role(m), map(_fp_part, m.content)) for m in messages])

_same_endpoint(a::AbstractProvider, b::AbstractProvider) = typeof(a) === typeof(b) && a == b

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

function _send(p::AbstractProvider, req::_Request, on_text)
    if req.stream
        st = _stream_state(p, req)
        _post_sse(data -> _stream_event!(st, data, on_text), p, _request_url(p, req), _request_body(p, req))
        return _stream_finish(st, req)
    end
    json = _post_json(p, _request_url(p, req), _request_body(p, req))
    return _parse_reply(p, req, json)
end

# The core every surface calls: one request for the given history, no session involved.
# Continues from a stored reply (previous_response_id / previous_interaction_id) when possible.
# With `on_text`, streams (if the provider can) and calls `on_text(delta)` per text chunk.
function _complete(model::Model, messages::AbstractVector{<:AbstractMessage},
                   system::Union{Nothing,AbstractString}; max_tokens = nothing, on_text = nothing,
                   tools::Vector{ToolSpec} = ToolSpec[])
    p = model.provider
    n, store = _max_tokens(p, max_tokens), _store_requests()
    stream = on_text !== nothing && _supports_streaming(p)
    full = _Request(model, messages, system, n, store, nothing, stream, tools)
    chain = _chain_point(p, messages, store)
    reply = if chain === nothing
        _send(p, full, on_text)
    else
        id, k = chain
        try
            _send(p, _Request(model, messages[k+1:end], system, n, store, id, stream, tools), on_text)
        catch e
            # The stored reply expired or was deleted: fall back to replaying everything.
            (e isa _APIError && e.status in (400, 404)) || rethrow()
            @debug "JAIL: previous id $id rejected, replaying full history" exception = e
            _send(p, full, on_text)
        end
    end
    if store && _supports_chaining(p) && reply.id !== nothing
        _CHAIN_STATE[reply.id] = _fingerprint([messages; reply])
    end
    return reply
end

"""
    chat!(session::Session, prompt; max_tokens = nothing, stream = false, max_tool_rounds = nothing) -> AssistantMessage
    chat!(prompt; max_tokens = nothing, stream = false, max_tool_rounds = nothing)

Send `prompt` (a `String` or [`UserMessage`](@ref)) as the next turn of `session`, or of the
[`active_session`](@ref) when no session is given, with the session's `system` instructions
and [`tools`](@ref). The prompt and the reply are appended to `session.messages` and the reply
is returned. If a request fails, the history is left as it was. Each message is also saved to
disk as it is added (see [`restore_session!`](@ref)).

When the model calls tools, JAIL runs them (in order), sends a [`ToolResultMessage`](@ref)
back and asks again, until a reply calls no tools; every step is added to the history and the
last reply is returned. Errors (unknown tool, bad arguments, a tool that throws) are sent to
the model as error results rather than thrown. After `max_tool_rounds` rounds (default: the
Preference `max_tool_rounds`, else 10) further calls are answered with "not run" results and
the last reply (`stop_reason = :tool_use`) is returned. Whether a call is confirmed on the
terminal first depends on the tool's `security` level, the Preference `tool_approval` and the
tool's entry in [`tool_auto_approvals`](@ref) (see [`register_tool!`](@ref)); the built-in
`ask_user` is never confirmed. A tool can read the calling session and call with
[`tool_context`](@ref).

OpenAI and Google store replies server-side, and the next turn continues from the last one
(`previous_response_id` / `previous_interaction_id`) so only the new turns are sent; so does
[`GoogleEnterprise`](@ref) unless it uses `api = :generate_content`. The full
history is sent instead when the history was edited since that reply, the model's provider
changed, the session was restored in a new Julia process, or the stored reply has expired. Other providers always get the full history. Set the
Preference `store_requests = false` to send `store = false` and always replay the full history.
A full history includes the replies' [`ReasoningPart`](@ref)s, but only for the provider and wire
format that produced them.

`max_tokens` caps the reply length. Without it the `max_tokens` Preference is used if set,
else the provider's default (Anthropic requires one and uses 8192; others let the model decide).

`stream = true` shows the turn as the `}` REPL mode does: on a terminal the reply streams on the
alternate screen with a line per tool call and result, then the normal screen gets the
`Tool calls` block, and the returned reply (displayed by the REPL) holds the text. Inside a
script (`include`), where nothing displays the return value, the reply is also printed,
rendered as Markdown under `Response (model; N in; M out):`; when Julia is not interactive
(`julia script.jl`), the prompt is printed first under `Prompt:`. When `stdout` isn't a terminal, the text and tool lines are printed as
they arrive. All built-in providers can stream; the full reply is always returned. The `}` REPL
mode streams when the Preference `stream = true` is set.

```julia
s = Session("anthropic/claude-sonnet-4-5"; system = "Be terse.")
reply = chat!(s, "Name a prime number.")
string(reply)        # the text
reply.stop_reason    # :end_turn
chat!(s, "Another?"; stream = true)   # streams, then shows the reply once
```
"""
function chat!(s::Session, prompt::Union{AbstractString,UserMessage}; max_tokens = nothing,
               stream::Bool = false, max_tool_rounds = nothing)
    (stream && s.model !== nothing) || return _chat!(s, prompt; max_tokens, max_tool_rounds)
    return _display_turn(stdout, s, prompt; stream = _supports_streaming(s.model.provider),
                         output = Base.source_path(nothing) !== nothing, max_tokens, max_tool_rounds)
end

function _max_tool_rounds(kw)
    n = something(kw, _load_pref("max_tool_rounds", 10))
    n isa Integer && n >= 0 || throw(ArgumentError(
        "max_tool_rounds must be a non-negative integer, got $(repr(n))"))
    return Int(n)
end

function _print_tool(io::IO, c::ToolCall)
    printstyled(io, "→ ", _tool_label(c.name), "\n"; color = :cyan)
    p = _call_preview(c)
    p === nothing || _print_preview(io, p)
end
function _print_tool(io::IO, r::ToolResult)
    line = _short(first(split(r.content, '\n'; limit = 2)), 70)
    printstyled(io, "← ", _tool_label(r.name), r.is_error ? " error: " : ": ", line, "\n";
                color = r.is_error ? :red : :light_black)
end

# Passed to `on_step` just before the user is asked to confirm `call`; returning `true` says the
# call's preview is already on screen.
struct _Confirming
    call::ToolCall
end

# Passed to `on_step` when a running tool is about to read the terminal (e.g. `ask_user`).
struct _Prompting
    call::ToolCall
end

# `on_text` is the streaming hook shared by `chat!(; stream = true)` and the `}` REPL mode;
# `on_step` sees each AssistantMessage as it arrives, each ToolCall before it runs, a
# `_Confirming` before a confirmation prompt, and each ToolResult after.
function _chat!(s::Session, prompt::Union{AbstractString,UserMessage}; max_tokens = nothing,
                on_text = nothing, on_step = nothing, max_tool_rounds = nothing)
    s.model === nothing && error(
        "session \"$(s.name)\" has no model; pick one with `set_model!(session, \"provider/model\")` " *
        "or `select_model!()`")
    msg = prompt isa UserMessage ? prompt : UserMessage(prompt)
    isempty(strip(string(msg))) && throw(ArgumentError("prompt must not be empty"))
    limit, approval = _max_tool_rounds(max_tool_rounds), tool_approval()
    tool_auto_approvals()   # a malformed table fails here, before the turn starts
    n0 = length(s.messages)
    push!(s.messages, msg)
    _sync!(s)
    try
        return _tool_loop!(s, limit, approval; max_tokens, on_text, on_step)
    catch
        resize!(s.messages, n0)
        # A first turn that failed leaves nothing worth restoring.
        n0 == 0 ? _guard(() -> _delete_files!(s), s) : _sync!(s)
        rethrow()
    end
end

function _tool_loop!(s::Session, limit::Int, approval::String; max_tokens, on_text, on_step)
    step(x) = on_step === nothing ? nothing : on_step(x)
    rounds = 0
    while true
        specs = tools(s)
        reply = _complete(s.model, s.messages, s.system; max_tokens, on_text, tools = specs)
        push!(s.messages, reply)
        _sync!(s)
        step(reply)
        calls = _tool_calls(reply)
        isempty(calls) && return reply
        if rounds >= limit
            now = Dates.now(Dates.UTC)
            push!(s.messages, ToolResultMessage([_record_tool!(s, c, ToolResult(c.id, c.name,
                "Not run: the limit of $limit tool rounds for this turn was reached."; is_error = true), now)
                for c in calls]))
            _sync!(s)
            return reply
        end
        rounds += 1
        results = ToolResult[]
        for c in calls
            step(c)
            started = Dates.now(Dates.UTC)
            r = with(_TOOL_CONTEXT => ToolContext(s, c), _PROMPT_HOOK => () -> step(_Prompting(c))) do
                _run_tool(c, specs; approval, before_confirm = x -> step(_Confirming(x)))
            end
            r = _record_tool!(s, c, r, started)
            step(r)
            push!(results, r)
        end
        push!(s.messages, ToolResultMessage(results))
        _sync!(s)
    end
end

chat!(prompt::Union{AbstractString,UserMessage}; kwargs...) = chat!(active_session(), prompt; kwargs...)
