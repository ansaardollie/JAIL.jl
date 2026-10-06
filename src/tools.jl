# Tool registry: reflect a Function into a ToolSpec (name, docstring, JSON Schema per argument).

const _TOOLS = Dict{String,ToolSpec}()

# Anthropic Tool.name pattern (artifacts/provider_docs/anthropic/api_spec.yaml#L5071-L5081).
const _TOOL_NAME = r"^[a-zA-Z0-9_-]{1,64}$"

function _tool_name(f::Function)
    name = replace(string(nameof(f)), "!" => "_bang")
    startswith(name, '#') &&
        throw(ArgumentError("anonymous functions can't be tools; define a named, documented function"))
    occursin(_TOOL_NAME, name) || throw(ArgumentError(
        "can't use `$(nameof(f))` as a tool: tool names must match $(_TOOL_NAME.pattern) " *
        "(after `!` → `_bang`); rename the function"))
    return name
end

_sig_params(m::Method) =
    Any[p isa TypeVar ? p.ub : p for p in Base.unwrap_unionall(m.sig).parameters[2:end]]

# The longest method; the others must be its prefixes (as `f(a, b = 1)` produces).
function _tool_method(f::Function)
    ms = collect(methods(f))
    isempty(ms) && throw(ArgumentError("can't use `$f` as a tool: it has no methods"))
    any(m -> m.isva, ms) &&
        throw(ArgumentError("can't use `$f` as a tool: varargs (`args...`) are not supported"))
    long = argmax(m -> m.nargs, ms)
    sig, names = _sig_params(long), Base.method_argnames(long)
    for m in ms
        s, n = _sig_params(m), Base.method_argnames(m)
        (s == sig[1:length(s)] && n == names[1:length(n)]) || throw(ArgumentError(
            "can't use `$f` as a tool: its $(length(ms)) methods have different signatures; " *
            "a tool needs one (positional arguments with defaults are fine)"))
    end
    return long, minimum(m -> m.nargs, ms) - 1
end

function _raw_docstring(f::Function)
    b = Docs.Binding(parentmodule(f), nameof(f))
    texts = String[]
    for mod in Docs.modules
        md = get(Docs.meta(mod), b, nothing)
        md === nothing && continue
        for sig in md.order
            ds = md.docs[sig]
            push!(texts, rstrip(isempty(ds.text) ? string(something(ds.object, "")) : join(ds.text)))
        end
    end
    return join(texts, "\n\n")
end

# -> (description, Dict(argument name => description)). Drops the leading indented signature
# block and moves the `# Arguments` section into the dict.
function _parse_docstring(text::AbstractString)
    lines = split(text, '\n')
    start = findfirst(l -> !(isempty(strip(l)) || startswith(l, "    ") || startswith(l, '\t')), lines)
    kept, args = SubString{String}[], Dict{String,String}()
    in_fence, in_args, current = false, false, nothing
    for l in (start === nothing ? SubString{String}[] : lines[start:end])
        startswith(lstrip(l), "```") && (in_fence = !in_fence)
        h = in_fence ? nothing : match(r"^#{1,6}\s+(.+?)\s*$", l)
        if h !== nothing
            in_args, current = lowercase(h[1]) == "arguments", nothing
            in_args && continue
        end
        if !in_args
            push!(kept, l)
        elseif (m = match(r"^\s*[-*+]\s+`([^`:=\s]+)[^`]*`\s*:?\s*(.*)$", l)) !== nothing
            current = String(m[1])
            args[current] = strip(m[2])
        elseif current !== nothing && !isempty(strip(l))
            args[current] = args[current] * " " * strip(l)
        end
    end
    return String(strip(join(kept, '\n'))), args
end

_schema(pairs...) = Dict{String,Any}(pairs...)

_json_schema(::Type{Any}, _) = _schema()
_json_schema(::Type{Bool}, _) = _schema("type" => "boolean")
_json_schema(::Type{<:Integer}, _) = _schema("type" => "integer")
_json_schema(::Type{<:Real}, _) = _schema("type" => "number")
_json_schema(::Type{<:Union{AbstractString,Symbol}}, _) = _schema("type" => "string")
_json_schema(T::Type{<:Enum}, _) = _schema("type" => "string", "enum" => [string(x) for x in instances(T)])
_json_schema(T::Type{<:AbstractVector}, seen) =
    _schema("type" => "array", "items" => _json_schema(eltype(T), seen))
_json_schema(t::TypeVar, seen) = _json_schema(t.ub, seen)

function _json_schema(T::Type{<:AbstractDict}, seen)
    K = keytype(T)
    K === Any || K <: Union{AbstractString,Symbol} ||
        throw(ArgumentError("dictionary keys must be strings or symbols, not $K"))
    return _schema("type" => "object", "additionalProperties" => _json_schema(valtype(T), seen))
end

