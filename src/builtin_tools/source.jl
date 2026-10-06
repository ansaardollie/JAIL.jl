# Built-in source-definition tools ("inspect" group): julia_source_module, julia_source_struct,
# julia_source_method, julia_source_methods. Ported from the owner's JuliaSyntax-based helper
# (src_helpers_claude.jl). Names are resolved without `eval`, so these are always :low.

using JuliaSyntax: JuliaSyntax, @K_str, SyntaxNode, kind, children, sourcetext, sourcefile,
                   byte_range, source_location
using InteractiveUtils: functionloc

# --- Resolving names -------------------------------------------------------------------------

# Where names are looked up: the calling session's sandbox module (with julia_code_module =
# "sandbox"), then Main.
function _lookup_modules()
    ctx = tool_context()
    sandbox = ctx === nothing ? nothing : get(_SANDBOXES, ctx.session.id, nothing)
    return sandbox === nothing ? Module[Main] : Module[sandbox, Main]
end

_parse_name(s::AbstractString) = Meta.parse(strip(s); raise = true)

# A (qualified) name, or a type such as `Vector{Int}`, to its value; anything else is refused.
function _resolve_name(ex, mods = _lookup_modules())
    if ex isa Symbol
        for m in mods
            isdefined(m, ex) && return getglobal(m, ex)
        end
        throw(ArgumentError("`$ex` is not defined in Main"))
    elseif Meta.isexpr(ex, :., 2) && ex.args[2] isa QuoteNode && ex.args[2].value isa Symbol
        parent = _resolve_name(ex.args[1], mods)
        parent isa Module || throw(ArgumentError("`$(ex.args[1])` is not a module"))
        s = ex.args[2].value
        isdefined(parent, s) || throw(ArgumentError("`$s` is not defined in `$parent`"))
        return getglobal(parent, s)
    elseif Meta.isexpr(ex, :curly)
        params = map(ex.args[2:end]) do p
            p isa Union{Number,Char} ? p : p isa QuoteNode ? p.value : _resolve_name(p, mods)
        end
        return Core.apply_type(_resolve_name(ex.args[1], mods), params...)
    end
    throw(ArgumentError("`$ex` is not a name; give a name such as `sum`, `Base.sum` or `Vector{Int}`"))
end

_resolve_name(s::AbstractString) = _resolve_name(_parse_name(s))

function _resolve_kind(s::AbstractString, ::Type{T}, what::AbstractString) where {T}
    v = _resolve_name(s)
    v isa T || throw(ArgumentError("`$s` is a $(typeof(v)), not a $what"))
    return v
end

# --- Parsing source files (the helper's functions) -------------------------------------------

const _PARSED = Dict{String,Tuple{Float64,SyntaxNode}}()

function _parsed(file::AbstractString)
    t = mtime(file)
    cached = get(_PARSED, file, nothing)
    cached !== nothing && cached[1] == t && return cached[2]
    tree = JuliaSyntax.parseall(SyntaxNode, read(file, String); filename = file, ignore_errors = true)
    _PARSED[file] = (t, tree)
    return tree
end

function _collect_nodes!(out, node, pred)
    pred(node) && push!(out, node)
    cs = children(node)
    cs === nothing || foreach(c -> _collect_nodes!(out, c, pred), cs)
    return out
end

function _node_lines(node)
    sf, r = sourcefile(node), byte_range(node)
    return (source_location(sf, first(r))[1], source_location(sf, last(r))[1])
end

_first_child(n) = (cs = children(n); cs === nothing || isempty(cs) ? nothing : cs[1])

# f(x), f(x)::T, f(x) where T, f(x)::T where T ...
function _is_signature(n)
    k = kind(n)
    k == K"call" && return true
    if k == K"where" || k == K"::"
        c = _first_child(n)
        return c !== nothing && _is_signature(c)
    end
    return false
end

_is_method_def(n) = kind(n) == K"function" || kind(n) == K"macro" ||
    (kind(n) == K"=" && (c = _first_child(n); c !== nothing && _is_signature(c)))

_is_type_def(n) = kind(n) in (K"struct", K"abstract", K"primitive")

