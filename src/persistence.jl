# Sessions on disk: <storage_dir>/sessions/<id>.json (session JSON) and
# <storage_dir>/messages/<id>.jsonl (one message per line, appended as the history grows).

const _FORMAT_VERSION = 1

_uuid7_time(id::UUID) = DateTime(1970) + Dates.Millisecond(Int64(id.value >> 80))

_local_time(t::DateTime) =
    Dates.format(t + round(Dates.now() - Dates.now(Dates.UTC), Dates.Minute), "yyyy-mm-dd HH:MM")

_iso(t::DateTime) = Dates.format(t, "yyyy-mm-ddTHH:MM:SS.sss") * "Z"

function _persist_pref()
    v = _load_pref("persist_sessions", true)
    v isa Bool || throw(ArgumentError("Preference `persist_sessions` must be true or false, got $(repr(v))"))
    return v
end

function _storage_dir()
    v = _load_pref("storage_dir", ".jail")
    v isa AbstractString && !isempty(v) || throw(ArgumentError(
        "Preference `storage_dir` must be a non-empty path, got $(repr(v))"))
    return abspath(v)
end

_session_path(dir, id) = joinpath(dir, "sessions", string(id, ".json"))
_messages_path(dir, id) = joinpath(dir, "messages", string(id, ".jsonl"))

# ---- encoding ----

_part_json(p::TextPart) = (type = "text", text = p.text)

function _part_json(c::ToolCall)
    sig = get(_THOUGHT_SIGNATURES, c.id, nothing)
    d = JSON.Object{String,Any}("type" => "tool_call", "id" => c.id, "name" => c.name, "arguments" => c.arguments)
    sig === nothing || (d["thought_signature"] = sig)
    return d
end

# Tool output that is JSON (an object, array or number) is stored as that value, but only when it
# re-serialises to the identical text, so restoring gives back the exact string the model saw.
function _result_value(text::String)
    v = try
        JSON.parse(text)
    catch
        return text
    end
    v isa AbstractString && return text
    return JSON.json(v) == text ? v : text
end

_part_json(r::ToolResult) = (type = "tool_result", call_id = r.call_id, name = r.name,
                             content = _result_value(r.content), is_error = r.is_error)

_message_json(m::Union{UserMessage,ToolResultMessage}) = (role = _role(m), content = map(_part_json, m.content))

function _message_json(m::AssistantMessage)
    d = JSON.Object{String,Any}("role" => "assistant", "content" => map(_part_json, m.content))
    m.model === nothing || (d["model"] = string(m.model))
    m.stop_reason === nothing || (d["stop_reason"] = string(m.stop_reason))
    m.usage === nothing ||
        (d["usage"] = (input_tokens = m.usage.input_tokens, output_tokens = m.usage.output_tokens))
    m.id === nothing || (d["id"] = m.id)
    return d
end

_session_json(s::Session) = (version = _FORMAT_VERSION, id = string(s.id), name = s.name,
    created = _iso(s.created), model = _model_string(s), system = s.system, tools = s.tools)

# ---- writing ----

function _write_atomic(path::AbstractString, text::AbstractString)
    mkpath(dirname(path))
    tmp = path * ".tmp"
    write(tmp, text)
    mv(tmp, path; force = true)
    return nothing
end

function _write_lines(io::IO, messages)
    for m in messages
        JSON.json(io, _message_json(m))
        write(io, '\n')
    end
end

function _write_meta!(s::Session, text::String = JSON.json(_session_json(s); pretty = true))
    st = s._store
    _write_atomic(_session_path(st.dir, s.id), text)
    st.meta = hash(text)
    return nothing
end

function _write_messages!(s::Session)
    st, n = s._store, length(s.messages)
    path = _messages_path(st.dir, s.id)
    if n < st.nsaved || !isfile(path)
        # The history shrank (cleared, or a failed turn was rolled back): rewrite it whole.
        _write_atomic(path, sprint(_write_lines, s.messages))
    elseif n > st.nsaved
        open(io -> _write_lines(io, view(s.messages, st.nsaved+1:n)), path, "a")
    end
    st.nsaved = n
    return nothing
