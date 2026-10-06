# Skills in agent mode: the catalogue, activate_skill, read_skill_related_file, skill_<name> tools,
# argument substitution and user-invoked skills (run_skill!).

const _SKILL_CHOICES = Dict{UUID,Dict{String,String}}()   # session id => skill name => folder

# Model-visible skills for a turn, one per name: a remembered choice, else a menu once.
function _turn_skills(s::Session)
    visible = filter(k -> k.model_invocable, skills())
    out = Dict{String,Skill}()
    choices = get!(Dict{String,String}, _SKILL_CHOICES, s.id)
    for name in unique(k.name for k in visible)
        found = filter(k -> k.name == name, visible)
        if length(found) == 1
            out[name] = only(found)
            continue
        end
        i = findfirst(k -> k.dir == get(choices, name, nothing), found)
        k = i === nothing ? _by_name(found, name, "skill") : found[i]
        k === nothing && continue
        choices[name] = k.dir
        out[name] = k
    end
    return out
end

function _skill_catalogue(ks::Vector{Skill})
    io = IOBuffer()
    print(io, "## Skills\n\nBefore starting a task, check whether one of these skills covers it; if so, call ",
          "`activate_skill` with its name and follow the instructions it returns. Read the files a skill ",
          "refers to with `read_skill_related_file`.\n")
    for k in ks
        print(io, "\n- `", k.name, "`: ", k.description)
        k.when_to_use === nothing || print(io, " When to use: ", k.when_to_use)
    end
    return String(take!(io))
end

# `{{name}}` => the argument's text; `\{` and `\}` are literal braces; unknown names stay as written.
function _substitute(body::AbstractString, values::AbstractDict)
    io = IOBuffer()
    i = firstindex(body)
    while i <= lastindex(body)
        c = body[i]
        if c == '\\' && i < lastindex(body) && body[nextind(body, i)] in ('{', '}')
            print(io, body[nextind(body, i)])
            i = nextind(body, i, 2)
            continue
        end
        if c == '{' && startswith(SubString(body, i), "{{")
            m = match(r"\A\{\{\s*([A-Za-z_][A-Za-z0-9_-]*)\s*\}\}", SubString(body, i))
            if m !== nothing && haskey(values, m.captures[1])
                v = values[m.captures[1]]
                print(io, v === nothing ? "" : string(v))
                i = nextind(body, i, length(m.match))
                continue
            end
        end
        print(io, c)
        i = nextind(body, i)
    end
    return String(take!(io))
end

# Values for every argument: given ones, else the default, else nothing.
_argument_values(k::Skill, given::AbstractDict) =
    Dict{String,Any}(a.name => (haskey(given, a.name) && given[a.name] !== nothing ? given[a.name] : a.default)
                     for a in k.arguments)

function _activate!(turn::_AgentTurn, k::Skill)
    allowed = _ref_names(_resolve_tool_refs(k.allowed_tools))
    denied = _ref_names(_resolve_tool_refs(k.disallowed_tools))
    lock(turn.lock) do
        turn.active[k.name] = k
        union!(turn.auto, allowed)
        foreach(n -> turn.denied[n] = k.name, denied)
    end
    return nothing
end

_current_turn() = (t = _AGENT_TURN[]; t === nothing ?
    throw(ArgumentError("skills are only available in agent mode (`agent!` or the `&` REPL mode)")) : t)

function _related_files(dir::AbstractString)
    out = String[]
    for (root, _, files) in walkdir(dir)
        for f in files
            p = relpath(joinpath(root, f), dir)
            p == "SKILL.md" || push!(out, p)
        end
    end
    return sort!(out)
end

"""
    activate_skill(name)

Load a skill's instructions by name (one of the skills listed in the system instructions) and
follow them for the current task. Returns the skill's folder, the other files in it (read them
with `read_skill_related_file`) and its instructions.

# Arguments
- `name`: the skill's name
"""
function activate_skill(name::String)
    turn = _current_turn()
    k = get(turn.skills, name, nothing)
    k === nothing && throw(ArgumentError("no skill named \"$name\"; the skills are: " *
        join(sort!([x.name for x in values(turn.skills) if isempty(x.arguments)]), ", ")))
    isempty(k.arguments) || throw(ArgumentError("the skill \"$name\" takes arguments; call the tool `skill_$name` instead"))
    _activate!(turn, k)
    files = _related_files(k.dir)
    return string("Skill `", k.name, "` (folder ", Base.contractuser(k.dir), "; related files: ",
                  isempty(files) ? "none" : join(files, ", "), ")\n\n", k.body)
end

