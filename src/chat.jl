function _max_tokens(model::AbstractModel, kw)
    n = something(kw, _load_pref("max_tokens"), default_max_tokens(model), Some(nothing))
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

_check_effort(::Nothing, what = "thinking_effort") = nothing
_check_effort(x::Symbol, what = "thinking_effort") = x
function _check_effort(x, what = "thinking_effort")
    x isa AbstractString && !isempty(strip(x)) && return Symbol(strip(x))
    throw(ArgumentError("$what must be a Symbol such as :high, got $(repr(x))"))
end

_check_temperature(::Nothing, what = "temperature") = nothing
function _check_temperature(x, what = "temperature")
    x isa Real && !(x isa Bool) && isfinite(x) && x >= 0 || throw(ArgumentError(
        "$what must be a non-negative number, got $(repr(x))"))
    return Float64(x)
end

# Preference `providers.<name>.parallel_tool_calls`, else the top-level one, else true.
function _parallel_tool_calls(p::AbstractProvider)
    name = provider_name(p)
    v = get(_provider_prefs(name), "parallel_tool_calls", nothing)
    key = v === nothing ? "parallel_tool_calls" : "providers.$name.parallel_tool_calls"
    v === nothing && (v = _load_pref("parallel_tool_calls", true))
    v isa Bool || throw(ArgumentError("Preference `$key` must be true or false, got $(repr(v))"))
    return v
end

_thinking_effort(kw) =
    something(_check_effort(kw), _check_effort(_load_pref("thinking_effort"), "Preference `thinking_effort`"), Some(nothing))
_temperature(kw) =
    something(_check_temperature(kw), _check_temperature(_load_pref("temperature"), "Preference `temperature`"), Some(nothing))

_show_reasoning(kw::Bool) = kw
function _show_reasoning(::Nothing)
    v = _load_pref("show_reasoning", false)
    v isa Bool || throw(ArgumentError("Preference `show_reasoning` must be true or false, got $(repr(v))"))
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
_fp_part(t::ToolSearchPart) = (t.format, t.data)
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

function _send(p::AbstractProvider, req::_Request, on::_StreamHooks)
    if req.stream
        st = _stream_state(p, req)
        _post_sse(data -> _stream_event!(st, data, on), p, _request_url(p, req), _request_body(p, req))
        return _stream_finish(st, req)
    end
    json = _post_json(p, _request_url(p, req), _request_body(p, req))
    return _parse_reply(p, req, json)
end

# The core every surface calls: one request for the given history, no session involved.
# Continues from a stored reply (previous_response_id / previous_interaction_id) when possible.
# With `on_text`, streams (if the provider can) and calls `on_text(delta)` per text chunk, and
# `on_reasoning(delta)` per chunk of reasoning summary. Unset options fall back to Preferences.
function _complete(model::Model, messages::AbstractVector{<:AbstractMessage},
                   system::Union{Nothing,AbstractString}; max_tokens = nothing, on_text = nothing,
                   on_reasoning = nothing, tools::Vector{ToolSpec} = ToolSpec[],
                   deferred::Vector{ToolSpec} = ToolSpec[],
                   thinking_effort = nothing, temperature = nothing, show_reasoning = nothing)
    p = model.provider
    n, store = _max_tokens(model, max_tokens), _store_requests()
    effort, temp, summaries = _thinking_effort(thinking_effort), _temperature(temperature),
                              _show_reasoning(show_reasoning)
    stream = on_text !== nothing && _supports_streaming(p)
    on = _StreamHooks(on_text, something(on_reasoning, Returns(nothing)))
    parallel = _parallel_tool_calls(p)
    request(ms, id) = _Request(model, ms, system, n, store, id, stream, tools, effort, temp, summaries,
                               deferred, parallel)
    full = request(messages, nothing)
    chain = _chain_point(p, messages, store)
    reply = if chain === nothing
        _send(p, full, on)
    else
        id, k = chain
        try
            _send(p, request(messages[k+1:end], id), on)
        catch e
            # The stored reply expired or was deleted: fall back to replaying everything.
            (e isa _APIError && e.status in (400, 404)) || rethrow()
            @debug "JAIL: previous id $id rejected, replaying full history" exception = e
            _send(p, full, on)
        end
    end
    if store && _supports_chaining(p) && reply.id !== nothing
        _CHAIN_STATE[reply.id] = _fingerprint([messages; reply])
    end
    return reply