end

# Never throws: a full disk or a bad Preference must not break a chat turn.
function _guard(f, s::Session)
    try
        _persist_pref() && f()
    catch e
        e isa InterruptException && rethrow()
        @warn "JAIL: could not save session \"$(s.name)\"" exception = e
    end
    return nothing
end

# Bring the files up to date with the session; called after every change to the history.
function _sync!(s::Session)
    _guard(s) do
        st = s._store
        if st.dir === nothing
            isempty(s.messages) && return
            st.dir = _storage_dir()
        end
        text = JSON.json(_session_json(s); pretty = true)
        hash(text) == st.meta || _write_meta!(s, text)
        _write_messages!(s)
    end
end

# Model or tools changed: only the session JSON, and only once the session is on disk.
_sync_meta!(s::Session) = s._store.dir === nothing ? nothing : _sync!(s)

function _delete_files!(s::Session)
    dir = something(s._store.dir, _storage_dir())
    rm(_session_path(dir, s.id); force = true)
    rm(_messages_path(dir, s.id); force = true)
    s._store.dir = nothing
    s._store.nsaved = 0
    s._store.meta = UInt(0)
    return nothing
end

# ---- reading ----

function _restore_model(x, what)
    x === nothing && return nothing
    try
        return Model(x)
    catch e
        e isa InterruptException && rethrow()
        @warn "JAIL: $what model \"$x\" can't be used; it is restored without one" exception = e
        return nothing
    end
end

function _restore_part(d)
    t = d["type"]
    t == "text" && return TextPart(d["text"])
    if t == "tool_call"
        sig = get(d, "thought_signature", nothing)
        sig === nothing || (_THOUGHT_SIGNATURES[d["id"]] = sig)
        return ToolCall(d["id"], d["name"], d["arguments"])
    end
    if t == "tool_result"
        c = d["content"]
        return ToolResult(d["call_id"], d["name"], c isa AbstractString ? c : JSON.json(c);
                          is_error = d["is_error"])
    end
    throw(ArgumentError("unknown content part type $(repr(t))"))
end

function _restore_message(d, models::Dict{String,Any})
    role = d["role"]
    parts = AbstractContentPart[_restore_part(p) for p in d["content"]]
    role == "user" && return UserMessage(parts)
    role == "tool" && return ToolResultMessage(convert(Vector{ToolResult}, parts))
    role == "assistant" || throw(ArgumentError("unknown message role $(repr(role))"))
    m = get(d, "model", nothing)
    model = m === nothing ? nothing : get!(() -> _restore_model(m, "a reply's"), models, m)
    u = get(d, "usage", nothing)
    r = get(d, "stop_reason", nothing)
    return AssistantMessage(parts; model, id = get(d, "id", nothing),
        stop_reason = r === nothing ? nothing : Symbol(r),
        usage = u === nothing ? nothing : Usage(u["input_tokens"], u["output_tokens"]))
end

# Messages that parse, and whether any line was unreadable (e.g. a write cut off by a crash).
function _read_messages(path::AbstractString)
    messages, bad, models = AbstractMessage[], false, Dict{String,Any}()
    isfile(path) || return messages, bad
    for (i, line) in enumerate(eachline(path))
        isempty(strip(line)) && continue
        try
            push!(messages, _restore_message(JSON.parse(line), models))
        catch e
            e isa InterruptException && rethrow()
            @warn "JAIL: skipping unreadable line $i of $path" exception = e
            bad = true
        end
    end
    return messages, bad
end

_parse_id(id::UUID) = id
function _parse_id(id::AbstractString)
    u = tryparse(UUID, id)
    u === nothing && throw(ArgumentError("not a session id: \"$id\""))
    return u
end