"""
    read_skill_related_file(skill, path)

Read a file that belongs to a skill, e.g. a reference or template the skill's instructions
mention. `path` is relative to the skill's folder.

# Arguments
- `skill`: the skill's name
- `path`: the file's path inside the skill's folder, e.g. `references/style.md`
"""
function read_skill_related_file(skill::String, path::String)
    turn = _current_turn()
    k = lock(() -> get(turn.active, skill, get(turn.skills, skill, nothing)), turn.lock)
    k === nothing && throw(ArgumentError("no skill named \"$skill\""))
    isempty(path) && throw(ArgumentError("the path is empty"))
    isabspath(path) && throw(ArgumentError("`$path` is absolute; give a path inside the skill's folder"))
    dir = normpath(k.dir)
    full = normpath(joinpath(dir, path))
    (_under(full, dir) && _under(_real_path(full), _real_path(dir))) ||
        throw(ArgumentError("`$path` is outside the skill's folder"))
    isfile(full) || throw(ArgumentError("no file `$path` in the skill \"$skill\""))
    _is_binary(full) && throw(ArgumentError("`$path` is not a text file"))
    return read(full, String)
end

# The `skill_<name>` tool of a skill with arguments; `params` are its argument names in call order.
struct _SkillTool <: Function
    skill::Skill
    params::Vector{String}
end

function (t::_SkillTool)(args...)
    turn = _current_turn()
    _activate!(turn, t.skill)
    return _substitute(t.skill.body, _argument_values(t.skill, Dict(zip(t.params, args))))
end

const _ARG_JULIA_TYPES = Dict(:string => String, :integer => Int, :number => Float64, :boolean => Bool)

const _SKILL_TOOL_PREFIX = "skill_"

function _skill_tool_spec(k::Skill)
    args = [filter(a -> a.required, k.arguments); filter(a -> !a.required, k.arguments)]
    params = ToolParameter[]
    for a in args
        T = _ARG_JULIA_TYPES[a.type]
        desc = isempty(a.description) ? a.hint : a.hint === nothing ? a.description : string(a.description, " (e.g. ", a.hint, ")")
        push!(params, ToolParameter(a.name, T, _json_schema(T, Type[]), desc, a.required))
    end
    desc = k.when_to_use === nothing ? k.description : string(k.description, " When to use: ", k.when_to_use)
    name = _SKILL_TOOL_PREFIX * k.name
    return ToolSpec(name, desc, params, _SkillTool(k, [a.name for a in args]), "skills", name, :low,
                    nothing, false)
end

const _CORE_SKILL_SPECS = ToolSpec[]

function _core_skill_specs()
    isempty(_CORE_SKILL_SPECS) && append!(_CORE_SKILL_SPECS, [
        _tool_spec(activate_skill; group = "skills", label = "Activate skill", security = :low,
                   preview = :name, concurrent = false),
        _tool_spec(read_skill_related_file; group = "skills", label = "Read skill file", security = :low,
                   preview = [:skill, :path])])
    return _CORE_SKILL_SPECS
end

# activate_skill with its `name` limited to the catalogue.
function _activate_spec(catalogue::Vector{Skill})
    t = _core_skill_specs()[1]
    p = only(t.parameters)
    schema = merge(p.schema, Dict{String,Any}("enum" => [k.name for k in catalogue]))
    return ToolSpec(t.name, t.description, [ToolParameter(p.name, p.type, schema, p.description, p.required)],
                    t.f, t.group, t.label, t.security, t.preview, t.concurrent)
end

const _WARNED_SKILL_NAMES = Set{String}()

# (loaded, deferred) extra tools of a turn: the two skill tools when any skill is model-visible,
# and a deferred `skill_<name>` per skill with arguments.
function _skill_specs(sks::Dict{String,Skill}, catalogue::Vector{Skill})
    isempty(sks) && return ToolSpec[], ToolSpec[]
    loaded = ToolSpec[]
    isempty(catalogue) || push!(loaded, _activate_spec(catalogue))
    push!(loaded, _core_skill_specs()[2])
    deferred = ToolSpec[]
    for k in sort!(collect(values(sks)); by = k -> k.name)
        isempty(k.arguments) && continue
        name = _SKILL_TOOL_PREFIX * k.name
        if !occursin(_TOOL_NAME, name)
            name in _WARNED_SKILL_NAMES || @warn "JAIL: the skill \"$(k.name)\" can't be a tool (`$name` is not a valid tool name of at most 64 characters)"
            push!(_WARNED_SKILL_NAMES, name)
            continue
        end
        push!(deferred, _skill_tool_spec(k))
    end
    return loaded, deferred
end

# --- User-invoked skills ---------------------------------------------------------------------

# Words of a `/skill` line: spaces separate, "…" and '…' group (quotes removed).
function _split_args(line::AbstractString)
    out, buf, quote_char, started = String[], IOBuffer(), nothing, false
    for c in line
        if quote_char !== nothing
            c == quote_char ? (quote_char = nothing) : print(buf, c)
        elseif c in ('"', '\'')
            quote_char, started = c, true
        elseif isspace(c)
            started && (push!(out, String(take!(buf))); started = false)
        else
            print(buf, c); started = true
        end
    end
    quote_char === nothing || throw(ArgumentError("unclosed $(quote_char) quote"))
    started && push!(out, String(take!(buf)))
    return out