# `Foo`, `Foo{T}`, `Foo <: Bar`, `Foo{T} <: Bar{T}` -> "Foo"
function _type_def_name(n)
    c = _first_child(n)
    while c !== nothing && kind(c) in (K"<:", K"curly")
        c = _first_child(c)
    end
    return c === nothing ? nothing : sourcetext(c)
end

# Text of the innermost node matching `pred` that encloses `line` in `file`; prefers nodes whose
# first child (the signature) spans the line, since a method's line can be any signature line.
function _def_text(file::AbstractString, line::Integer, pred)
    cands = filter(n -> (l = _node_lines(n); l[1] <= line <= l[2]), _collect_nodes!(SyntaxNode[], _parsed(file), pred))
    isempty(cands) && return nothing
    in_sig(n) = (c = _first_child(n); c !== nothing && (l = _node_lines(c); l[1] <= line <= l[2]))
    sig_hits = filter(in_sig, cands)
    return sourcetext(last(isempty(sig_hits) ? cands : sig_hits))
end

_located(file, line, text) = string("# ", file, ":", line, "\n", text)

function _method_source(m::Method)
    file, line = functionloc(m)
    (file === nothing || !isfile(file)) && throw(ArgumentError(
        "the source of `$m` is not available (it was defined in the REPL, by execute_julia_code or by generated code)"))
    text = _def_text(file, line, _is_method_def)
    text === nothing && throw(ArgumentError(
        "no method definition encloses $file:$line (the method may be generated, e.g. by `@eval`)"))
    return _located(file, line, text)
end

# Julia files of the package (or Julia's base folder) a module comes from, its own file first.
function _module_files(M::Module)
    dir = pkgdir(M)
    if dir === nothing
        Base.moduleroot(M) in (Base, Core) || return String[]
        dir = joinpath(Sys.BINDIR, Base.DATAROOTDIR, "julia", "base")
    end
    return _dir_files(dir, pathof(M))
end

function _dir_files(dir, entry)
    files = String[]
    entry === nothing || push!(files, entry)
    isdir(dir) || return files
    for (d, _, fs) in walkdir(dir), f in fs
        endswith(f, ".jl") && push!(files, joinpath(d, f))
    end
    return unique!(files)
end

# Files of the package `name` without loading it: a copy loaded elsewhere (e.g. as a dependency),
# else the package the active environments resolve the name to. `nothing` if there is neither.
function _package_files(name::Symbol)
    for (id, m) in Base.loaded_modules
        id.name == string(name) && return _module_files(m)
    end
    id = Base.identify_package(string(name))
    entry = id === nothing ? nothing : Base.locate_package(id)
    entry === nothing && return nothing
    return _dir_files(dirname(dirname(entry)), entry)   # <pkg>/src/Name.jl
end

_root_name(ex) = ex isa Symbol ? ex : Meta.isexpr(ex, :., 2) ? _root_name(ex.args[1]) : nothing

# The first node matching `pred` in the files, skipping files that don't contain `needle`.
function _search_files(files, needle::AbstractString, pred)
    for file in files
        occursin(needle, read(file, String)) || continue
        hits = _collect_nodes!(SyntaxNode[], _parsed(file), pred)
        isempty(hits) || return _located(file, _node_lines(first(hits))[1], sourcetext(first(hits)))
    end
    return nothing
end

# --- Tools -----------------------------------------------------------------------------------

"""
    julia_source_method(signature)

Show the source code of the one method a call would run. Give the call signature with the
argument types, e.g. `Base.sum(::Vector{Int})` or `MyPkg.solve(::Problem, ::Float64)`; an
argument without a type means any type. The result starts with `# file:line`.

# Arguments
- `signature`: the function (qualified with its module if it isn't in Main) and argument types, e.g. `Base.sum(::Vector{Int})`
"""
function julia_source_method(signature::String)
    ex = _parse_name(signature)
    Meta.isexpr(ex, :call) || throw(ArgumentError(
        "`$signature` is not a call signature; write it like `Base.sum(::Vector{Int})`"))
    f = _resolve_name(ex.args[1])
    types = map(ex.args[2:end]) do a
        Meta.isexpr(a, :parameters) && throw(ArgumentError(
            "leave keyword arguments out of the signature; they don't select a method"))
        a isa Symbol && return Any
        T = Meta.isexpr(a, :(::), 1) ? a.args[1] : Meta.isexpr(a, :(::), 2) ? a.args[2] :
            throw(ArgumentError("write each argument as `::Type`, `name::Type` or `name`, not `$a`"))
        t = _resolve_name(T)
        t isa Type || throw(ArgumentError("`$T` is not a type"))
        t
    end
    return _method_source(which(f, Tuple{types...}))