function _load_session(dir::AbstractString, id::UUID)
    path = _session_path(dir, id)
    isfile(path) || throw(ArgumentError("no saved session $id in $dir"))
    uuid_version(id) == 7 || throw(ArgumentError("session id $id is not a version 7 UUID"))
    meta = JSON.parse(read(path, String))
    messages, bad = _read_messages(_messages_path(dir, id))
    tools = meta["tools"]
    store = _SessionStore(dir, bad ? typemax(Int) : length(messages), UInt(0))
    s = Session(_Register(), meta["name"], _restore_model(meta["model"], "the session's"),
                meta["system"], tools === nothing ? nothing : String[t for t in tools];
                id, messages, store)
    # Record what is on disk so an unchanged session isn't rewritten; skipped lines are dropped
    # from the file on the next sync.
    store.meta = hash(read(path, String))
    bad && _sync!(s)
    return s
end

const _SavedEntry = NamedTuple{(:id, :name, :created, :first),Tuple{UUID,String,DateTime,String}}

# One entry per saved session, newest first: (id, name, created, first user message).
function _saved_sessions(dir::AbstractString = _storage_dir())
    sdir = joinpath(dir, "sessions")
    isdir(sdir) || return _SavedEntry[]
    files = sort!(filter(f -> endswith(f, ".json"), readdir(sdir)); rev = true)
    out = _SavedEntry[]
    for f in files
        id = tryparse(UUID, chop(f; tail = 5))
        (id === nothing || uuid_version(id) != 7) && continue
        name = try
            String(JSON.parse(read(joinpath(sdir, f), String))["name"])
        catch e
            e isa InterruptException && rethrow()
            continue
        end
        push!(out, (; id, name, created = _uuid7_time(id), first = _first_prompt(_messages_path(dir, id))))
    end
    return out
end

function _first_prompt(path::AbstractString)
    isfile(path) || return ""
    for line in eachline(path)
        occursin("\"user\"", line) || continue
        try
            d = JSON.parse(line)
            d["role"] == "user" &&
                return join((p["text"] for p in d["content"] if p["type"] == "text"), " ")
        catch
        end
    end
    return ""
end

function _saved_label(e, width)
    first = isempty(e.first) ? "(no messages)" : _short(e.first, 50)
    return string(rpad(e.name, width), "  ", _local_time(e.created), "  ", first)
end

"""
    restore_session!() -> Union{Session,Nothing}
    restore_session!(id::Union{UUID,AbstractString}) -> Session

Bring back a saved session and make it the active one. Without an `id`, a terminal menu lists
the saved sessions, newest first, by name, creation time and first prompt; cancelling returns
`nothing`. A session that is already loaded is just activated. The `|` REPL mode's
`session restore` opens the same menu.

Sessions are saved automatically from their first message on: the session (name, `id`,
`created`, model, system instructions, tools) to `<dir>/sessions/<id>.json`, and its messages to
`<dir>/messages/<id>.jsonl`, one line per message, appended as the conversation grows. `<dir>`
is the Preference `storage_dir` (default `".jail"`, relative to the working directory when the
session is first saved). Set the Preference `persist_sessions = false` to stop saving.

Model names are resolved through the current Preferences; one that no longer resolves leaves the
session without a model (pick one with [`set_model!`](@ref)).
"""
function restore_session!(id::Union{UUID,AbstractString})
    u = _parse_id(id)
    i = findfirst(s -> s.id == u, _SESSIONS)
    s = i === nothing ? _load_session(_storage_dir(), u) : _SESSIONS[i]
    return use_session!(s)
end

restore_session!() = _restore_from_menu(_menu_terminal())

function _restore_from_menu(term)
    dir = _storage_dir()
    saved = _saved_sessions(dir)
    if isempty(saved)
        println("No saved sessions in ", dir)
        return nothing
    end
    width = maximum(e -> length(e.name), saved)
    i = _pick(term, "Restore a session:", [_saved_label(e, width) for e in saved])
    i === nothing && return nothing
    return restore_session!(saved[i].id)
end