_is_null(T) = T === Nothing || T === Missing

function _json_schema(T::Type, seen)
    _is_null(T) && return _schema("type" => "null")
    if T isa Union
        ts = Base.uniontypes(T)
        schemas = Any[_json_schema(t, seen) for t in ts if !_is_null(t)]
        nullable = any(_is_null, ts)
        # `{"type": [t, "null"]}` is the nullable form both OpenAI strict mode and Gemini document.
        if nullable && length(schemas) == 1 && get(schemas[1], "type", nothing) isa String
            return merge(schemas[1], _schema("type" => [schemas[1]["type"], "null"]))
        end
        nullable && push!(schemas, _schema("type" => "null"))
        return _schema("anyOf" => schemas)
    end
    (isconcretetype(T) && isstructtype(T) && fieldcount(T) > 0 && !(T <: Union{Function,Tuple})) ||
        throw(ArgumentError("$T has no JSON Schema mapping"))
    T in seen && throw(ArgumentError("$T is recursive"))
    push!(seen, T)
    names, types = fieldnames(T), fieldtypes(T)
    props = _schema((string(n) => _json_schema(t, seen) for (n, t) in zip(names, types))...)
    pop!(seen)
    required = [string(n) for (n, t) in zip(names, types) if !(t isa Union && any(_is_null, Base.uniontypes(t)))]
    return _schema("type" => "object", "properties" => props, "required" => required)
end

function _tool_spec(f::Function; group = _DEFAULT_GROUP, label = nothing, security = :medium,
                    preview = nothing, concurrent::Bool = true)
    name = _tool_name(f)
    group, label, security = _group_name(group), _label(f, label), _security_spec(security)
    m, nrequired = _tool_method(f)
    kws = unique!(reduce(vcat, (Base.kwarg_decl(x) for x in methods(f)); init = Symbol[]))
    description, arg_docs = _parse_docstring(_raw_docstring(f))
    params = ToolParameter[]
    for (i, (a, T)) in enumerate(zip(Base.method_argnames(m)[2:end], _sig_params(m)))
        arg = string(a)
        (isempty(arg) || startswith(arg, '#')) &&
            throw(ArgumentError("can't use `$f` as a tool: argument $i has no name"))
        schema = try
            _json_schema(T, Type[])
        catch e
            e isa ArgumentError || rethrow()
            throw(ArgumentError("can't use `$f` as a tool: argument `$arg::$T`: $(e.msg)"))
        end
        push!(params, ToolParameter(arg, T, schema, get(arg_docs, arg, nothing), i <= nrequired))
    end
    isempty(kws) || @warn "Keyword arguments of `$f` are not exposed to the model: $(join(kws, ", "))"
    isempty(description) && @warn "`$f` has no docstring; the model only sees its name and arguments"
    return ToolSpec(name, description, params, f, group, label, security, _preview_spec(preview, params),
                    concurrent)
end

const _SECURITY_LEVELS = (:low, :medium, :high)

_security_spec(f::Function) = f
function _security_spec(level::Union{Symbol,AbstractString})
    l = Symbol(level)
    l in _SECURITY_LEVELS || throw(ArgumentError(
        "tool security must be :low, :medium, :high or a function of the arguments, got $(repr(level))"))
    return l
end

_preview_spec(::Nothing, params) = nothing
_preview_spec(f::Function, params) = f
_preview_spec(name::Union{Symbol,AbstractString}, params) = only(_preview_spec([name], params))
function _preview_spec(names::AbstractVector, params)
    isempty(names) && throw(ArgumentError("tool preview: give at least one argument name"))
    out = String[]
    for n in names
        n isa Union{Symbol,AbstractString} || throw(ArgumentError(
            "tool preview must be an argument name, a vector of them, or a function; got $(repr(n))"))
        any(p -> p.name == string(n), params) || throw(ArgumentError(
            "tool preview: no argument `$n` (arguments: $(join((p.name for p in params), ", ")))"))
        push!(out, string(n))
    end
    return out
end

const _DEFAULT_GROUP = "global"
const _GROUP_NAME = r"^[A-Za-z0-9_.-]+$"

function _group_name(g::Union{AbstractString,Symbol})
    g = string(g)
    occursin(_GROUP_NAME, g) || throw(ArgumentError(
        "tool group $(repr(g)) is not a valid group name: use letters, digits, `_`, `-` or `.`"))
    return g
end

function _label(f::Function, label)
    label === nothing && return string(nameof(f))
    l = strip(string(label))
    isempty(l) && throw(ArgumentError("a tool label must not be empty"))
    return String(l)
end

# JSON Schema object for all of a tool's arguments; providers wrap it in their tool shape.
function _parameters_schema(t::ToolSpec)
    props = _schema()
    for p in t.parameters
        props[p.name] = p.description === nothing ? p.schema : merge(p.schema, _schema("description" => p.description))
    end
    return _schema("type" => "object", "properties" => props,
                   "required" => [p.name for p in t.parameters if p.required])
