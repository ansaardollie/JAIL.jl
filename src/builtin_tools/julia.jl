# Built-in Julia tools: julia_docs, find_julia_symbols ("inspect"), check_julia_syntax ("read")
# and execute_julia_code ("execute").

using Logging: Logging

# --- Where model code runs -------------------------------------------------------------------

const _JULIA_CODE_MODULES = ("main", "sandbox")

function _julia_code_module()
    v = _load_pref("julia_code_module", "main")
    v isa AbstractString && v in _JULIA_CODE_MODULES || throw(ArgumentError(
        "Preference `julia_code_module` must be \"main\" or \"sandbox\", got $(repr(v))"))
    return String(v)
end

# One module per session (key `nothing`: calls made outside a chat turn). Not saved with sessions.
const _SANDBOXES = Dict{Union{Nothing,UUID},Module}()

function _eval_module()
    _julia_code_module() == "main" && return Main
    ctx = tool_context()
    id = ctx === nothing ? nothing : ctx.session.id
    # The tail of a version 7 UUID is random; its head is a timestamp shared by nearby sessions.
    return get!(() -> Module(Symbol("Sandbox_", id === nothing ? "shared" : string(id)[end-11:end])), _SANDBOXES, id)
end

# --- execute_julia_code ----------------------------------------------------------------------

struct _JuliaEvalError <: Exception
    output::String
    error::Any
    trace::Vector{Base.StackTraces.StackFrame}
end

function Base.showerror(io::IO, e::_JuliaEvalError)
    isempty(e.output) || print(io, e.output, endswith(e.output, '\n') ? "" : "\n")
    print(io, "ERROR: ")
    showerror(io, e.error)
    isempty(e.trace) || Base.show_backtrace(io, e.trace)
end

const _EVAL_FILE = "jail_tool"

# Frames of the evaluated code only: everything from the first frame of JAIL's own call down.
function _user_frames(bt)
    st = stacktrace(bt)
    i = findlast(f -> string(f.file) == _EVAL_FILE, st)
    return i === nothing ? Base.StackTraces.StackFrame[] : st[1:i]
end

# Runs `f()` with stdout, stderr, logging and `display` going to one text stream; returns
# (value or exception, backtrace or nothing, captured text).
function _captured(f)
    pipe = Pipe()
    Base.link_pipe!(pipe; reader_supports_async = true, writer_supports_async = true)
    buf = IOBuffer()
    reader = @async write(buf, pipe)
    d = TextDisplay(pipe)
    value, bt = nothing, nothing
    try
        redirect_stdout(pipe) do
            redirect_stderr(pipe) do
                Logging.with_logger(Logging.ConsoleLogger(pipe, Logging.Info)) do
                    pushdisplay(d)
                    try
                        value = f()
                    catch e
                        e isa InterruptException && rethrow()
                        value, bt = e, catch_backtrace()
                    finally
                        popdisplay(d)
                    end
                end
            end
        end
    finally
        close(pipe.in)
        wait(reader)
    end
    return value, bt, String(take!(buf))
end

"""
    execute_julia_code(code)

Run Julia code in the user's Julia session and return everything it printed (stdout, stderr,
log messages, `display`ed values) followed by `=> ` and the value of the last expression, as
the REPL would show it. End the code with `;` to leave the value out. Definitions and
variables stay defined for later calls. Relative paths (e.g. in `include`) are relative to the
workspace folder. If the code throws, the result is an error that still contains what was
printed before it.

# Arguments
- `code`: the Julia code to run; several lines are fine
"""
function execute_julia_code(code::String)
    mod = _eval_module()
    # Relative `include`s and `@__DIR__` in the code resolve from the workspace folder, not from
    # whatever file is being included when the tool runs.
    run() = task_local_storage(:SOURCE_PATH, joinpath(_workspace_root(), _EVAL_FILE)) do
        Base.invokelatest(include_string, mod, code, _EVAL_FILE)
    end
    value, bt, out = _captured(run)
    if bt !== nothing
        err = value isa LoadError ? value.error : value
        throw(_JuliaEvalError(out, err, _user_frames(bt)))
    end
    (value === nothing || REPL.ends_with_semicolon(code)) && return isempty(out) ? "(no output)" : out
    shown = sprint(value) do io, v
        show(IOContext(io, :limit => true, :module => mod), MIME"text/plain"(), v)
    end
    return string(out, isempty(out) || endswith(out, '\n') ? "" : "\n", "=> ", shown)