end

function _convert_arg(a::SkillArgument, x)
    a.type === :string && return string(x)
    x isa AbstractString || return a.type === :boolean ? (x isa Bool ? x : _bad_arg(a, x)) :
                                                         a.type === :integer ? (x isa Integer ? Int(x) : _bad_arg(a, x)) :
                                                         (x isa Real ? Float64(x) : _bad_arg(a, x))
    s = lowercase(strip(x))
    if a.type === :boolean
        s in ("true", "yes", "y") && return true
        s in ("false", "no", "n") && return false
    elseif a.type === :integer
        v = tryparse(Int, s); v === nothing || return v
    else
        v = tryparse(Float64, s); v === nothing || return v
    end
    return _bad_arg(a, x)
end
_bad_arg(a, x) = throw(ArgumentError("argument `$(a.name)` must be a$(a.type === :integer ? "n" : "") $(a.type), got $(repr(x))"))

# Prompts on the terminal for one argument; empty input = default (optional) or asks again.
function _prompt_arg(a::SkillArgument; io::IO = stdout, input::IO = stdin)
    while true
        if a.type === :boolean && input isa Base.TTY
            i = _pick(_menu_terminal(), string(a.name, isempty(a.description) ? "" : ": " * a.description),
                      ["true", "false"])
            i === nothing && throw(InterruptException())
            return i == 1
        end
        printstyled(io, a.name; color = :cyan, bold = true)
        isempty(a.description) || print(io, " (", a.description, ")")
        a.hint === nothing || printstyled(io, " e.g. ", a.hint; color = :light_black)
        a.default === nothing || printstyled(io, " [default: ", a.default, "]"; color = :light_black)
        a.required || a.default !== nothing || printstyled(io, " [optional]"; color = :light_black)
        print(io, ": ")
        text = strip(readline(input))
        if isempty(text)
            a.required || return a.default
            println(io, "  `", a.name, "` is required.")
            continue
        end
        try
            return _convert_arg(a, text)
        catch e
            e isa ArgumentError || rethrow()
            println(io, "  ", e.msg)
        end
    end
end

# The user message for a user-invoked skill: values from `args` (positional, in front matter
# order), the rest prompted.
function _skill_prompt(k::Skill, args; prompt_missing::Bool = true)
    if isempty(k.arguments)
        extra = join(string.(args), " ")
        return isempty(strip(extra)) ? k.body : string(rstrip(k.body), "\n\n", extra)
    end
    length(args) > length(k.arguments) && throw(ArgumentError(
        "the skill \"$(k.name)\" takes $(length(k.arguments)) arguments ($(join((a.name for a in k.arguments), ", "))), got $(length(args))"))
    given = Dict{String,Any}()
    for (a, x) in zip(k.arguments, args)
        given[a.name] = _convert_arg(a, x)
    end
    # With some arguments given, only missing required ones are asked for; with none, every one.
    for a in k.arguments[length(args)+1:end]
        prompt_missing && (isempty(args) || a.required) || continue
        given[a.name] = _prompt_arg(a)
    end
    missing_names = [a.name for a in k.arguments if a.required && get(given, a.name, nothing) === nothing]
    isempty(missing_names) || throw(ArgumentError("missing required argument(s): $(join(missing_names, ", "))"))
    return _substitute(k.body, _argument_values(k, given))
end

_user_skills() = filter(k -> k.user_invocable, skills())

"""
    run_skill!(session::Session, name, args...; kwargs...) -> AssistantMessage
    run_skill!(name, args...; kwargs...)

Run the skill `name` (see [`skills`](@ref)) as the next [`agent!`](@ref) turn of the session (or
the [`active_session`](@ref)): its instructions, with each `{{argument}}` replaced, are sent as
the prompt, and the skill is active for the turn (its `allowed-tools` run without asking, its
`disallowed-tools` are refused). `args` fill the skill's `arguments` in order. With no `args`,
each argument is asked for on the terminal (empty input keeps an optional argument's default);
with some, only missing required ones are asked for. For a skill without arguments, `args` are
added after its instructions. `kwargs` are passed to `agent!`.
This is what `/name args...` does in the `&` REPL mode.

```julia
run_skill!(s, "review", "src/chat.jl", 2)
```
"""
function run_skill!(s::Session, name::AbstractString, args...; kwargs...)
    k = _by_name(_user_skills(), name, "user-invocable skill")
    k === nothing && return nothing
    prompt = _skill_prompt(k, args)
    turn = _agent_turn(s)
    _activate!(turn, k)
    return _agent!(s, prompt, turn; kwargs...)
end
run_skill!(name::AbstractString, args...; kwargs...) = run_skill!(active_session(), name, args...; kwargs...)