end

"""
    register_tool!(f::Function; group = "global", label = nothing, security = :medium,
                   preview = nothing, concurrent = true, load = false) -> ToolSpec

Make `f` available to models as a tool and return its [`ToolSpec`](@ref). Registering a name
again replaces the earlier tool. A registered tool is found by the model through tool search;
`load = true` also loads it in the [`active_session`](@ref), so the model sees it in full from
the next request (see [`load_tools!`](@ref)).

What the model sees comes from `f` itself:

- **name**: the function name, with `!` replaced by `_bang` (`save!` → `"save_bang"`).
- **description**: the function's docstring, minus its signature line and `# Arguments`.
- **parameters**: the positional arguments of its (single) method. Arguments with default values
  are optional. Argument types map to JSON Schema (`Integer`, `Real`, `Bool`, `AbstractString`,
  `Symbol`, enums, vectors, dictionaries, `Union{Nothing,T}`, structs); an untyped argument
  accepts any JSON value. Keyword arguments are ignored with a warning.
- **argument descriptions**: entries of the docstring's `# Arguments` section,
  ``- `city`: the city name``.

The model never sees these:

- **group**: files the tool under a group (letters, digits, `_`, `-`, `.`); `tools("shell")`
  lists a group and `set_tools!(s, tools("shell"))` gives a session just that group.
- **label**: how the tool's calls are shown in the `}` REPL mode and `chat!(...; stream = true)`;
  defaults to the function name as written (`save!`).
- **security**: `:low`, `:medium` (default) or `:high`, or a function that gets the call's
  arguments (every positional parameter of `f`, with `nothing` for optional ones the model left
  out) and returns one. Together with the
  Preference `tool_approval` it decides whether a call is confirmed first, unless the tool has an
  entry in [`tool_auto_approvals`](@ref) (see the Tools guide).
  A security function that throws or returns anything else counts as `:high`.
- **preview**: which arguments are shown with a call (in the confirmation prompt and the
  streamed `→ label` line): one argument name shows that argument's text as it is (for code or
  a shell command), a vector of names shows those as `name = value`, and a function (given the
  same arguments as a security function) returns the text to show. By default nothing is shown on the streamed line and the
  prompt shows every argument.
- **concurrent**: when the Preference `parallel_tool_calls` is on (the default) and a reply calls
  several tools, the approved calls run at the same time (on threads when Julia has more than
  one, else as tasks). `concurrent = false` makes this tool's calls run alone, one after
  another; use it for tools that read the terminal, redirect `stdout`, or change shared state.

```julia
\"\"\"
    get_weather(city, days = 3)

Get the weather forecast for a city.

# Arguments
- `city`: the city name, e.g. "Cape Town"
- `days`: number of days to forecast
\"\"\"
get_weather(city::String, days::Int = 3) = "Sunny for \$days days in \$city"

register_tool!(get_weather)
register_tool!(get_weather; group = "web", label = "Weather forecast", security = :low)

"Run a shell command."
run_shell(cmd::String) = read(`sh -c \$cmd`, String)
register_tool!(run_shell; security = :high, preview = :cmd)

"Append a line to the shared log."
log_line(text::String) = open(io -> println(io, text), "log.txt", "a")
register_tool!(log_line; concurrent = false)

"Read a text file."
read_text(path::String) = read(path, String)
register_tool!(read_text; security = path -> startswith(abspath(path), pwd() * "/") ? :low : :high)
```

See also [`@tool`](@ref), [`tools`](@ref), [`unregister_tool!`](@ref).
"""
function register_tool!(f::Function; group::Union{AbstractString,Symbol} = _DEFAULT_GROUP,
                        label::Union{Nothing,AbstractString} = nothing,
                        security::Union{Symbol,AbstractString,Function} = :medium,
                        preview::Union{Nothing,Symbol,AbstractString,AbstractVector,Function} = nothing,
                        concurrent::Bool = true, load::Bool = false)
    spec = _register!(_tool_spec(f; group, label, security, preview, concurrent))
    load && isassigned(_ACTIVE) && load_tools!(active_session(), spec)
    return spec
end

function _register!(spec::ToolSpec)
    f, old = spec.f, get(_TOOLS, spec.name, nothing)
    old === nothing || old.f === f ||
        @warn "Tool \"$(spec.name)\" from `$(parentmodule(old.f)).$(nameof(old.f))` is replaced by `$(parentmodule(f)).$(nameof(f))`"
    _TOOLS[spec.name] = spec
    return spec
end

