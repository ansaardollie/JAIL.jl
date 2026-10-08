# Agent mode: the agent applied to a session, and the state of one `agent!` call.

const _AGENT_BOILERPLATE = """
    You are working as an agent (JAIL.jl agent mode): you can call tools to read and change files, run Julia code and shell commands, look up Julia source and documentation, and ask the user questions.

    - Keep working with tools until the user's request is done, checking the result of each step; then reply with a short summary of what you did.
    - The user may decline a tool call; adapt instead of repeating it.
    - Tool search is available: besides the tools you can see, more tools can be searched for and loaded. Before starting a task, always check whether there is a tool relevant to it, and search for one when none of your current tools fits."""

# JAIL's own agent-mode tools: never removed, denied or confirmed.
const _HARNESS_TOOLS = ("activate_skill", "read_skill_related_file", "tool_search", "tool_load")

# One `agent!` call. Activated skills add approvals and denials until the call ends; parallel tool
# calls may read it while `activate_skill` writes, hence the lock.
mutable struct _AgentTurn
    agent::Agent
    system::Union{Nothing,String}
    skills::Dict{String,Skill}       # model-visible skills by name
    active::Dict{String,Skill}       # skills activated in this turn
    removed::Set{String}             # the agent's disallowed tools
    loaded::Set{String}              # the agent's tools
    auto::Set{String}                # run without asking
    denied::Dict{String,String}      # tool => the skill that disallows it
    extra_loaded::Vector{ToolSpec}   # activate_skill, read_skill_related_file
    extra_deferred::Vector{ToolSpec} # skill_<name> tools
    lock::ReentrantLock
end

const _AGENT_TURN = ScopedValue{Union{Nothing,_AgentTurn}}(nothing)

function _source_of(path::AbstractString)
    for (src, dir) in _agent_dirs()
        _under(normpath(path), normpath(dir)) && return src
    end
    return :storage
end

# The session's agent, read from its remembered file; by name again when that file is gone.
function _session_agent(s::Session)
    (s.agent === nothing || s.agent == _DEFAULT_AGENT) && return _JULIA_AGENT
    p = s.agent_path
    if p !== nothing && isfile(p)
        a = _read_agent(p, _source_of(p))
        a.name == s.agent && return a
    end
    found = filter(a -> a.name == s.agent, agents())
    isempty(found) && throw(ArgumentError(
        "the agent \"$(s.agent)\" of session \"$(s.name)\" is no longer found; choose another with " *
        "`use_agent!` or `agent select` in the `|` mode"))
    a = _by_name(found, s.agent, "agent")
    a === nothing && throw(ArgumentError("no agent chosen"))
    s.agent_path = a.path
    _sync_meta!(s)
    return a
end

"""
    use_agent!(session::Session, name) -> Union{Agent,Nothing}
    use_agent!(name)

Apply the agent called `name` (see [`agents`](@ref)) to the session, or to the
[`active_session`](@ref) when none is given; `nothing` removes it. The agent shapes every
[`agent!`](@ref) turn (and the `&` REPL mode) on the session until changed: its instructions are
added to the system prompt, its `tools` are loaded and run without asking, and its
`disallowedTools` are left out. The registered memory tools are loaded in the session.
[`chat!`](@ref) is unaffected. Without an agent, agent turns use the built-in `julia` agent.

When several agent files share the name, a terminal menu asks which; the choice is remembered
with the session (and saved with it). Returns the agent, or `nothing` when removed (including
by choosing `"julia"`) or the menu was cancelled.
"""
function use_agent!(s::Session, name::Union{Nothing,AbstractString})
    if name === nothing
        s.agent = s.agent_path = nothing
        _sync_meta!(s)
        return nothing
    end
    a = _by_name(agents(), name, "agent")
    a === nothing && return nothing
    # The built-in agent is the same as no agent.
    s.agent, s.agent_path = a.path === nothing ? (nothing, nothing) : (a.name, a.path)
    # Agentic sessions load the registered memory tools, so the model sees them in full.
    a.path === nothing || append!(s.loaded_tools, setdiff([t.name for t in values(_TOOLS) if t.group == "memory"], s.loaded_tools))
    _sync_meta!(s)
    return a.path === nothing ? nothing : a
