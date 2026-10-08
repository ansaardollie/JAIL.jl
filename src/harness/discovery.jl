# Agent and skill files: types, the folders they are found in, and choosing among same-named ones.

"""
    Agent

An agent for the agent mode ([`agent!`](@ref), the `&` REPL mode): its `name`, `description`,
`instructions` (the file's text without its YAML front matter, added to the system prompt), the
`tools` it uses (loaded and run without asking while it is applied), the `disallowed_tools` it
removes from the session, the file `path` (`nothing` for the built-in `julia` agent), where it
was found (`source`: `:workspace`, `:storage`, `:home` or `:builtin`) and the parsed
`frontmatter`. See [`agents`](@ref).
"""
struct Agent
    name::String
    description::String
    instructions::String
    tools::Vector{String}
    disallowed_tools::Vector{String}
    path::Union{Nothing,String}
    source::Symbol
    frontmatter::Dict{String,Any}
end

Base.show(io::IO, a::Agent) = print(io, "Agent(", repr(a.name), ", ", a.source, ")")

"""
    SkillArgument

One entry of a skill's `arguments` front matter: `name`, `type` (`:string`, `:integer`,
`:number` or `:boolean`), `description`, whether it is `required` (default `true`), its
`default` (`nothing` when not given) and the `hint` from `argument-hint`.
"""
struct SkillArgument
    name::String
    type::Symbol
    description::String
    required::Bool
    default::Any
    hint::Union{Nothing,String}
end

"""
    Skill

A skill (`<folder>/SKILL.md`): `name`, `description`, `when_to_use`, its `body` (the file
without front matter), its folder `dir`, typed `arguments`, a plain-text `argument_hint`,
whether the user may run it with `/name` (`user_invocable`) and whether the model knows about
it (`model_invocable`), the tools it lets run without asking (`allowed_tools`) or forbids
(`disallowed_tools`), where it was found (`source`) and the parsed `frontmatter`. See
[`skills`](@ref).
"""
struct Skill
    name::String
    description::String
    when_to_use::Union{Nothing,String}
    body::String
    dir::String
    arguments::Vector{SkillArgument}
    argument_hint::Union{Nothing,String}
    user_invocable::Bool
    model_invocable::Bool
    allowed_tools::Vector{String}
    disallowed_tools::Vector{String}
    source::Symbol
    frontmatter::Dict{String,Any}
end

Base.show(io::IO, s::Skill) = print(io, "Skill(", repr(s.name), ", ", s.source, ")")

_skill_path(s::Skill) = joinpath(s.dir, "SKILL.md")

const _DEFAULT_AGENT = "julia"

const _JULIA_AGENT = Agent(_DEFAULT_AGENT, "JAIL's built-in agent: tools, no extra instructions.",
                           "", String[], String[], nothing, :builtin, Dict{String,Any}())

# Base folders, in listing order: workspace, storage_dir, home.
function _harness_bases()
    root, home = _workspace_root(), homedir()
    return [(:workspace, joinpath(root, ".github")), (:workspace, joinpath(root, ".claude")),
            (:workspace, joinpath(root, ".copilot")), (:storage, _storage_dir()),
            (:home, joinpath(home, ".claude")), (:home, joinpath(home, ".agents")),
            (:home, joinpath(home, ".copilot"))]
end

# `~/.agents` holds agents directly; the other bases in an `agents` folder.
_agent_dirs() = [(src, base == joinpath(homedir(), ".agents") ? base : joinpath(base, "agents"))
                 for (src, base) in _harness_bases()]
_skill_dirs() = [(src, joinpath(base, "skills")) for (src, base) in _harness_bases()]

_is_agent_file(f) = endswith(f, ".agent.md") || f in ("AGENTS.md", "CLAUDE.md")

_agent_stem(f) = endswith(f, ".agent.md") ? f[1:end-length(".agent.md")] : f[1:end-length(".md")]

function _read_agent(path::AbstractString, source::Symbol)
    fm, body = _frontmatter(read(path, String))
    name = _fm_string(fm, "name", _agent_stem(basename(path)))
    return Agent(name, _fm_string(fm, "description", ""), body,
                 _name_list(get(fm, "tools", nothing), "tools"),
                 _name_list(get(fm, "disallowedTools", nothing), "disallowedTools"),
                 path, source, fm)
end

# Warned once per file version: discovery runs on every agent turn.
function _skipped(kind, path, e)
    key = string("skip:", path, ":", mtime(path))
    key in _WARNED_TOOL_REFS && return nothing
    push!(_WARNED_TOOL_REFS, key)
    @warn "JAIL: skipping the $kind file $(Base.contractuser(path))" exception = e
    return nothing
end

"""
    agents() -> Vector{Agent}

Every agent found now, sorted by name, starting with JAIL's built-in `julia` agent. Agent files
are `*.agent.md`, `AGENTS.md` and `CLAUDE.md` in `./.github/agents`, `./.claude/agents`,
`./.copilot/agents` (the current directory), `<storage_dir>/agents`, `~/.claude/agents`,
`~/.agents` and `~/.copilot/agents`. An agent's name is its front matter `name`, else the file
name without `.agent.md` / `.md`. Names may repeat across folders; choosing one by name then
asks which. A file agent named `julia` is ignored. See [`use_agent!`](@ref).
"""
function agents()
    out = Agent[_JULIA_AGENT]
    for (src, dir) in _agent_dirs()
        isdir(dir) || continue
        for f in sort!(readdir(dir))
            path = joinpath(dir, f)
            (_is_agent_file(f) && isfile(path)) || continue
            a = try
                _read_agent(path, src)
            catch e
                e isa InterruptException && rethrow()
                _skipped("agent", path, e)
            end
            a === nothing && continue
            if a.name == _DEFAULT_AGENT
                _warn_ref_once("reserved:$path", "the agent name \"julia\" is reserved for the built-in agent; ignoring $(Base.contractuser(path))")
                continue
            end
            push!(out, a)
        end
    end
    return sort!(out; by = a -> (a.name != _DEFAULT_AGENT, a.name))
