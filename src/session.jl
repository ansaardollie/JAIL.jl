struct _Register end

# On-disk state: `dir` is fixed at the first write (nothing = not written yet), `nsaved` counts the
# messages in the messages file, `meta` hashes the last session JSON written.
mutable struct _SessionStore
    dir::Union{Nothing,String}
    nsaved::Int
    meta::UInt
end
_SessionStore() = _SessionStore(nothing, 0, UInt(0))

"""
    Session(model; name = nothing, system = nothing, tools = nothing, loaded_tools = nothing, thinking_effort = nothing, temperature = nothing)
    Session(; name = nothing, system = nothing, tools = nothing, loaded_tools = nothing, thinking_effort = nothing, temperature = nothing)

One conversation: a `name`, the active `model`, optional `system` instructions, the tools the
model may call, and the typed message history in `messages`. `model` may be a [`Model`](@ref)
or a `"provider/model"` string; without one the saved [`default_model`](@ref) is used, and an
error is thrown if none is set.

`tools = nothing` gives the session every registered tool (see [`register_tool!`](@ref)),
including ones registered later; a vector of tool names or functions restricts it (see
[`set_tools!`](@ref)).

`loaded_tools` are the session's tools the model sees in full from the start; its other tools
are only found through tool search (see [`load_tools!`](@ref)). `nothing` takes them from the
Preference `loaded_tools` (default none); a vector of tool names, functions or group names
replaces it.

`thinking_effort` and `temperature` apply to every [`chat!`](@ref) on the session unless the
call passes its own; `nothing` leaves them to the Preferences of the same name (see
[`set_thinking_effort!`](@ref), [`set_temperature!`](@ref)).

Every session is registered (see [`sessions`](@ref)) so the REPL can switch to it, and stays
registered until [`delete_session!`](@ref). Without a `name` it is called `"session"`. Names
need not be unique (the `id` tells sessions apart) and may only contain letters, digits, `.`,
`_` and `-`. History is provider-agnostic, so the model can be switched with
[`set_model!`](@ref) at any time.

`model` is `nothing` only for the `"default"` session JAIL starts when no default model is
saved (see [`active_session`](@ref)).

Each session has an `id` (a version 7 `UUID`, so ids sort by creation time) and a `created`
time (`DateTime`, UTC). Sessions are saved to disk from their first message on and can be
brought back with [`restore_session!`](@ref); see that function for the files and Preferences.

Without `system`, the session gets JAIL's built-in REPL instructions (be concise, fence code in
```` ``` ```` blocks) plus a line describing the environment at creation (Julia version, OS,
active project, packages loaded in `Main`). The Preference `system_prompt` replaces the
instructions. Pass `system = ""` for no system instructions.
"""
mutable struct Session
    const id::UUID
    const created::DateTime
    const name::String
    model::Union{Nothing,AbstractModel}
    system::Union{Nothing,String}
    tools::Union{Nothing,Vector{String}}
    loaded_tools::Vector{String}
    thinking_effort::Union{Nothing,Symbol}
    temperature::Union{Nothing,Float64}
    agent::Union{Nothing,String}
    agent_path::Union{Nothing,String}
    const messages::Vector{AbstractMessage}
    const _store::_SessionStore
    function Session(::_Register, name::AbstractString, model, system, tools = nothing;
                     id::UUID = uuid7(), messages = AbstractMessage[],
                     store::_SessionStore = _SessionStore(), thinking_effort = nothing,
                     temperature = nothing, loaded_tools = _default_loaded(),
                     agent = nothing, agent_path = nothing)
        s = new(id, _uuid7_time(id), String(name), model,
                system === nothing ? nothing : String(system), tools, loaded_tools,
                _check_effort(thinking_effort), _check_temperature(temperature), agent, agent_path,
                messages, store)
        push!(_SESSIONS, s)
        return s
    end
end

const _SESSIONS = Session[]
const _ACTIVE = Ref{Session}()

function Session(model::AbstractModel; name::Union{Nothing,AbstractString} = nothing,
                 system::Union{Nothing,AbstractString} = nothing, tools = nothing,
                 loaded_tools::Union{Nothing,AbstractVector} = nothing,
                 thinking_effort = nothing, temperature = nothing)
    name === nothing || _check_session_name(name)
    names = _tool_names(tools)
    loaded = loaded_tools === nothing ? _default_loaded() : _load_names(loaded_tools; strict = true)
    system = system === nothing ? _default_system() : isempty(system) ? nothing : system
    return Session(_Register(), something(name, "session"), model, system, names;
                   thinking_effort, temperature, loaded_tools = loaded)
