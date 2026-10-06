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
    ask_user(question, options = nothing, allow_free_text = true)

Ask the user a question in the terminal and wait for the answer. Use it when you need a decision
or information only the user has; don't use it to ask permission for tool calls (that happens
automatically). With `options`, the user picks one of them, or, if `allow_free_text` is true,
types their own answer instead.

# Arguments
- `question`: the question, one or two sentences
- `options`: the answers to choose from; omit for a free-text answer
- `allow_free_text`: with `options`, whether the user may answer with their own text instead of an option
"""
function ask_user(question::String, options::Union{Nothing,Vector{String}} = nothing,
                  allow_free_text::Bool = true)
    _before_prompt()
    _discard_pending_input(stdin)
    printstyled(stdout, "? ", strip(question), "\n"; color = :magenta, bold = true)
    (options === nothing || isempty(options)) && return _free_text_answer()
    if stdin isa Base.TTY
        labels = allow_free_text ? [options; "Other (type your own answer)"] : options
        i = _pick(_menu_terminal(), "", labels)
        i === nothing && return "(the user cancelled without choosing)"
        return i <= length(options) ? options[i] : _free_text_answer()
    end
    foreach(((i, o),) -> println(stdout, "  ", i, ". ", o), enumerate(options))
    hint = allow_free_text ? "number or your own answer" : "number"
    while true
        print(stdout, "(", hint, ") > ")
        answer = strip(readline(stdin))
        isempty(answer) && return "(the user gave no answer)"
        k = tryparse(Int, answer)
        k !== nothing && 1 <= k <= length(options) && return options[k]
        allow_free_text && return String(answer)
        println(stdout, "Please enter a number from 1 to ", length(options), ".")
    end
end

function _free_text_answer()
    print(stdout, "> ")
    answer = strip(readline(stdin))
    return isempty(answer) ? "(the user gave no answer)" : String(answer)
end

# Tools that never need approval, whatever the security level, mode or auto-approvals.
_never_confirm(t::ToolSpec) = t.f === ask_user || t.f === tool_search || t.f === tool_load ||
    t.f === activate_skill || t.f === read_skill_related_file || t.f isa _SkillTool

_builtin!(repl_history; group = "inspect", label = "REPL history", security = :medium)
_builtin!(last_result; group = "inspect", label = "Last REPL result", security = :medium)
# No preview: the tool prints the question itself.
_builtin!(ask_user; group = "interact", label = "Ask user", security = :low, concurrent = false)