end

const _ARG_TYPES = ("string", "integer", "number", "boolean")

function _skill_arguments(fm)
    args = get(fm, "arguments", nothing)
    args === nothing && return SkillArgument[]
    args isa AbstractDict || throw(ArgumentError("`arguments` must be a mapping of argument names"))
    hints = get(fm, "argument-hint", nothing)
    out = SkillArgument[]
    for (name, spec) in args
        name = string(name)
        occursin(r"^[A-Za-z_][A-Za-z0-9_-]*$", name) || throw(ArgumentError("invalid argument name `$name`"))
        spec === nothing && (spec = Dict{String,Any}())
        spec isa AbstractDict || throw(ArgumentError("argument `$name` must be a mapping (type, description, required, default)"))
        type = string(get(spec, "type", "string"))
        type in _ARG_TYPES || throw(ArgumentError("argument `$name` has type `$type`; use one of $(join(_ARG_TYPES, ", "))"))
        hint = hints isa AbstractDict ? get(hints, name, nothing) : nothing
        push!(out, SkillArgument(name, Symbol(type), _fm_string(spec, "description", ""),
                                 _fm_bool(spec, "required", true), get(spec, "default", nothing),
                                 hint === nothing ? nothing : string(hint)))
    end
    return out
end

function _read_skill(dir::AbstractString, source::Symbol)
    fm, body = _frontmatter(read(joinpath(dir, "SKILL.md"), String))
    hint = get(fm, "argument-hint", nothing)
    plain_hint = hint isa AbstractString ? String(hint) : nothing
    return Skill(_fm_string(fm, "name", basename(dir)), _fm_string(fm, "description", ""),
                 _fm_string(fm, "when_to_use"), body, dir, _skill_arguments(fm), plain_hint,
                 hint !== nothing || _fm_bool(fm, "user-invocable", true),
                 !_fm_bool(fm, "disable-model-invocation", false),
                 _name_list(get(fm, "allowed-tools", nothing), "allowed-tools"),
                 _name_list(get(fm, "disallowed-tools", nothing), "disallowed-tools"), source, fm)
end

"""
    skills() -> Vector{Skill}

Every skill found now, sorted by name: each `<name>/SKILL.md` in the `skills` folder of
`./.github`, `./.claude`, `./.copilot` (the current directory), `<storage_dir>`, `~/.claude`,
`~/.agents` and `~/.copilot`. A skill's name is its front matter `name`, else its folder name.
See the Agents guide for the front matter keys.

The Preference `allowed_skills` (a list of names) keeps only those skills; `disallowed_skills`
drops those. Set one of them: with both, `allowed_skills` is used and a warning shown.
"""
function skills()
    out = Skill[]
    for (src, dir) in _skill_dirs()
        isdir(dir) || continue
        for f in sort!(readdir(dir))
            sdir = joinpath(dir, f)
            isfile(joinpath(sdir, "SKILL.md")) || continue
            s = try
                _read_skill(sdir, src)
            catch e
                e isa InterruptException && rethrow()
                _skipped("skill", joinpath(sdir, "SKILL.md"), e)
            end
            s === nothing || push!(out, s)
        end
    end
    keep = _skill_filter()
    return sort!(filter!(s -> keep(s.name), out); by = s -> s.name)
end

# Name predicate from the `allowed_skills` / `disallowed_skills` Preferences.
function _skill_filter()
    allowed = _load_pref("allowed_skills") === nothing ? nothing : Set(_string_list_pref("allowed_skills"))
    denied = _load_pref("disallowed_skills") === nothing ? nothing : Set(_string_list_pref("disallowed_skills"))
    if allowed !== nothing
        denied === nothing || _warn_ref_once("pref:skills_both",
            "the Preferences `allowed_skills` and `disallowed_skills` are both set; `allowed_skills` is used")
        return in(allowed)
    end
    return denied === nothing ? Returns(true) : !in(denied)
end

_location(a::Agent) = a.path === nothing ? "built in" : string(a.source, ": ", Base.contractuser(a.path))
_location(s::Skill) = string(s.source, ": ", Base.contractuser(_skill_path(s)))

# Asks which of several same-named items; overridden in scripted checks.
const _CHOOSER = Ref{Any}((title, labels) -> _pick(_menu_terminal(), title, labels))

# The one item named `name`, a menu when several share it, `nothing` when cancelled.
function _by_name(items::Vector{T}, name::AbstractString, kind::AbstractString) where {T}
    found = filter(x -> x.name == name, items)
    isempty(found) && throw(ArgumentError("no $kind named \"$name\" (found: " *
        (isempty(items) ? "none" : join(unique(x.name for x in items), ", ")) * ")"))
    length(found) == 1 && return only(found)
    i = _CHOOSER[]("Several $(kind)s are named \"$name\":", String[_location(x) for x in found])
    return i === nothing ? nothing : found[i]
end