end

"""
    chat!(session::Session, prompt; max_tokens = nothing, stream = false, max_tool_rounds = nothing,
          thinking_effort = nothing, temperature = nothing, show_reasoning = nothing) -> AssistantMessage
    chat!(prompt; kwargs...)

Send `prompt` (a `String` or [`UserMessage`](@ref)) as the next turn of `session`, or of the
[`active_session`](@ref) when no session is given, with the session's `system` instructions
and [`tools`](@ref). The prompt and the reply are appended to `session.messages` and the reply
is returned. If a request fails, the history is left as it was. Each message is also saved to
disk as it is added (see [`restore_session!`](@ref)).

When the model calls tools, JAIL runs them, sends a [`ToolResultMessage`](@ref)
back and asks again, until a reply calls no tools; every step is added to the history and the
last reply is returned. With the Preference `parallel_tool_calls` on (the default; a
`providers.<name>.parallel_tool_calls` entry overrides it for one provider) the model may call
several tools in one reply: each call is confirmed first, one by one, then calls of tools
registered with `concurrent = false` run one after another and the rest run at the same time
(on threads when Julia has more than one). With it `false`, OpenAI, OpenAI-compatible servers
and Anthropic are asked for at most one call per reply (Google has no such setting) and calls
run one by one, in order. Errors (unknown tool, bad arguments, a tool that throws) are sent to
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
else the provider's default (Anthropic requires one and uses the model's maximum output; others
let the model decide).

`thinking_effort` sets how much the model reasons: a `Symbol` such as `:none`, `:minimal`,
`:low`, `:medium`, `:high`, `:xhigh` or `:max`, sent as-is (OpenAI `reasoning.effort`;
Anthropic `output_config.effort` with adaptive thinking, or thinking disabled for `:none`; Google
`thinking_level`). Providers and models accept different levels and reject the others.
`temperature` (a non-negative number) sets the sampling temperature; some models reject it.
Each falls back to the session's value (see [`set_thinking_effort!`](@ref),
[`set_temperature!`](@ref)), then the Preference of the same name; when all are unset the field
is not sent and the model's default applies.

`show_reasoning = true` (default: the Preference `show_reasoning`, else `false`) asks the model
for readable reasoning summaries, which fill the reply's [`ReasoningPart`](@ref) `text`. When
streaming they are shown as they arrive, dimmed, above the reply text, and each summary is saved
to `<storage_dir>/reasoning/<session id>/<trace id>.md` (Markdown with YAML front matter), which
the finished turn links to in a `Reasoning` box. On Anthropic summaries are only requested along
with a `thinking_effort`; without one no thinking settings are sent.

`stream = true` shows the turn as the `}` REPL mode does: on a terminal the reply streams on the
alternate screen with a line per tool call and result (parallel calls that run together share
one line and show no results), then the normal screen gets the
`Tool calls` box, and the returned reply (displayed by the REPL) holds the text. Inside a
script (`include`), where nothing displays the return value, the whole turn is printed instead,
boxed as in the `}` mode: the `Tool calls` box and the reply, rendered as Markdown, in a
`Response (model; N in; M out):` box; when Julia is not interactive (`julia script.jl`), a
`Prompt:` box comes first. When `stdout` isn't a terminal, the text and tool lines are printed as
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
               stream::Bool = false, max_tool_rounds = nothing, thinking_effort = nothing,
               temperature = nothing, show_reasoning::Union{Nothing,Bool} = nothing)
    opts = (; max_tokens, max_tool_rounds, thinking_effort, temperature, show_reasoning)
    (stream && s.model !== nothing) || return _chat!(s, prompt; opts...)
    return _display_turn(stdout, s, prompt; stream = _supports_streaming(s.model.provider),
                         output = Base.source_path(nothing) !== nothing, opts...)
end

# (loaded, deferred, runnable): the tools sent in full, the tools sent for the provider's own
# search, and every tool a call may name. Without hosted search the registered tools stay out of
# the request and the model gets JAIL's tool_search / tool_load instead.
function _request_tools(s::Session, p::AbstractProvider)
    all = tools(s)
    loaded = ToolSpec[t for t in all if t.name in s.loaded_tools]
    deferred = ToolSpec[t for t in all if !(t.name in s.loaded_tools)]
    (isempty(deferred) || _tool_search_mode(p) === :hosted) && return loaded, deferred, all
    client = _client_search_specs()
    return ToolSpec[loaded; client], ToolSpec[], ToolSpec[all; client]
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

# A line for a hosted tool search step: the search the model ran, or the tools it found.
function _search_line(t::ToolSearchPart)
    kind, d = _search_kind(t), t.data
    if kind in ("server_tool_use", "tool_search_call")
        args = get(d, kind == "server_tool_use" ? "input" : "arguments", nothing)
        return string("⌕ tool search", isempty(something(args, ())) ? "" : ": " * _short(JSON.json(args), 70))
    end
    names = String[]
    if kind == "tool_search_tool_result"
        c = get(d, "content", nothing)
        c isa AbstractDict || return nothing
        get(c, "type", nothing) == "tool_search_tool_result_error" &&
            return string("⌕ tool search failed: ", get(c, "error_code", "error"))
        append!(names, string(get(r, "tool_name", "?")) for r in something(get(c, "tool_references", nothing), ()))
    elseif kind == "tool_search_output"
        for x in something(get(d, "tools", nothing), ())
            inner = get(x, "tools", nothing)
            inner === nothing ? push!(names, string(get(x, "name", "?"))) :
                append!(names, string(get(x, "name", "?"), ".", get(y, "name", "?")) for y in inner)
        end
    else
        return nothing
    end
    return string("⌕ found: ", isempty(names) ? "no tools" : join(names, ", "))
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

# Passed to `on_step` before parallel calls that weren't confirmed start running together.
struct _RunningTogether
    calls::Vector{ToolCall}
end

# Passed to `on_step` once a round of parallel calls has finished.
struct _ToolsFinished end

# One line for calls that run together: `→ label (preview) | label | …`.
function _print_tool(io::IO, x::_RunningTogether)
    item(c) = (p = _call_preview(c);
               string(_tool_label(c.name), p === nothing ? "" : string(" (", _short(first(split(p, '\n')), 40), ")")))
    printstyled(io, "→ ", join(map(item, x.calls), " | "), "\n"; color = :cyan)
end

# Passed to `on_step` after a successful turn whose reasoning summaries were saved to `paths`.
struct _ReasoningSaved
    paths::Vector{String}
end

# `on_text` / `on_reasoning` are the streaming hooks shared by `chat!(; stream = true)` and the
# `}` REPL mode; `on_step` sees each AssistantMessage as it arrives, each ToolCall before it runs,
# a `_Confirming` before a confirmation prompt, each ToolResult after, and a final
# `_ReasoningSaved`. `thinking_effort` and `temperature` fall back to the session's, then to
# Preferences (in `_complete`).
function _chat!(s::Session, prompt::Union{AbstractString,UserMessage}; max_tokens = nothing,
                on_text = nothing, on_reasoning = nothing, on_step = nothing, max_tool_rounds = nothing,
                thinking_effort = nothing, temperature = nothing, show_reasoning = nothing)
    s.model === nothing && error(
        "session \"$(s.name)\" has no model; pick one with `set_model!(session, \"provider/model\")` " *
        "or `select_model!()`")
    msg = prompt isa UserMessage ? prompt : UserMessage(prompt)
    isempty(strip(string(msg))) && throw(ArgumentError("prompt must not be empty"))
    limit, approval = _max_tool_rounds(max_tool_rounds), tool_approval()
    tool_auto_approvals()   # a malformed table fails here, before the turn starts
    opts = (; max_tokens, show_reasoning = _show_reasoning(show_reasoning),
            thinking_effort = something(_check_effort(thinking_effort), s.thinking_effort, Some(nothing)),
            temperature = something(_check_temperature(temperature), s.temperature, Some(nothing)))
    n0 = length(s.messages)
    push!(s.messages, msg)
    _sync!(s)
    reply = try
        with(_DEBUG_SESSION => s) do
            _tool_loop!(s, limit, approval; opts..., on_text, on_reasoning, on_step)
        end
    catch
        resize!(s.messages, n0)
        # A first turn that failed leaves nothing worth restoring.
        n0 == 0 ? _guard(() -> _delete_files!(s), s) : _sync!(s)
        rethrow()
    end
    if opts.show_reasoning
        saved = _record_reasoning!(s, view(s.messages, n0+2:length(s.messages)))
        saved === nothing || on_step === nothing || on_step(_ReasoningSaved(saved))
    end
    return reply
end

function _tool_loop!(s::Session, limit::Int, approval::String; on_step, opts...)
    step(x) = on_step === nothing ? nothing : on_step(x)
    rounds = 0
    while true
        # Recomputed every round: `tool_load` changes the session's loaded tools.
        loaded, deferred, specs = _request_tools(s, s.model.provider)
        reply = _complete(s.model, s.messages, s.system; opts..., tools = loaded, deferred)
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
        run = _parallel_tool_calls(s.model.provider) && length(calls) > 1 ? _run_calls_concurrently : _run_calls
        push!(s.messages, ToolResultMessage(run(s, calls, specs, approval, step)))
        _sync!(s)
    end
end

_tool_scope(f, s::Session, c::ToolCall, step) =
    with(f, _TOOL_CONTEXT => ToolContext(s, c), _PROMPT_HOOK => () -> step(_Prompting(c)))

function _run_calls(s::Session, calls, specs, approval, step)
    results = ToolResult[]
    for c in calls
        step(c)
        started = Dates.now(Dates.UTC)
        r = _tool_scope(s, c, step) do
            _run_tool(c, specs; approval, before_confirm = x -> step(_Confirming(x)))
        end
        r = _record_tool!(s, c, r, started)
        step(r)
        push!(results, r)
    end
    return results
end

# Every call is confirmed first, one by one. Then the calls of tools with `concurrent = false` run
# one after another, and the rest run together: on threads when there are several, else as tasks.
# `step` sees a call only when it is confirmed or runs alone, the other calls of the batch as one
# `_RunningTogether`, no results, and `_ToolsFinished` at the end. It is only called from this
# task; results keep the order of `calls`.
function _run_calls_concurrently(s::Session, calls, specs, approval, step)
    n = length(calls)
    results = Vector{ToolResult}(undef, n)
    ready = Vector{Any}(nothing, n)
    shown = falses(n)
    finish!(i, r, started) = (results[i] = _record_tool!(s, calls[i], r, started))
    for (i, c) in enumerate(calls)
        confirm = y -> (step(y); shown[i] = true; step(_Confirming(y)))
        x = _tool_scope(s, c, step) do
            _prepare_tool(c, specs; approval, before_confirm = confirm)
        end
        x isa ToolResult ? finish!(i, x, Dates.now(Dates.UTC)) : (ready[i] = x)
    end
    function work(i)
        started = Dates.now(Dates.UTC)
        r = _tool_scope(() -> _invoke_tool(calls[i], ready[i]...), s, calls[i], step)
        return r, started
    end
    alone = [i for i in 1:n if ready[i] !== nothing && !first(ready[i]).concurrent]
    together = [i for i in 1:n if ready[i] !== nothing && first(ready[i]).concurrent]
    for i in alone
        shown[i] || step(calls[i])
        finish!(i, work(i)...)
    end
    quiet = ToolCall[calls[i] for i in together if !shown[i]]
    isempty(quiet) || step(_RunningTogether(quiet))
    ch = Channel{Tuple{Int,Any,Dates.DateTime}}(length(together))
    threaded = Threads.nthreads() > 1
    for i in together
        f = () -> put!(ch, try
            (i, work(i)...)
        catch e
            (i, e, Dates.now(Dates.UTC))
        end)
        threaded ? Threads.@spawn(f()) : @async(f())
    end
    for _ in together
        i, r, started = take!(ch)
        r isa ToolResult || throw(r)
        finish!(i, r, started)
    end
    step(_ToolsFinished())
    return results
end

chat!(prompt::Union{AbstractString,UserMessage}; kwargs...) = chat!(active_session(), prompt; kwargs...)