end
Session(model::AbstractString; kwargs...) = Session(Model(model); kwargs...)

function Session(; kwargs...)
    _load_pref("default_model") === nothing && error(
        "No default model is set. Pass one, e.g. `Session(\"anthropic/claude-sonnet-4-5\")`, or " *
        "save a default with `set_default_model!`.")
    return Session(default_model(); kwargs...)
end

function _check_session_name(name::AbstractString)
    occursin(r"^[A-Za-z0-9._-]+$", name) || throw(ArgumentError(
        "session name may only contain letters, digits, '.', '_' and '-', got \"$name\""))
    tryparse(UUID, name) === nothing || throw(ArgumentError(
        "session name can't be a UUID (UUIDs refer to session ids), got \"$name\""))
    return nothing
end

_session(s::Session, term = nothing) = s

function _session(id::UUID, term = nothing)
    i = findfirst(s -> s.id == id, _SESSIONS)
    i === nothing && throw(ArgumentError("no loaded session with id $id"))
    return _SESSIONS[i]
end

# A UUID string is an id; otherwise a name, with a menu when several sessions share it.
function _session(x::AbstractString, term = nothing)
    id = tryparse(UUID, x)
    id === nothing || return _session(id)
    matches = filter(s -> s.name == x, _SESSIONS)
    isempty(matches) && throw(ArgumentError(
        "no session named \"$x\" (sessions: $(join(unique(s.name for s in _SESSIONS), ", ")))"))
    length(matches) == 1 && return only(matches)
    i = _pick(something(term, _menu_terminal()), "Several sessions are named \"$x\":",
              _session_rows(matches))
    return i === nothing ? nothing : matches[i]
end

_session_row(s::Session, width::Int) = string(rpad(s.name, width), "  ", _local_time(s.created), "  ",
    rpad(something(_model_string(s), "no model"), 30), "  ", length(s.messages), " messages  ", s.id)

function _session_rows(ss)
    width = maximum(s -> length(s.name), ss)
    return [(s === active_session() ? "* " : "  ") * _session_row(s, width) for s in ss]
end

"""
    sessions() -> Vector{Session}

All registered sessions, in creation order.
"""
sessions() = copy(_SESSIONS)

"""
    active_session() -> Session

The session the REPL modes and session-less calls such as `select_model!()` act on. JAIL starts
a session named `"default"` using the saved default model (or no model if none is saved).
"""
active_session() = _ACTIVE[]

"""
    use_session!(session_name_or_id) -> Union{Session,Nothing}

Make a registered session the active one. Accepts a `Session`, its `id` (a `UUID` or its
string), or its name; when several sessions share the name, a terminal menu chooses one
(cancelling returns `nothing`).
"""
function use_session!(x::Union{AbstractString,UUID,Session})
    s = _session(x)
    s === nothing && return nothing
    s in _SESSIONS || throw(ArgumentError("session \"$(s.name)\" has been deleted"))
    return _ACTIVE[] = s
end

"""
    new_session!(name = nothing; model = nothing, system = nothing, tools = nothing,
                 loaded_tools = nothing, thinking_effort = nothing, temperature = nothing) -> Session

Create a session and make it the active one. `model` defaults to the saved default model.
"""
function new_session!(name::Union{Nothing,AbstractString} = nothing; model = nothing, system = nothing,
                      tools = nothing, loaded_tools = nothing, thinking_effort = nothing,
                      temperature = nothing)
    kw = (; name, system, tools, loaded_tools, thinking_effort, temperature)
    s = model === nothing ? Session(; kw...) : Session(model; kw...)
    return _ACTIVE[] = s
end

"""
    delete_session!(session_name_or_id; files = false) -> Union{Session,Nothing}

Unregister a session, given as for [`use_session!`](@ref) (a menu chooses among sessions that
share a name; cancelling returns `nothing`). The active session can't be deleted; switch away
first. Its saved files stay, so it can be brought back with [`restore_session!`](@ref), unless
`files = true`.
"""
function delete_session!(x::Union{AbstractString,UUID,Session}; files::Bool = false)
    s = _session(x)
    s === nothing && return nothing
    i = findfirst(==(s), _SESSIONS)
    i === nothing && throw(ArgumentError("session \"$(s.name)\" is not registered"))
    s === active_session() && throw(ArgumentError(
        "can't delete the active session \"$(s.name)\"; switch to another session first"))
    deleteat!(_SESSIONS, i)
    files && _delete_files!(s)
    return s
