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

function _tool_spec(f::Function; group = _DEFAULT_GROUP, label = nothing)
    name = _tool_name(f)
    group, label = _group_name(group), _label(f, label)
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
    return ToolSpec(name, description, params, f, group, label)
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
    register_tool!(f::Function; group = "global", label = nothing) -> ToolSpec

Make `f` available to models as a tool and return its [`ToolSpec`](@ref). Registering a name
again replaces the earlier tool.

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
register_tool!(get_weather; group = "web", label = "Weather forecast")
```

See also [`@tool`](@ref), [`tools`](@ref), [`unregister_tool!`](@ref).
"""
function register_tool!(f::Function; group::Union{AbstractString,Symbol} = _DEFAULT_GROUP,
                        label::Union{Nothing,AbstractString} = nothing)
    spec = _tool_spec(f; group, label)
    old = get(_TOOLS, spec.name, nothing)
    old === nothing || old.f === f ||
        @warn "Tool \"$(spec.name)\" from `$(parentmodule(old.f)).$(nameof(old.f))` is replaced by `$(parentmodule(f)).$(nameof(f))`"
    _TOOLS[spec.name] = spec
    return spec
end

"""
    @tool [group=name] [label="text"] f1 f2 ...

Register each named function as a tool with [`register_tool!`](@ref); returns their
[`ToolSpec`](@ref)s. Names may be qualified (`@tool MyPkg.search`). `group=` (a name or a
string) files them all under that group; `label=` sets the label of a single tool.

```julia
@tool get_weather search_docs
@tool group=shell execute_shell_command list_files
@tool label="Shell command" group=shell execute_shell_command
```
"""
macro tool(args...)
    opts, fs = Dict{Symbol,String}(), Any[]
    for a in args
        if Meta.isexpr(a, :(=), 2)
            k, v = a.args
            k in (:group, :label) || throw(ArgumentError(
                "unknown @tool option `$k`; the options are `group=` and `label=`"))
            haskey(opts, k) && throw(ArgumentError("@tool option `$k=` given twice"))
            v isa Union{Symbol,String} || throw(ArgumentError(
                "@tool `$k=` takes a name or a plain string, e.g. `@tool $k=shell f`, got `$v`"))
            opts[k] = string(v)
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

function _confirm_tools()
    v = _load_pref("confirm_tools", false)
    v isa Bool || throw(ArgumentError("Preference `confirm_tools` must be true or false, got $(repr(v))"))
    return v
end

function _confirm(c::ToolCall, io::IO = stdout, input::IO = stdin)
    printstyled(io, "Run ", _call_signature(c; n = 200), "? [y/N] "; color = :yellow)
    return lowercase(strip(readline(input))) in ("y", "yes")
end

# Never throws for problems the model can fix: they become error results it can read.
function _run_tool(c::ToolCall, specs::AbstractVector{ToolSpec}; confirm::Bool = false)
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
    confirm && !_confirm(c) && return err("The user declined to run this tool call.")
    value = try
        t.f(args...)
    catch e
        e isa InterruptException && rethrow()
        return err("`$(t.name)` threw an error: " * sprint(showerror, e))
    end
    return ToolResult(c.id, c.name, _result_text(value))
end