end

"""
    julia_source_methods(name)

Show the source code of every method of a function (or every constructor of a type), each
starting with `# file:line`. Use julia_source_method instead when you know the argument types.

# Arguments
- `name`: the function, qualified with its module if it isn't in Main, e.g. `Base.sum` or `MyPkg.solve`
"""
function julia_source_methods(name::String)
    f = _resolve_name(name)
    ms = collect(methods(f))
    isempty(ms) && return "`$name` has no methods."
    seen, out = Set{Tuple{String,Int}}(), String[]
    for m in ms
        file, line = functionloc(m)
        key = (string(file), line)
        key in seen && continue      # methods made from one definition with optional arguments
        push!(seen, key)
        push!(out, try
            _method_source(m)
        catch e
            e isa ArgumentError || rethrow()
            string("# ", m, "\n# ", e.msg)
        end)
    end
    return join(out, "\n\n")
end

"""
    julia_source_struct(name)

Show the source code of a type definition: a `struct`, `mutable struct`, `abstract type` or
`primitive type`. The result starts with `# file:line`.

# Arguments
- `name`: the type, qualified with its module if it isn't in Main, e.g. `Base.Dict` or `MyPkg.Problem`; parameters are ignored
"""
function julia_source_struct(name::String)
    T = Base.unwrap_unionall(_resolve_kind(name, Type, "type"))
    T isa DataType || throw(ArgumentError("`$name` is a $(typeof(T)), not a struct or abstract/primitive type"))
    W, tname = T.name.wrapper, string(T.name.name)
    pred(n) = _is_type_def(n) && _type_def_name(n) == tname
    for m in methods(W)      # default constructors point at the type's definition
        file, line = functionloc(m)
        (file === nothing || !isfile(file)) && continue
        text = _def_text(file, line, pred)
        text === nothing || return _located(file, line, text)
    end
    found = _search_files(_module_files(parentmodule(W)), tname, pred)
    found === nothing && throw(ArgumentError(
        "could not find the definition of `$name` (types defined in the REPL have no source file)"))
    return found
end

"""
    julia_source_module(name)

Show the source code of a module definition, from `module Name` to its `end` (files it
`include`s are not expanded). The result starts with `# file:line`. A package (or a submodule
of one) is found even when it isn't loaded, if it is installed in the active environments.

# Arguments
- `name`: the module, e.g. `MyPkg` or `MyPkg.Submodule`
"""
function julia_source_module(name::String)
    ex = _parse_name(name)
    root = _root_name(ex)
    M = try
        _resolve_kind(name, Module, "module")
    catch e
        (e isa ArgumentError && root !== nothing && !any(m -> isdefined(m, root), _lookup_modules())) || rethrow()
        nothing
    end
    if M === nothing
        files = _package_files(root)
        files === nothing && throw(ArgumentError(
            "`$root` is not defined in Main and is not a package in the active environments"))
        mname = string(ex isa Symbol ? ex : ex.args[2].value)
    else
        M === Main && throw(ArgumentError("`Main` has no source file"))
        files, mname = _module_files(M), string(nameof(M))
    end
    pred(n) = kind(n) == K"module" && (c = _first_child(n); c !== nothing && sourcetext(c) == mname)
    found = _search_files(files, "module " * mname, pred)
    found === nothing && throw(ArgumentError(
        "could not find the source of `$name` (modules created in the REPL have no source file)"))
    return found
end

_builtin!(julia_source_method; group = "inspect", label = "Method source", security = :low, preview = "signature")
_builtin!(julia_source_methods; group = "inspect", label = "Method sources", security = :low, preview = "name")
_builtin!(julia_source_struct; group = "inspect", label = "Type source", security = :low, preview = "name")
_builtin!(julia_source_module; group = "inspect", label = "Module source", security = :low, preview = "name")