end

# Called from __init__; only this session may start without a model.
function _start_default_session!()
    empty!(_SESSIONS)
    saved = _load_pref("default_model")
    model = try
        saved === nothing ? nothing : Model(saved)
    catch e
        @warn "JAIL: saved default model \"$saved\" can't be used; the default session has no model" exception = e
        nothing
    end
    system = try
        _default_system()
    catch e
        @warn "JAIL: the default session has no system instructions" exception = e
        nothing
    end
    _ACTIVE[] = Session(_Register(), "default", model, system, nothing;
                        loaded_tools = _default_loaded(; warn = true))
    return nothing
end

_model_string(s::Session) = s.model === nothing ? nothing : string(s.model)

"""
    set_model!(session::Session, model::Union{AbstractString,Model}) -> Model
    set_model!(model::Union{AbstractString,Model}) -> Model

Switch the session's model, or the [`active_session`](@ref)'s when no session is given,
keeping its history. Does not change the default model.
"""
set_model!(s::Session, m::AbstractModel) = (s.model = m; _sync_meta!(s); m)
set_model!(s::Session, m::AbstractString) = set_model!(s, Model(m))
set_model!(m::Union{AbstractString,AbstractModel}) = set_model!(active_session(), m)

"""
    use_provider!(session::Session, p::AbstractProvider) -> Model
    use_provider!(p::AbstractProvider) -> Model

Switch the session (or the [`active_session`](@ref) when none is given) to `p`'s own default
model, saved with [`set_default_model!`](@ref)`(p, id)`. Throws if `p` has no default model
saved. The imperative form of the REPL's `use provider` (no model id).
"""
use_provider!(s::Session, p::AbstractProvider) = set_model!(s, default_model(p))
use_provider!(p::AbstractProvider) = use_provider!(active_session(), p)

"""
    set_thinking_effort!(session::Session, level) -> Union{Symbol,Nothing}
    set_thinking_effort!(level)

Set how much the session's model reasons on every [`chat!`](@ref), or the
[`active_session`](@ref)'s when no session is given: a `Symbol` such as `:low` or `:high`, sent
as-is (see [`chat!`](@ref) for the levels and how each provider takes them). `nothing` clears
it, leaving the Preference `thinking_effort` (if set) in charge. A `thinking_effort` passed to
`chat!` wins over it.

```julia
set_thinking_effort!(s, :low)
set_thinking_effort!(s, nothing)
```
"""
set_thinking_effort!(s::Session, x::Union{Nothing,Symbol,AbstractString}) =
    (s.thinking_effort = _check_effort(x); _sync_meta!(s); s.thinking_effort)
set_thinking_effort!(x::Union{Nothing,Symbol,AbstractString}) = set_thinking_effort!(active_session(), x)

"""
    set_temperature!(session::Session, t) -> Union{Float64,Nothing}
    set_temperature!(t)

Set the sampling temperature (a non-negative number) for every [`chat!`](@ref) on the session,
or the [`active_session`](@ref) when no session is given. It is sent as-is: ranges differ by
provider (OpenAI 0 to 2, Anthropic 0 to 1) and some models reject any non-default value.
`nothing` clears it, leaving the Preference `temperature` (if set) in charge. A `temperature`
passed to `chat!` wins over it.
"""
set_temperature!(s::Session, t::Union{Nothing,Real}) =
    (s.temperature = _check_temperature(t); _sync_meta!(s); s.temperature)
set_temperature!(t::Union{Nothing,Real}) = set_temperature!(active_session(), t)

"""
    empty!(session::Session)

Clear the message history, keeping the model and system instructions. A saved session's
messages file is emptied too.
"""
Base.empty!(s::Session) = (empty!(s.messages); _sync!(s); s)

# nothing = every registered tool; otherwise registered names (functions are mapped to names).
_tool_names(::Nothing) = nothing
function _tool_names(xs)
    names = String[x isa Function ? _tool_name(x) : x isa ToolSpec ? x.name : String(x) for x in xs]
    for n in names
        haskey(_TOOLS, n) || throw(ArgumentError(
            "no tool named \"$n\" is registered (tools: $(join(sort!(collect(keys(_TOOLS))), ", ")))"))
    end
    return unique!(names)
end