end

# --- Inspecting ------------------------------------------------------------------------------

"""
    julia_docs(name)

Show the documentation (docstring) of a Julia function, type, module, macro or constant, as
Markdown.

# Arguments
- `name`: the name, qualified with its module if it isn't in Main, e.g. `sum`, `Base.Dict`, `Base.@kwdef`, `MyPkg.solve`
"""
function julia_docs(name::String)
    ex = _parse_name(name)
    # `Base.@kwdef` parses as a call of the macro with no arguments.
    Meta.isexpr(ex, :macrocall) && all(a -> a isa LineNumberNode, ex.args[2:end]) && (ex = ex.args[1])
    binding = if ex isa Symbol
        mods = _lookup_modules()
        i = findfirst(m -> isdefined(m, ex), mods)
        Docs.Binding(i === nothing ? Main : mods[i], ex)
    elseif Meta.isexpr(ex, :., 2) && ex.args[2] isa QuoteNode
        parent = _resolve_name(ex.args[1])
        parent isa Module || throw(ArgumentError("`$(ex.args[1])` is not a module"))
        Docs.Binding(parent, ex.args[2].value)
    else
        throw(ArgumentError("`$name` is not a name; give a name such as `sum` or `Base.Dict`"))
    end
    return Markdown.plain(Docs.doc(binding))
end

function _symbol_kind(v)
    v isa Module && return "module"
    v isa Type && return "type"
    v isa Function && return "function"
    return "value of type $(typeof(v))"
end

"""
    find_julia_symbols(query, max_results = 50)

Find functions, types, modules and other names of the loaded Julia packages (and Main) whose
name contains `query`, ignoring case. Returns one `Module.name :: kind` per line. Only public
names of packages are searched.

# Arguments
- `query`: part of the name to look for
- `max_results`: how many names to return at most
"""
function find_julia_symbols(query::String, max_results::Int = 50)
    q = lowercase(strip(query))
    isempty(q) && throw(ArgumentError("the query is empty"))
    hits = Tuple{Bool,String}[]
    for m in unique!([Main; Base.loaded_modules_array()]), n in names(m)
        s = string(n)
        (startswith(s, '#') || startswith(s, '_') || !occursin(q, lowercase(s)) || !isdefined(m, n)) && continue
        push!(hits, (m !== Main, string(m, '.', s, " :: ", _symbol_kind(getglobal(m, n)))))
    end
    isempty(hits) && return "No loaded names contain `$query`."
    return _limited(last.(sort!(unique!(hits))), max_results, "names")
end

"""
    check_julia_syntax(path)

Check a Julia file for syntax errors without running it. Returns each problem with its
`file:line:column` and the offending code, or a line saying there are none.

# Arguments
- `path`: the `.jl` file, relative to the workspace folder or absolute
"""
function check_julia_syntax(path::String)
    text = read(_text_file(path), String)
    stream = JuliaSyntax.ParseStream(text; version = VERSION)
    JuliaSyntax.parse!(stream; rule = :all)
    isempty(stream.diagnostics) && return "No syntax errors in `$path`."
    io = IOBuffer()
    JuliaSyntax.show_diagnostics(io, stream.diagnostics, JuliaSyntax.SourceFile(text; filename = path))
    return String(take!(io))
end

# Runs alone: it redirects the process-wide stdout and stderr.
_builtin!(execute_julia_code; group = "execute", label = "Julia code", security = :high, preview = "code",
          concurrent = false)
_builtin!(julia_docs; group = "inspect", label = "Julia docs", security = :low, preview = "name")
_builtin!(find_julia_symbols; group = "inspect", label = "Find Julia names", security = :low, preview = "query")
_builtin!(check_julia_syntax; group = "read", label = "Check syntax", security = _read_level, preview = "path")
_PATH_GUARDS[check_julia_syntax] = _read_guard