"""
    @tool [group=name] [label="text"] [security=level] [preview=arg] [concurrent=false] [load=true] f1 f2 ...

Register each named function as a tool with [`register_tool!`](@ref); returns their
[`ToolSpec`](@ref)s. Names may be qualified (`@tool MyPkg.search`). `group=` (a name or a
string), `security=`, `preview=`, `concurrent=` and `load=` apply to every function named; `label=` sets the
label of a single tool. `load=true` also loads them in the active session.

- `security=` takes `low`, `medium` or `high`; any other name or expression is used as the
  security function (`security=shell_level`, `security=cmd -> ...`).
- `preview=` takes an argument name (`preview=cmd`), a vector of them (`preview=[path, mode]`),
  or an anonymous function (`preview=(path, mode) -> path`). For a named function use
  `register_tool!(f; preview = g)`, since a bare name here means an argument.

```julia
@tool get_weather search_docs
@tool group=shell execute_shell_command list_files
@tool label="Shell command" group=shell security=high preview=command execute_shell_command
```
"""
macro tool(args...)
    opts, fs = Dict{Symbol,Any}(), Any[]
    for a in args
        if Meta.isexpr(a, :(=), 2)
            k, v = a.args
            k in (:group, :label, :security, :preview, :concurrent, :load) || throw(ArgumentError(
                "unknown @tool option `$k`; the options are `group=`, `label=`, `security=`, `preview=`, `concurrent=` and `load=`"))
            haskey(opts, k) && throw(ArgumentError("@tool option `$k=` given twice"))
            opts[k] = _tool_option(Val(k), v)
        elseif a isa Symbol || Meta.isexpr(a, :.)
            push!(fs, a)
        else
            throw(ArgumentError(
                "@tool takes function names (e.g. `@tool get_weather MyPkg.search`), got " *
                (a isa Expr ? "a `$(a.head)` expression" : repr(a)) *
                ". Define and document the function first, then pass its name"))
        end
    end
    isempty(fs) && throw(ArgumentError("@tool needs at least one function name, e.g. `@tool get_weather`"))
    haskey(opts, :label) && length(fs) > 1 && throw(ArgumentError(
        "@tool `label=` labels a single tool; register the other functions separately"))
    reg = GlobalRef(@__MODULE__, :register_tool!)
    kw = Expr(:parameters, (Expr(:kw, k, v) for (k, v) in opts)...)
    return :($(GlobalRef(@__MODULE__, :ToolSpec))[$((Expr(:call, reg, kw, esc(f)) for f in fs)...)])
end

_literal_name(v) = v isa Union{Symbol,String} ? string(v) : v isa QuoteNode && v.value isa Symbol ? string(v.value) : nothing

function _tool_option(::Union{Val{:group},Val{:label}}, v)
    s = _literal_name(v)
    s === nothing && throw(ArgumentError("@tool `group=`/`label=` take a name or a plain string, got `$v`"))
    return s
end

function _tool_option(::Val{:security}, v)
    s = _literal_name(v)
    return s !== nothing && Symbol(s) in _SECURITY_LEVELS ? QuoteNode(Symbol(s)) : esc(v)
end

function _tool_option(::Val{:load}, v)
    v isa Bool || throw(ArgumentError("@tool `load=` takes `true` or `false`, got `$v`"))
    return v
end

function _tool_option(::Val{:concurrent}, v)
    v isa Bool || throw(ArgumentError("@tool `concurrent=` takes `true` or `false`, got `$v`"))
    return v
end

function _tool_option(::Val{:preview}, v)
    s = _literal_name(v)
    s === nothing || return s
    if Meta.isexpr(v, :vect)
        names = map(_literal_name, v.args)
        any(isnothing, names) && throw(ArgumentError("@tool `preview=[...]` takes argument names, got `$v`"))
        return :(String[$(names...)])
    end
    return esc(v)
end

"""
    tools() -> Vector{ToolSpec}
    tools(group::AbstractString) -> Vector{ToolSpec}

All registered tools, or those in `group`, sorted by name. Throws for a group with no tools.
"""
tools() = sort!(collect(values(_TOOLS)); by = t -> t.name)

function tools(group::Union{AbstractString,Symbol})
    g = string(group)
    ts = filter(t -> t.group == g, tools())
    isempty(ts) && throw(ArgumentError("no tools in group \"$g\" (groups: $(join(_tool_groups(), ", ")))"))
    return ts
end

_tool_groups() = sort!(unique(t.group for t in values(_TOOLS)))

# How calls of the tool `name` are shown; unregistered names show as they are.
_tool_label(name::AbstractString) = haskey(_TOOLS, name) ? _TOOLS[name].label : String(name)

"""
    unregister_tool!(name::AbstractString) -> ToolSpec
    unregister_tool!(f::Function) -> ToolSpec

Remove a tool from the registry and return it. Throws if no such tool is registered.
"""
function unregister_tool!(name::AbstractString)
    haskey(_TOOLS, name) || throw(ArgumentError("no tool named \"$name\" is registered"))
    return pop!(_TOOLS, name)