"""
    tools(session::Session) -> Vector{ToolSpec}

The tools the session's model may call: every registered tool, or the subset chosen with
[`set_tools!`](@ref). Tools unregistered since are left out.
"""
tools(s::Session) = s.tools === nothing ? tools() : ToolSpec[_TOOLS[n] for n in s.tools if haskey(_TOOLS, n)]

"""
    set_tools!(session::Session, tools) -> Vector{ToolSpec}
    set_tools!(tools)

Choose which registered tools the session (or the [`active_session`](@ref)) may use: a vector
of tool names or functions restricts it, `[]` gives it none, and `nothing` gives it every
registered tool (the default, which also includes tools registered later). Returns the
session's tools.

```julia
set_tools!(s, [get_weather, "search_docs"])
set_tools!(s, nothing)
```
"""
set_tools!(s::Session, xs::Union{Nothing,AbstractVector}) = (s.tools = _tool_names(xs); _sync_meta!(s); tools(s))
set_tools!(xs::Union{Nothing,AbstractVector}) = set_tools!(active_session(), xs)

const _ToolRef = Union{AbstractString,Symbol,Function,ToolSpec}

# Tool names for tool references: a function or ToolSpec is its tool; a string or symbol is a
# registered tool's name, else a group (`group:<g>` or just `<g>`) of registered tools. With
# `strict`, anything else throws; without, it is kept as a name (a tool registered later).
function _load_names(xs; strict::Bool)
    out = String[]
    for x in xs
        x isa Function && (push!(out, _tool_name(x)); continue)
        x isa ToolSpec && (push!(out, x.name); continue)
        x isa _ToolRef || throw(ArgumentError("expected tool names, functions or groups, got $(repr(x))"))
        n = string(x)
        g = startswith(n, "group:") ? n[length("group:")+1:end] : nothing
        if g === nothing && haskey(_TOOLS, n)
            push!(out, n)
        elseif (grp = something(g, n); any(t -> t.group == grp, values(_TOOLS)))
            append!(out, sort!([t.name for t in values(_TOOLS) if t.group == grp]))
        elseif strict
            throw(ArgumentError("no tool or tool group named \"$n\" is registered"))
        else
            push!(out, n)
        end
    end
    return unique!(out)
end

# Loaded tools for a new session, from the Preference `loaded_tools`.
function _default_loaded(; warn::Bool = false)
    try
        return _load_names(_string_list_pref("loaded_tools"); strict = false)
    catch e
        e isa ArgumentError && warn || rethrow()
        @warn "JAIL: the Preference `loaded_tools` is ignored" exception = e
        return String[]
    end
end

_loaded_specs(s::Session) = ToolSpec[t for t in tools(s) if t.name in s.loaded_tools]

"""
    load_tools!(session::Session, tools...) -> Vector{ToolSpec}
    load_tools!(tools...)

Load registered tools in the session (or the [`active_session`](@ref)): each is a tool name,
function, [`ToolSpec`](@ref) or group name (`"read"`, or `"group:read"` when a tool has the
same name). Returns the session's loaded tools.

A session sends its tools in two ways. **Loaded** tools are given to the model in full on every
request. Every other tool of the session is only **registered**: the model finds it through
tool search and loads it when it needs it, which keeps large tool sets out of the context.
OpenAI and Anthropic search natively (`defer_loading`); for the other providers, JAIL gives the
model two tools of its own, `tool_search` and `tool_load` (see the Tools guide).

New sessions load the tools named in the Preference `loaded_tools` (default none). Loaded tools
are saved with the session. See also [`unload_tools!`](@ref), [`tool_status`](@ref).

```julia
load_tools!(s, "read_file", "grep_files")
load_tools!(get_weather)
load_tools!(s, "memory")     # a whole group
```
"""
function load_tools!(s::Session, xs::_ToolRef...)
    isempty(xs) && throw(ArgumentError("name the tools or groups to load, e.g. `load_tools!(s, \"read_file\")`"))
    names = _load_names(xs; strict = true)
    append!(s.loaded_tools, setdiff(names, s.loaded_tools))
    _sync_meta!(s)
    return _loaded_specs(s)
end
load_tools!(xs::_ToolRef...) = load_tools!(active_session(), xs...)

