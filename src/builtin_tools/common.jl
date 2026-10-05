# Shared pieces of the built-in tools: the workspace path rules, child processes, the tool context
# and opting in. The tools themselves live in the other files of this folder.

using Base.ScopedValues: ScopedValue, with

# --- Tool context ----------------------------------------------------------------------------

"""
    ToolContext

Where a tool call comes from: the [`Session`](@ref) whose turn is running (`session`) and the
[`ToolCall`](@ref) being run (`call`). Read it with [`tool_context`](@ref) inside a tool.
"""
struct ToolContext
    session::Session
    call::ToolCall
end

const _TOOL_CONTEXT = ScopedValue{Union{Nothing,ToolContext}}(nothing)

# Called by tools that read the terminal, so a REPL mode can clear its status line first.
const _PROMPT_HOOK = ScopedValue{Any}(nothing)

"""
    tool_context() -> Union{ToolContext,Nothing}

The [`ToolContext`](@ref) of the tool call being run, or `nothing` outside one. Lets a tool
see the session and call that asked for it:

```julia
"Name of the session that called this tool."
session_name() = tool_context().session.name
register_tool!(session_name)
```
"""
tool_context() = _TOOL_CONTEXT[]

_before_prompt() = (h = _PROMPT_HOOK[]; h === nothing || h(); nothing)

# --- Paths -----------------------------------------------------------------------------------

_workspace_root() = pwd()

function _string_list_pref(key::AbstractString)
    v = _load_pref(key, String[])
    v isa AbstractVector && all(x -> x isa AbstractString, v) || throw(ArgumentError(
        "Preference `$key` must be a list of strings, got $(repr(v))"))
    return String[x for x in v]
end

_under(path, dir) = (p = splitpath(path); d = splitpath(dir); length(p) >= length(d) && p[1:length(d)] == d)

const _DEFAULT_PROTECTED = ("LocalPreferences.toml", "Project.toml", ".git")

# Absolute protected paths: the defaults and the `protected_paths` Preference, relative to `root`.
function _protected_paths(root::AbstractString = _workspace_root())
    entries = [collect(_DEFAULT_PROTECTED); _string_list_pref("protected_paths")]
    out = [normpath(joinpath(root, e)) for e in entries if !isempty(strip(e))]
    push!(out, _storage_dir())
    return out
end

# Where a path given to a built-in tool points. `inside` is false for an absolute path outside the
# workspace root, a path whose first part is `..` (after `normpath`), or a path through a symlink
# below the root.
struct _PathInfo
    path::String
    inside::Bool
    protected::Bool
end

function _resolve(path::AbstractString; root::AbstractString = _workspace_root())
    root = normpath(root)
    isempty(path) && throw(ArgumentError("the path is empty"))
    if isabspath(path)
        abs = normpath(path)
        inside = _under(abs, root)
    else
        rel = normpath(path)
        parts = splitpath(rel)
        inside = isempty(parts) || first(parts) != ".."
        abs = normpath(joinpath(root, rel))
    end
    if inside
        cur = root
        for part in splitpath(relpath(abs, root))
            part == "." && continue
            cur = joinpath(cur, part)
            islink(cur) && (inside = false; break)
        end
    end
    protected = any(p -> _under(abs, p), _protected_paths(root))
    return _PathInfo(abs, inside, protected)
end

# Security functions: outside the root is always :high; protected paths are :high for writes.
_read_level(path, _...) = _resolve(path).inside ? :low : :high
function _write_level(path, base::Symbol = :medium)
    r = _resolve(path)
    return !r.inside || r.protected ? :high : base
end

# --- Child processes -------------------------------------------------------------------------

const _SECRET_SUFFIXES = ("_KEY", "_CREDENTIALS", "_CREDENTIAL")

# ENV for child processes, without secrets: names ending in a _SECRET_SUFFIXES entry or listed in
# the `scrub_env_vars` Preference, compared case-insensitively.
function _child_env()
    extra = Set(uppercase.(_string_list_pref("scrub_env_vars")))
    keep(k) = (K = uppercase(k); !(K in extra || any(s -> endswith(K, s), _SECRET_SUFFIXES)))
    return Dict{String,String}(k => v for (k, v) in ENV if keep(k))
end