end
unregister_tool!(f::Function) = unregister_tool!(_tool_name(f))

# --- Running calls ---------------------------------------------------------------------------

_json_desc(x) = _short(JSON.json(x), 60)
_arg_error(T, x) = throw(ArgumentError("expected $T, got $(_json_desc(x))"))

# JSON value (from JSON.parse) -> a value of type T, following the _json_schema mapping.
_from_json(t::TypeVar, x) = _from_json(t.ub, x)
_from_json(::Type{Any}, x) = x
function _from_json(T::Type, x)
    x === nothing && return Nothing <: T ? nothing : _arg_error(T, x)
    if T isa Union
        for t in Base.uniontypes(T)
            _is_null(t) && continue
            try
                return _from_json(t, x)
            catch e
                e isa ArgumentError || rethrow()
            end
        end
        _arg_error(T, x)
    end
    T <: Bool && return x isa Bool ? x : _arg_error(T, x)
    x isa Bool && T <: Real && _arg_error(T, x)
    T <: Integer && return x isa Integer || (x isa Real && isinteger(x)) ? convert(T, x) : _arg_error(T, x)
    T <: Real && return x isa Real ? convert(T, x) : _arg_error(T, x)
    T === Symbol && return x isa AbstractString ? Symbol(x) : _arg_error(T, x)
    T <: AbstractString && return x isa AbstractString ? (isconcretetype(T) ? convert(T, x) : x) : _arg_error(T, x)
    if T <: Enum
        i = findfirst(v -> string(v) == x, instances(T))
        return i === nothing ? _arg_error(T, x) : instances(T)[i]
    end
    if T <: AbstractVector
        x isa AbstractVector || _arg_error(T, x)
        E = eltype(T)
        v = [_from_json(E, e) for e in x]
        return isconcretetype(T) ? convert(T, v) : convert(Vector{E isa TypeVar ? Any : E}, v)
    end
    if T <: AbstractDict
        x isa AbstractDict || _arg_error(T, x)
        K, V = keytype(T), valtype(T)
        return Dict{K,V}((K === Symbol ? Symbol(k) : k) => _from_json(V, v) for (k, v) in x)
    end
    if isconcretetype(T) && isstructtype(T) && x isa AbstractDict
        vals = map(fieldnames(T), fieldtypes(T)) do n, ft
            haskey(x, string(n)) ? _from_json(ft, x[string(n)]) :
            Nothing <: ft ? nothing : throw(ArgumentError("missing field `$n` of $T"))
        end
        return T(vals...)
    end
    return x isa T ? x : _arg_error(T, x)
end

# Positional arguments for the call; trailing optionals the model left out use Julia's defaults.
function _call_args(t::ToolSpec, args::AbstractDict)
    extra = setdiff(keys(args), (p.name for p in t.parameters))
    isempty(extra) || throw(ArgumentError(
        "unknown argument$(length(extra) > 1 ? "s" : "") $(join(("`$e`" for e in extra), ", ")); " *
        "expected $(join(("`$(p.name)`" for p in t.parameters), ", "))"))
    vals, skipped = Any[], nothing
    for p in t.parameters
        if haskey(args, p.name)
            skipped === nothing || throw(ArgumentError(
                "`$(p.name)` was given but the earlier optional `$skipped` was not; give `$skipped` too"))
            v = try
                _from_json(p.type, args[p.name])
            catch e
                e isa ArgumentError || rethrow()
                throw(ArgumentError("argument `$(p.name)`: $(e.msg)"))
            end
            push!(vals, v)
        elseif p.required
            throw(ArgumentError("missing required argument `$(p.name)`"))
        else
            skipped = something(skipped, p.name)
        end
    end
    return vals
end

_default_show(T) = which(show, Tuple{IO,T}).module === Base &&
                   which(show, Tuple{IO,MIME"text/plain",T}).module === Base

# Strings as they are; plain data as JSON; anything with its own `show` as its text/plain form.
_result_text(v::AbstractString) = String(v)
function _result_text(v)
    plain = v isa Union{Nothing,Number,Symbol,AbstractDict,AbstractVector,Tuple,NamedTuple} ||
            (isstructtype(typeof(v)) && !(v isa Union{Function,Module,Type,IO}) && _default_show(typeof(v)))
    if plain
        try
            return JSON.json(v)
        catch
        end
    end
    return repr(MIME"text/plain"(), v)
end

const _APPROVAL_MODES = ("all", "auto", "none", "yolo")
const _WARNED_CONFIRM_TOOLS = Ref(false)

function _approval_mode(mode)
    m = mode isa Symbol ? String(mode) : mode
    m isa AbstractString && m in _APPROVAL_MODES || throw(ArgumentError(
        "tool approval must be \"all\", \"auto\", \"none\" or \"yolo\", got $(repr(mode))"))
    return String(m)
