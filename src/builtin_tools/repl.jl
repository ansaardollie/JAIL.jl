# Built-in REPL tools: repl_history, last_result ("inspect") and ask_user ("interact").

# (mode, text) of the REPL's history, oldest first; nothing without an interactive REPL.
function _repl_entries()
    isdefined(Base, :active_repl) || return nothing
    r = Base.active_repl
    r isa REPL.LineEditREPL && isdefined(r, :interface) || return nothing
    i = findfirst(m -> hasproperty(m, :hist) && m.hist isa REPL.REPLHistoryProvider, r.interface.modes)
    i === nothing && return nothing
    hp = r.interface.modes[i].hist
    h = hp.history
    # Julia ≤ 1.12 keeps parallel vectors; 1.13 a HistoryFile of entries.
    h isa AbstractVector{<:AbstractString} && return collect(zip(hp.modes, h))
    hasproperty(h, :records) && return [(e.mode, e.content) for e in h.records]
    return nothing
end

"""
    repl_history(n = 20)

Show the last `n` inputs the user typed in the Julia REPL (code and other REPL modes), oldest
first, each starting with its mode's prompt, e.g. `julia> `.

# Arguments
- `n`: how many inputs to show
"""
function repl_history(n::Int = 20)
    n >= 1 || throw(ArgumentError("n must be at least 1"))
    entries = _repl_entries()
    entries === nothing && return "No REPL history is available (Julia is not running an interactive REPL)."
    isempty(entries) && return "The REPL history is empty."
    lines = [string(mode, "> ", text) for (mode, text) in entries[max(1, end - n + 1):end]]
    return join(lines, '\n')
end

"""
    last_result()

Show the value of the last expression the user evaluated in the Julia REPL (`ans`), as the REPL
displays it.
"""
function last_result()
    isdefined(Main, :ans) || return "There is no last result (`ans` is not defined)."
    return sprint((io, v) -> show(IOContext(io, :limit => true), MIME"text/plain"(), v), Main.ans)
end

"""
    ask_user(question, options = nothing)

Ask the user a question in the terminal and wait for the answer. Use it when you need a decision
or information only the user has; don't use it to ask permission for tool calls (that happens
automatically). With `options`, the user picks one of them (or, without a menu, types its number
or their own answer).

# Arguments
- `question`: the question, one or two sentences
- `options`: the answers to choose from; omit for a free-text answer
"""
function ask_user(question::String, options::Union{Nothing,Vector{String}} = nothing)
    _before_prompt()
    printstyled(stdout, "? ", strip(question), "\n"; color = :magenta, bold = true)
    if options === nothing || isempty(options)
        print(stdout, "> ")
        answer = strip(readline(stdin))
        return isempty(answer) ? "(the user gave no answer)" : String(answer)
    end
    if stdin isa Base.TTY
        i = _pick(_menu_terminal(), "", options)
        return i === nothing ? "(the user cancelled without choosing)" : options[i]
    end
    foreach(((i, o),) -> println(stdout, "  ", i, ". ", o), enumerate(options))
    print(stdout, "> ")
    answer = strip(readline(stdin))
    k = tryparse(Int, answer)
    k !== nothing && 1 <= k <= length(options) && return options[k]
    return isempty(answer) ? "(the user gave no answer)" : String(answer)
end

# Tools that never need approval, whatever the security level, mode or auto-approvals.
_never_confirm(t::ToolSpec) = t.f === ask_user

_builtin!(repl_history; group = "inspect", label = "REPL history", security = :medium)
_builtin!(last_result; group = "inspect", label = "Last REPL result", security = :medium)
_builtin!(ask_user; group = "interact", label = "Ask user", security = :low, preview = "question")