end
use_agent!(name::Union{Nothing,AbstractString}) = use_agent!(active_session(), name)

"""
    current_agent(session::Session = active_session()) -> Union{Agent,Nothing}

The agent applied to the session (re-read from its file), or `nothing` when none is (agent
turns then use the built-in `julia` agent). See [`use_agent!`](@ref).
"""
current_agent(s::Session = active_session()) = s.agent === nothing ? nothing : _session_agent(s)

_agent_name(s::Session) = something(s.agent, _DEFAULT_AGENT)

function _project_instructions()
    out = String[]
    for f in ("AGENTS.md", "CLAUDE.md")
        p = joinpath(_workspace_root(), f)
        isfile(p) || continue
        body = try
            last(_frontmatter(read(p, String)))
        catch e
            e isa InterruptException && rethrow()
            _skipped("project instructions", p, e)
            continue
        end
        isempty(strip(body)) || push!(out, string("## Project instructions (", f, ")\n\n", rstrip(body)))
    end
    return out
end

function _agent_system(s::Session, a::Agent, catalogue::Vector{Skill})
    parts = String[]
    s.system === nothing || push!(parts, rstrip(s.system))
    push!(parts, _AGENT_BOILERPLATE)
    append!(parts, _project_instructions())
    isempty(strip(a.instructions)) || push!(parts, string("## Agent: ", a.name, "\n\n", rstrip(a.instructions)))
    isempty(catalogue) || push!(parts, _skill_catalogue(catalogue))
    return join(parts, "\n\n")
end

# Builds the state of one agent turn; may ask (menus) which same-named agent or skill to use.
function _agent_turn(s::Session)
    a = _session_agent(s)
    sks = _turn_skills(s)
    pool = Set(t.name for t in tools(s))
    removed = setdiff(Set(_ref_names(_resolve_tool_refs(a.disallowed_tools))), _HARNESS_TOOLS)
    wanted = _ref_names(_resolve_tool_refs(a.tools))
    for n in wanted
        n in pool || _warn_ref_once("session:$(s.id):$n",
            "agent \"$(a.name)\" uses `$n`, which session \"$(s.name)\" doesn't have; it is left out")
    end
    loaded = setdiff(Set(filter(in(pool), wanted)), removed)
    catalogue = sort!([k for k in values(sks) if isempty(k.arguments)]; by = k -> k.name)
    extra_loaded, extra_deferred = _skill_specs(sks, catalogue)
    return _AgentTurn(a, _agent_system(s, a, catalogue), sks, Dict{String,Skill}(), removed, loaded,
                      copy(loaded), Dict{String,String}(), extra_loaded, extra_deferred, ReentrantLock())
end

# Turn-level approval: a denial message, `true` (run without asking) or `nothing` (usual rules).
function _turn_verdict(t::ToolSpec)
    turn = _AGENT_TURN[]
    (turn === nothing || t.name in _HARNESS_TOOLS || t.f isa _SkillTool) && return nothing
    return lock(turn.lock) do
        haskey(turn.denied, t.name) &&
            return "Denied: the skill `$(turn.denied[t.name])` does not allow `$(t.name)`."
        t.name in turn.auto ? true : nothing
    end
end

# Every tool the agent turn may call (before tool search's own tools).
function _turn_pool(s::Session, turn::_AgentTurn)
    base = ToolSpec[t for t in tools(s) if !(t.name in turn.removed)]
    return ToolSpec[base; turn.extra_loaded; turn.extra_deferred]
end

_turn_loaded(s::Session, turn::_AgentTurn, t::ToolSpec) =
    t.name in s.loaded_tools || t.name in turn.loaded || any(x -> x.name == t.name, turn.extra_loaded)