end

"""
    tool_approval() -> String

The active tool approval mode, from the Preference `tool_approval` (default `"auto"`): which
security levels are confirmed on the terminal before a tool call runs.

| Confirm first? | `"all"` | `"auto"` | `"none"` | `"yolo"` |
|---|---|---|---|---|
| `:low` | yes | no | no | no |
| `:medium` | yes | yes | no | no |
| `:high` | yes | yes | yes | no |

See also [`set_tool_approval!`](@ref), [`needs_confirmation`](@ref), and
[`tool_auto_approvals`](@ref) for per-tool overrides.
"""
function tool_approval()
    if !_WARNED_CONFIRM_TOOLS[] && _load_pref("confirm_tools") !== nothing
        _WARNED_CONFIRM_TOOLS[] = true
        @warn "The Preference `confirm_tools` is no longer read; set `tool_approval` to \"all\", \"auto\", \"none\" or \"yolo\" (default \"auto\") instead"
    end
    v = _load_pref("tool_approval", "auto")
    v isa AbstractString && v in _APPROVAL_MODES || throw(ArgumentError(
        "Preference `tool_approval` must be \"all\", \"auto\", \"none\" or \"yolo\", got $(repr(v))"))
    return String(v)
end

"""
    set_tool_approval!(mode) -> String

Save the tool approval mode (`"all"`, `"auto"`, `"none"` or `"yolo"`, or the same as a Symbol)
to the Preference `tool_approval`; `nothing` removes it, going back to `"auto"`. Takes effect
from the next tool call. Returns the active mode.
"""
function set_tool_approval!(mode::Union{Nothing,AbstractString,Symbol})
    mode === nothing ? _delete_pref!("tool_approval") : _save_pref!("tool_approval", _approval_mode(mode))
    return tool_approval()
end

# Index into _SECURITY_LEVELS from which each mode asks first ("yolo" never asks).
const _CONFIRM_FROM = Dict("all" => 1, "auto" => 2, "none" => 3, "yolo" => 4)
_needs_confirmation(level::Symbol, mode::AbstractString) =
    findfirst(==(level), _SECURITY_LEVELS) >= _CONFIRM_FROM[mode]

# Security and preview functions get every parameter: `nothing` for optionals the model left out.
_padded(t::ToolSpec, args) = Any[args; fill(nothing, length(t.parameters) - length(args))]

function _security_level(t::ToolSpec, args)
    t.security isa Symbol && return t.security
    level = try
        t.security(_padded(t, args)...)
    catch e
        e isa InterruptException && rethrow()
        @warn "JAIL: the security function of tool `$(t.name)` threw; the call counts as :high" exception = e
        return :high
    end
    level isa Symbol && level in _SECURITY_LEVELS && return level
    @warn "JAIL: the security function of tool `$(t.name)` returned $(repr(level)), not :low, :medium or :high; the call counts as :high"
    return :high
end

_preview_value(v::AbstractString) = String(v)
_preview_value(v) = repr(v)

# `args` are the converted positional arguments; trailing optionals the model left out are absent.
function _preview_text(t::ToolSpec, args)
    p, n = t.preview, length(args)
    p === nothing && return nothing
    if p isa String
        i = findfirst(q -> q.name == p, t.parameters)
        return i <= n ? _preview_value(args[i]) : nothing
    elseif p isa Vector{String}
        parts = [string(q.name, " = ", repr(args[i])) for (i, q) in enumerate(t.parameters) if i <= n && q.name in p]
        return isempty(parts) ? nothing : join(parts, ", ")
    end
    try
        return _preview_value(p(_padded(t, args)...))
    catch e
        e isa InterruptException && rethrow()
        @warn "JAIL: the preview function of tool `$(t.name)` threw" exception = e
        return nothing
    end
end

# The registered tool and converted arguments of a call, as the tool loop would run it.
function _spec_and_args(c::ToolCall)
    t = get(_TOOLS, c.name, nothing)
    t === nothing && throw(ArgumentError("no tool named \"$(c.name)\" is registered"))
    haskey(c.arguments, _BAD_ARGUMENTS) &&
        throw(ArgumentError("the arguments were not a valid JSON object: $(c.arguments[_BAD_ARGUMENTS])"))
    return t, _call_args(t, c.arguments)
end

"""
    security_level(call::ToolCall) -> Symbol

The security level (`:low`, `:medium` or `:high`) of a call to a registered tool, as the tool
loop computes it: the tool's fixed level, or its security function applied to the call's
arguments (converted from JSON; `nothing` for optional arguments the call leaves out). Throws an
`ArgumentError` for an unregistered tool or invalid arguments.

```julia
security_level(ToolCall("c1", "shell", Dict("cmd" => "ls -la")))   # :low, say
```
"""
security_level(c::ToolCall) = _security_level(_spec_and_args(c)...)

