# Creating and editing agent and skill files in <storage_dir>.

using InteractiveUtils: InteractiveUtils

# Opens a file for editing; replaced in scripted checks.
const _EDITOR = Ref{Any}(path -> InteractiveUtils.edit(path))

const _FILE_NAME = r"^[A-Za-z0-9_-]{1,64}$"

function _ask_text(label::AbstractString; io::IO = stdout, input::IO = stdin)
    printstyled(io, label, ": "; color = :cyan, bold = true)
    text = strip(readline(input))
    isempty(text) && throw(ArgumentError("no $(lowercase(label)) given"))
    return String(text)
end

function _check_new_name(name::AbstractString, kind::AbstractString)
    occursin(_FILE_NAME, name) || throw(ArgumentError(
        "$kind name \"$name\" may only use letters, digits, `-` and `_` (at most 64 characters)"))
    kind == "agent" && name == _DEFAULT_AGENT && throw(ArgumentError(
        "\"julia\" is the built-in agent's name; choose another"))
    return String(name)
end

_yaml_scalar(text::AbstractString) = JSON.json(String(text))   # a JSON string is a YAML scalar

function _agent_template(name, description)
    return """
        ---
        name: $(name)
        description: $(_yaml_scalar(description))
        # Tools this agent loads and runs without asking (JAIL names, group:<group>, or Claude Code /
        # VS Code names such as Read, Bash, edit).
        tools: []
        # Tools removed from the session while this agent is applied.
        disallowedTools: []
        ---

        # $(name)

        Describe the agent's role, how it should work, and what it must not do.
        """
end

function _skill_template(name, description)
    return """
        ---
        name: $(name)
        description: $(_yaml_scalar(description))
        # when_to_use: "Added to the description in the skill list the model sees."
        # Tools that run without asking once the skill is active (until the turn ends).
        allowed-tools: []
        # Tools refused while the skill is active.
        disallowed-tools: []
        # With arguments, the model gets the skill as a tool `skill_$(name)` and `/$(name) args...`
        # in the `&` mode fills them; use {{name}} in the text below (\\{ and \\} for literal braces).
        # arguments:
        #   path: {type: string, description: "File to work on"}
        #   depth: {type: integer, description: "How deep", required: false, default: 1}
        # argument-hint:
        #   path: "src/foo.jl"
        # user-invocable: true            # false hides /$(name) (unless argument-hint is set)
        # disable-model-invocation: false # true hides the skill from the model
        ---

        # $(name)

        Step-by-step instructions for the task this skill covers.
        """
end

function _new_file(path::AbstractString, text::AbstractString, kind::AbstractString)
    ispath(path) && throw(ArgumentError("$(Base.contractuser(path)) already exists; edit it with `edit_$kind`"))
    _write_atomic(path, text)
    _EDITOR[](path)
    return path
end

"""
    new_agent(name = nothing; description = nothing) -> String

Create `<storage_dir>/agents/<name>.agent.md` from a template (YAML front matter with `name`,
`description`, `tools` and `disallowedTools`, then the instructions) and open it with `edit`.
A missing `name` or `description` is asked for on the terminal. Returns the file's path. See
[`agents`](@ref), [`use_agent!`](@ref).
"""
function new_agent(name::Union{Nothing,AbstractString} = nothing; description::Union{Nothing,AbstractString} = nothing)
    name = _check_new_name(name === nothing ? _ask_text("Agent name") : name, "agent")
    description = description === nothing ? _ask_text("Description") : description
    path = joinpath(_storage_dir(), "agents", name * ".agent.md")
    return _new_file(path, _agent_template(name, description), "agent")
end

"""
    new_skill(name = nothing; description = nothing) -> String

Create `<storage_dir>/skills/<name>/SKILL.md` from a template (front matter with the skill keys,
most commented out) and open it with `edit`. A missing `name` or `description` is asked for on the
terminal. Returns the file's path. See [`skills`](@ref).
"""
function new_skill(name::Union{Nothing,AbstractString} = nothing; description::Union{Nothing,AbstractString} = nothing)
    name = _check_new_name(name === nothing ? _ask_text("Skill name") : name, "skill")
    description = description === nothing ? _ask_text("Description") : description
    path = joinpath(_storage_dir(), "skills", name, "SKILL.md")
    return _new_file(path, _skill_template(name, description), "skill")
end

function _pick_item(items, kind)
    isempty(items) && throw(ArgumentError("no $(kind)s found"))
    i = _CHOOSER[]("Choose $(kind == "agent" ? "an" : "a") $kind:", String[string(x.name, "  (", _location(x), ")") for x in items])
    return i === nothing ? nothing : items[i]
end

"""
    edit_agent(name = nothing) -> Union{String,Nothing}

Open an agent's file with `edit`; without a `name`, a terminal menu lists the agents. Returns the
path, or `nothing` when the menu is cancelled.
"""
function edit_agent(name::Union{Nothing,AbstractString} = nothing)
    files = filter(a -> a.path !== nothing, agents())
    name == _DEFAULT_AGENT && throw(ArgumentError("the built-in agent \"julia\" has no file"))
    a = name === nothing ? _pick_item(files, "agent") : _by_name(files, name, "agent")
    a === nothing && return nothing
    _EDITOR[](a.path)
    return a.path
end

"""
    edit_skill(name = nothing) -> Union{String,Nothing}

Open a skill's `SKILL.md` with `edit`; without a `name`, a terminal menu lists the skills.
Returns the path, or `nothing` when the menu is cancelled.
"""
function edit_skill(name::Union{Nothing,AbstractString} = nothing)
    ks = skills()
    k = name === nothing ? _pick_item(ks, "skill") : _by_name(ks, name, "skill")
    k === nothing && return nothing
    _EDITOR[](_skill_path(k))
    return _skill_path(k)
end