"""
    unload_tools!(session::Session, tools...) -> Vector{ToolSpec}
    unload_tools!(tools...)

Take tools (names, functions, [`ToolSpec`](@ref)s or group names, as for
[`load_tools!`](@ref)) out of the session's loaded tools, so they are found through tool search
again. Returns the session's loaded tools.
"""
function unload_tools!(s::Session, xs::_ToolRef...)
    isempty(xs) && throw(ArgumentError("name the tools or groups to unload, e.g. `unload_tools!(s, \"read_file\")`"))
    names = _load_names(xs; strict = false)
    unknown = filter(n -> !(n in s.loaded_tools) && !haskey(_TOOLS, n), names)
    isempty(unknown) || throw(ArgumentError("no tool or tool group named $(join(repr.(unknown), ", ")) is registered"))
    filter!(n -> !(n in names), s.loaded_tools)
    _sync_meta!(s)
    return _loaded_specs(s)
end
unload_tools!(xs::_ToolRef...) = unload_tools!(active_session(), xs...)

"""
    tool_status(session::Session, tool) -> Symbol
    tool_status(tool)

The status of a tool (a name, function or [`ToolSpec`](@ref)) in the session (or the
[`active_session`](@ref)): `:unregistered` (not in the registry, see [`register_tool!`](@ref)),
`:registered` (found through tool search) or `:loaded` (given to the model in full, see
[`load_tools!`](@ref)). Tools the session is restricted from (see [`set_tools!`](@ref)) are
never sent, whatever their status.
"""
function tool_status(s::Session, x::Union{AbstractString,Symbol,Function,ToolSpec})
    name = x isa Function ? _tool_name(x) : x isa ToolSpec ? x.name : string(x)
    haskey(_TOOLS, name) || return :unregistered
    return name in s.loaded_tools ? :loaded : :registered
end
tool_status(x::Union{AbstractString,Symbol,Function,ToolSpec}) = tool_status(active_session(), x)

Base.show(io::IO, s::Session) = print(io, "Session(", repr(s.name), ", ",
    something(_model_string(s), "no model"), ", ", length(s.messages), " messages)")

Base.show(io::IO, ::MIME"text/plain", s::Session) = _show_details(io, s)

# A session setting as it will be sent: the session's own value, else the Preference, else none.
function _setting_label(v, key::AbstractString, check)
    v === nothing || return string(v)
    p = _load_pref(key)
    p === nothing && return "model default"
    ok = try
        check(p)
    catch
        return string(repr(p), " (Preference, invalid)")
    end
    return string(ok, " (Preference)")
end

function _reasoning_label()
    v = _load_pref("show_reasoning", false)
    return v === true ? "shown" : v === false ? "hidden" : string(repr(v), " (Preference, invalid)")
end

# The detailed display, shared by `show` and the `|` mode's `status`; `status` adds the hint for a
# missing model and the saved default when it differs.
function _show_details(io::IO, s::Session; status::Bool = false)
    row(label, value) = println(io, "  ", rpad(label * ":", 13), value)
    println(io, "Session ", repr(s.name))
    row("id", s.id)
    row("created", _local_time(s.created) * " (local time)")
    if s.model === nothing
        row("model", status ? "none (choose one with `use provider/model` or `select`)" : "none")
    else
        row("model", _model_string(s))
        row("provider", repr(s.model.provider))
    end
    if status
        default = _load_pref("default_model")
        default == _model_string(s) || row("default", something(default, "none"))
    end
    row("system", s.system === nothing ? "none" : _system_preview(s.system))
    row("agent", something(s.agent, "none (agent mode uses \"julia\")"))
    row("tools", _tools_label(s))
    row("loaded", _loaded_label(s))
    row("thinking", _setting_label(s.thinking_effort, "thinking_effort", x -> _check_effort(x)))
    row("temperature", _setting_label(s.temperature, "temperature", x -> _check_temperature(x)))
    row("reasoning", _reasoning_label())
    print(io, "  ", rpad("messages:", 13), length(s.messages))
end

function _tools_label(s::Session)
    ts = tools(s)
    names = isempty(ts) ? "none" : join((t.name for t in ts), ", ")
    return s.tools === nothing ? "all ($names)" : names
end

function _loaded_label(s::Session)
    ts = _loaded_specs(s)
    names = isempty(ts) ? "none" : join((t.name for t in ts), ", ")
    s.model === nothing && return names
    mode = try
        _tool_search_mode(s.model.provider)
    catch
        return names
    end
    return string(names, " (others found with ", mode === :hosted ? "the provider's tool search" :
                  "JAIL's tool_search/tool_load", ")")
end

function _system_preview(text::AbstractString, n = 60)
    line = first(split(text, '\n'))
    short = length(line) <= n ? line : first(line, n - 1) * "…"
    return short == text ? repr(text) : string(repr(short), " (", length(text), " chars)")
end