# Runs `cmd` in the workspace root with no stdin, the scrubbed environment and stdout and stderr
# combined; kills it after `timeout` seconds.
function _run_cmd(cmd::Cmd; timeout::Union{Nothing,Real} = nothing, dir::AbstractString = _workspace_root())
    cmd = setenv(cmd, _child_env(); dir)
    pipe, buf = Pipe(), IOBuffer()
    p = run(pipeline(cmd; stdin = devnull, stdout = pipe, stderr = pipe); wait = false)
    close(pipe.in)
    reader = @async try
        while !eof(pipe)
            write(buf, readavailable(pipe))
        end
    catch e
        e isa Base.IOError || rethrow()
    end
    timed_out = Ref(false)
    timer = timeout === nothing ? nothing :
        Timer(_ -> (timed_out[] = true; process_running(p) && kill(p)), timeout)
    try
        wait(p)
    finally
        timer === nothing || close(timer)
        process_running(p) && kill(p)
    end
    # A grandchild that outlived a killed process may still hold the pipe open.
    timed_out[] && close(pipe)
    wait(reader)
    return (output = String(take!(buf)), exitcode = p.exitcode, signal = p.termsignal, timed_out = timed_out[])
end

# --- Opting in -------------------------------------------------------------------------------

const _BUILTIN_GROUPS = ("read", "inspect", "edit", "execute", "web", "interact")

# name => (function, register_tool! keywords); filled by the files that define the tools.
const _BUILTIN_DEFS = Dict{String,Tuple{Function,NamedTuple}}()
const _BUILTINS = Dict{String,ToolSpec}()

function _builtin!(f::Function; group::String, kwargs...)
    group in _BUILTIN_GROUPS || error("unknown built-in group $group")
    _BUILTIN_DEFS[_tool_name(f)] = (f, (; group, kwargs...))
    return nothing
end

# Specs are built on first use: docstrings are read at run time, not while precompiling.
function _builtins()
    if length(_BUILTINS) != length(_BUILTIN_DEFS)
        for (name, (f, kw)) in _BUILTIN_DEFS
            haskey(_BUILTINS, name) || (_BUILTINS[name] = _tool_spec(f; kw...))
        end
    end
    return _BUILTINS
end

"""
    builtin_tools() -> Vector{ToolSpec}

Every tool that ships with JAIL, registered or not, sorted by name. They are grouped by what
they do:

| Group | Tools |
|---|---|
| `"read"` | `read_file`, `list_dir`, `find_files`, `grep_files`, `check_julia_syntax`, `git_changes` |
| `"inspect"` | `julia_source_module`, `julia_source_struct`, `julia_source_method`, `julia_source_methods`, `julia_docs`, `find_julia_symbols`, `pkg_status`, `repl_history`, `last_result` |
| `"edit"` | `create_file`, `create_directory`, `replace_in_file`, `replace_in_files`, `edit_file` |
| `"execute"` | `execute_julia_code`, `run_shell`, `run_tests`, `pkg_add` |
| `"web"` | `fetch_url` |
| `"interact"` | `ask_user` |

None is registered when JAIL loads: opt in with [`register_builtin_tools!`](@ref) or the
Preference `builtin_tools`. See the Tools guide for their security levels.
"""
builtin_tools() = sort!(collect(values(_builtins())); by = t -> t.name)

"""
    register_builtin_tools!(names...) -> Vector{ToolSpec}

Register built-in tools (see [`builtin_tools`](@ref)) so sessions can use them. Each name is a
group (`"read"`, `"inspect"`, `"edit"`, `"execute"`, `"web"`, `"interact"`) or a tool name,
as a `String` or `Symbol`. Returns the tools registered. A registered tool of the same name is
replaced, as with [`register_tool!`](@ref); remove one again with [`unregister_tool!`](@ref).

```julia
register_builtin_tools!("read", "inspect")
register_builtin_tools!(:execute_julia_code)
```

The Preference `builtin_tools` (a list of the same names) registers them each time JAIL loads.
"""
function register_builtin_tools!(names::Union{AbstractString,Symbol}...)
    isempty(names) && throw(ArgumentError(
        "name the built-in groups or tools to register, e.g. `register_builtin_tools!(\"read\")`; " *
        "groups: $(join(_BUILTIN_GROUPS, ", "))"))
    specs = ToolSpec[]
    for n in names
        n = string(n)
        found = n in _BUILTIN_GROUPS ? [t for t in builtin_tools() if t.group == n] :
                haskey(_builtins(), n) ? [_builtins()[n]] :
                throw(ArgumentError("no built-in group or tool named \"$n\"; groups: " *
                                    "$(join(_BUILTIN_GROUPS, ", ")); tools: $(join(sort!(collect(keys(_builtins()))), ", "))"))
        append!(specs, found)
    end
    unique!(t -> t.name, specs)
    foreach(_register!, specs)
    return specs
end

function _register_builtin_prefs!()
    try
        names = _string_list_pref("builtin_tools")
        isempty(names) || register_builtin_tools!(names...)
    catch e
        @warn "JAIL: could not register the built-in tools listed in the Preference `builtin_tools`" exception = e
    end
    return nothing
end