"""
    needs_confirmation(call::ToolCall; approval = tool_approval()) -> Bool

Whether the tool loop would ask on the terminal before running `call`: its entry in
[`tool_auto_approvals`](@ref) if it has one, else its [`security_level`](@ref) under the
`approval` mode (see [`tool_approval`](@ref)). Always `false` for the built-in `ask_user`,
which is never confirmed.
"""
needs_confirmation(c::ToolCall; approval::Union{AbstractString,Symbol} = tool_approval()) =
    _confirmation_needed(_spec_and_args(c)..., _approval_mode(approval))

"""
    tool_auto_approvals() -> Dict{String,Any}

The Preference `tool_auto_approvals`: per-tool overrides of the confirmation rule. Keys are tool
names for tools in the `"global"` group, and group names for the others, holding either a table
of tool names or a single `true`/`false` for the whole group:

```toml
[JAIL.tool_auto_approvals]
get_weather = true         # never asks, whatever its security level or `tool_approval`
shell.run_shell = false    # always asks, even with tool_approval = "yolo"
files = true               # every tool in the "files" group
```

Tools not listed follow their security level and [`tool_approval`](@ref). The built-in
`ask_user` is never confirmed, whatever its entry says. See also
[`set_tool_auto_approval!`](@ref).
"""
function tool_auto_approvals()
    v = _load_pref("tool_auto_approvals", nothing)
    v === nothing && return Dict{String,Any}()
    v isa AbstractDict || throw(ArgumentError("Preference `tool_auto_approvals` must be a table, got $(repr(v))"))
    out = Dict{String,Any}()
    for (k, x) in v
        if x isa Bool
            out[k] = x
        elseif x isa AbstractDict && all(y -> y isa Bool, values(x))
            out[k] = Dict{String,Bool}(x)
        else
            throw(ArgumentError("Preference `tool_auto_approvals.$k` must be true, false, or a table of tool names = true/false; got $(repr(x))"))
        end
    end
    return out
end

# true: never ask; false: always ask; nothing: the security level and approval mode decide.
function _auto_approval(t::ToolSpec, table = tool_auto_approvals())
    if t.group == _DEFAULT_GROUP
        v = get(table, t.name, nothing)
        return v isa Bool ? v : nothing
    end
    g = get(table, t.group, nothing)
    g isa Bool && return g
    return g isa AbstractDict ? get(g, t.name, nothing) : nothing
end

function _confirmation_needed(t::ToolSpec, args, mode::AbstractString)
    _never_confirm(t) && return false
    a = _auto_approval(t)
    return a === nothing ? _needs_confirmation(_security_level(t, args), mode) : !a
end

function _registered_tool(x::Union{AbstractString,Function})
    name = x isa Function ? _tool_name(x) : String(x)
    haskey(_TOOLS, name) || throw(ArgumentError("no tool named \"$name\" is registered"))
    return _TOOLS[name]
end

"""
    set_tool_auto_approval!(tool, value::Union{Bool,Nothing}) -> Dict{String,Any}

Save one entry of the Preference [`tool_auto_approvals`](@ref): `true` runs the tool's calls
without asking, `false` always asks, `nothing` removes the entry. `tool` is a registered tool's
name, function or [`ToolSpec`](@ref), or `"group:<group>"` for a whole group (not `"global"`).
Returns the updated table. Answering `a` at a confirmation prompt does
`set_tool_auto_approval!(tool, true)`.

```julia
set_tool_auto_approval!(get_weather, true)
set_tool_auto_approval!("group:shell", false)
set_tool_auto_approval!(get_weather, nothing)
```
"""
function set_tool_auto_approval!(tool::Union{AbstractString,Function,ToolSpec}, value::Union{Nothing,Bool})
    table = tool_auto_approvals()
    if tool isa AbstractString && startswith(tool, "group:")
        g = _group_name(tool[length("group:")+1:end])
        g == _DEFAULT_GROUP && throw(ArgumentError(
            "tools of the \"$g\" group are approved one by one; name the tool instead"))
        value === nothing ? delete!(table, g) : (table[g] = value)
    else
        t = tool isa ToolSpec ? tool : _registered_tool(tool)
        if t.group == _DEFAULT_GROUP
            get(table, t.name, nothing) isa AbstractDict && throw(ArgumentError(
                "tool_auto_approvals.$(t.name) holds the group \"$(t.name)\"; rename the tool or the group"))
            value === nothing ? delete!(table, t.name) : (table[t.name] = value)
        else
            g = get(table, t.group, nothing)
            g isa Bool && throw(ArgumentError(
                "the whole group \"$(t.group)\" is set to $g; change it with " *
                "`set_tool_auto_approval!(\"group:$(t.group)\", nothing)` first"))
            sub = g isa AbstractDict ? g : Dict{String,Bool}()
            value === nothing ? delete!(sub, t.name) : (sub[t.name] = value)
            isempty(sub) ? delete!(table, t.group) : (table[t.group] = sub)
        end
    end
    isempty(table) ? _delete_pref!("tool_auto_approvals") : _save_pref!("tool_auto_approvals", table)
    return tool_auto_approvals()
