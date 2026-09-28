struct _Register end

"""
    Session(model; name = nothing, system = nothing, tools = nothing)
    Session(; name = nothing, system = nothing, tools = nothing)

One conversation: a `name`, the active `model`, optional `system` instructions, the tools the
model may call, and the typed message history in `messages`. `model` may be a [`Model`](@ref)
or a `"provider/model"` string; without one the saved [`default_model`](@ref) is used, and an
error is thrown if none is set.

`tools = nothing` gives the session every registered tool (see [`register_tool!`](@ref)),
including ones registered later; a vector of tool names or functions restricts it (see
[`set_tools!`](@ref)).

Every session is registered (see [`sessions`](@ref)) so the REPL can switch to it, and stays
registered until [`delete_session!`](@ref). Without a `name` it is called `"session"`; a name
already in use gets a suffix (`"refactor-2"`). Names may only contain letters, digits, `.`,
`_` and `-`. History is provider-agnostic, so the model can be switched with
[`set_model!`](@ref) at any time.

`model` is `nothing` only for the `"default"` session JAIL starts when no default model is
saved (see [`active_session`](@ref)).

Without `system`, the session gets JAIL's built-in REPL instructions (be concise, fence code in
```` ``` ```` blocks) plus a line describing the environment at creation (Julia version, OS,
active project, packages loaded in `Main`). The Preference `system_prompt` replaces the
instructions. Pass `system = ""` for no system instructions.
"""
mutable struct Session
    const name::String
    model::Union{Nothing,AbstractModel}
    system::Union{Nothing,String}
    tools::Union{Nothing,Vector{String}}
    const messages::Vector{AbstractMessage}
    function Session(::_Register, name::AbstractString, model, system, tools = nothing)
        s = new(_unique_session_name(name), model,
                system === nothing ? nothing : String(system), _tool_names(tools), AbstractMessage[])
        push!(_SESSIONS, s)
        return s
    end
end

const _SESSIONS = Session[]
const _ACTIVE = Ref{Session}()

function Session(model::AbstractModel; name::Union{Nothing,AbstractString} = nothing,
                 system::Union{Nothing,AbstractString} = nothing, tools = nothing)
    name === nothing || _check_session_name(name)
    names = _tool_names(tools)
    system = system === nothing ? _default_system() : isempty(system) ? nothing : system
    return Session(_Register(), something(name, "session"), model, system, names)
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
    return nothing
end

_find_session(name::AbstractString) = findfirst(s -> s.name == name, _SESSIONS)

function _unique_session_name(base::AbstractString)
    _find_session(base) === nothing && return String(base)
    n = 2
    while _find_session("$base-$n") !== nothing
        n += 1
    end
    return "$base-$n"
end

function _session(name::AbstractString)
    i = _find_session(name)
    i === nothing && throw(ArgumentError(
        "no session named \"$name\" (sessions: $(join((s.name for s in _SESSIONS), ", ")))"))
    return _SESSIONS[i]
end
_session(s::Session) = s

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
    use_session!(name_or_session) -> Session

Make a registered session the active one.
"""
function use_session!(x::Union{AbstractString,Session})
    s = _session(x)
    s in _SESSIONS || throw(ArgumentError("session \"$(s.name)\" has been deleted"))
    return _ACTIVE[] = s
end

"""
    new_session!(name = nothing; model = nothing, system = nothing, tools = nothing) -> Session

Create a session and make it the active one. `model` defaults to the saved default model.
"""
function new_session!(name::Union{Nothing,AbstractString} = nothing; model = nothing, system = nothing,
                      tools = nothing)
    s = model === nothing ? Session(; name, system, tools) : Session(model; name, system, tools)
    return _ACTIVE[] = s
end

"""
    delete_session!(name_or_session) -> Session

Unregister a session. The active session can't be deleted; switch away first.
"""
function delete_session!(x::Union{AbstractString,Session})
    s = _session(x)
    i = findfirst(==(s), _SESSIONS)
    i === nothing && throw(ArgumentError("session \"$(s.name)\" is not registered"))
    s === active_session() && throw(ArgumentError(
        "can't delete the active session \"$(s.name)\"; switch to another session first"))
    deleteat!(_SESSIONS, i)
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
    _ACTIVE[] = Session(_Register(), "default", model, system)
    return nothing
end

_model_string(s::Session) = s.model === nothing ? nothing : string(s.model)

"""
    set_model!(session::Session, model::Union{AbstractString,Model}) -> Model
    set_model!(model::Union{AbstractString,Model}) -> Model

Switch the session's model, or the [`active_session`](@ref)'s when no session is given,
keeping its history. Does not change the default model.
"""
set_model!(s::Session, m::AbstractModel) = (s.model = m)
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
    empty!(session::Session)

Clear the message history, keeping the model and system instructions.
"""
Base.empty!(s::Session) = (empty!(s.messages); s)

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
set_tools!(s::Session, xs::Union{Nothing,AbstractVector}) = (s.tools = _tool_names(xs); tools(s))
set_tools!(xs::Union{Nothing,AbstractVector}) = set_tools!(active_session(), xs)

Base.show(io::IO, s::Session) = print(io, "Session(", repr(s.name), ", ",
    something(_model_string(s), "no model"), ", ", length(s.messages), " messages)")

function Base.show(io::IO, ::MIME"text/plain", s::Session)
    println(io, "Session ", repr(s.name))
    println(io, "  model:    ", something(_model_string(s), "none"))
    println(io, "  system:   ", s.system === nothing ? "none" : _system_preview(s.system))
    println(io, "  tools:    ", _tools_label(s))
    print(io, "  messages: ", length(s.messages))
end

function _tools_label(s::Session)
    ts = tools(s)
    names = isempty(ts) ? "none" : join((t.name for t in ts), ", ")
    return s.tools === nothing ? "all ($names)" : names
end

function _system_preview(text::AbstractString, n = 60)
    line = first(split(text, '\n'))
    short = length(line) <= n ? line : first(line, n - 1) * "…"
    return short == text ? repr(text) : string(repr(short), " (", length(text), " chars)")
end