end

"""
    tool_preview(call::ToolCall) -> Union{String,Nothing}

The text shown for `call` in a confirmation prompt and under its streamed `→ label` line, from
the tool's `preview` (see [`register_tool!`](@ref)); `nothing` when the tool has no preview.
"""
tool_preview(c::ToolCall) = _preview_text(_spec_and_args(c)...)

# A registered call's preview, or nothing (no preview, or arguments that don't convert).
function _call_preview(c::ToolCall)
    t = get(_TOOLS, c.name, nothing)
    (t === nothing || t.preview === nothing) && return nothing
    try
        return tool_preview(c)
    catch e
        e isa ArgumentError || rethrow()
        return nothing
    end
end

_print_preview(io::IO, text::AbstractString) = println(io, replace(rstrip(text), r"^"m => "    "))

# Input sent before a prompt appeared (e.g. an extra line run from the editor) must not answer it.
function _discard_pending_input(io::IO)
    io isa Base.TTY || return nothing
    Base.start_reading(io)
    sleep(0.02)    # lets bytes already sent arrive
    n = bytesavailable(io)
    n > 0 && read(io, n)
    return nothing
end

# `shown`: the preview was just printed under the call's streamed line, so don't repeat it.
# Returns :yes, :no or :always.
function _confirm(c::ToolCall, t::ToolSpec, args, level::Symbol; shown::Bool = false,
                  io::IO = stdout, input::IO = stdin)
    preview = _preview_text(t, args)
    ask = "run it? [y/N/a = always] "
    if preview === nothing
        printstyled(io, _call_signature(c; n = 200), " [", level, "]: ", ask; color = :yellow)
    elseif shown
        printstyled(io, t.label, " [", level, "]: ", ask; color = :yellow)
    else
        printstyled(io, t.label, " [", level, "]\n"; color = :yellow)
        _print_preview(io, preview)
        printstyled(io, uppercasefirst(ask); color = :yellow)
    end
    _discard_pending_input(input)
    answer = lowercase(strip(readline(input)))
    return answer in ("y", "yes") ? :yes : answer in ("a", "always") ? :always : :no
end

# Never throws for problems the model can fix: they become error results it can read.
# `before_confirm(c)` runs just before the user is asked; it returns true when it has already
# shown the call's preview.
function _run_tool(c::ToolCall, specs::AbstractVector{ToolSpec}; approval::AbstractString,
                   before_confirm = nothing)
    x = _prepare_tool(c, specs; approval, before_confirm)
    return x isa ToolResult ? x : _invoke_tool(c, x...)
end

# Checks and confirms a call: (spec, args) to run, or the error result to send instead.
function _prepare_tool(c::ToolCall, specs::AbstractVector{ToolSpec}; approval::AbstractString,
                       before_confirm = nothing)
    err(msg) = ToolResult(c.id, c.name, msg; is_error = true)
    i = findfirst(t -> t.name == c.name, specs)
    i === nothing && return err("Unknown tool `$(c.name)`. Available tools: " *
                                (isempty(specs) ? "none" : join((t.name for t in specs), ", ")))
    haskey(c.arguments, _BAD_ARGUMENTS) &&
        return err("The arguments were not a valid JSON object: $(c.arguments[_BAD_ARGUMENTS])")
    t = specs[i]
    args = try
        _call_args(t, c.arguments)
    catch e
        e isa ArgumentError || rethrow()
        return err("Invalid arguments for `$(t.name)`: $(e.msg)")
    end
    auto = _never_confirm(t) ? true : _auto_approval(t)
    level = auto === true ? :low : _security_level(t, args)
    if auto === false || (auto === nothing && _needs_confirmation(level, approval))
        shown = before_confirm !== nothing && before_confirm(c) === true
        answer = _confirm(c, t, args, level; shown)
        answer === :no && return err("The user declined to run this tool call.")
        if answer === :always
            try
                set_tool_auto_approval!(t, true)
            catch e
                e isa InterruptException && rethrow()
                @warn "JAIL: could not save the auto-approval for `$(t.name)`" exception = e
            end
        end
    end
    return t, args
end

function _invoke_tool(c::ToolCall, t::ToolSpec, args)
    value = try
        t.f(args...)
    catch e
        e isa InterruptException && rethrow()
        return ToolResult(c.id, c.name, "`$(t.name)` threw an error: " * sprint(showerror, e); is_error = true)
    end
    return ToolResult(c.id, c.name, _result_text(value))
end
