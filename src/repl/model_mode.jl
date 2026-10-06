const _MODEL_HELP = """
    status, st                            show the active session's details
    providers                             list providers and whether their API key is set
    models [provider]                     list models (default: the active model's provider)
    select [provider]                     choose the active session's model from menus
    use provider/model | use provider     set the active session's model (provider alone needs
                                           that provider's own default, see `default`)
    default [provider/model]              show or save the global default model for new sessions
    default provider [model-id]           show or save that provider's own default model
    sessions                              list sessions (* = active)
    session new [name] [provider/model]   start a session and make it active
    session use <name|id>                 switch the active session (a menu picks among
                                           sessions sharing the name)
    session restore                       choose a saved session from a menu and make it active
    session rm <name|id> [--files]        delete a session (not the active one); --files also
                                           deletes its saved files
    tools                                 list tools by group (* = available to the active session)
    tools show <name>                     a tool's description and parameters
    tools use <name>...                   restrict the active session to these tools; a
                                           `group:<group>` argument stands for all tools in it
    tools add <name>... | drop <name>...  add to / remove from the active session's tools
    tools all | none                      every registered tool (the default) | no tools
    tools approve <name|group:<group>>... run these tools' calls without asking (saved in
                                           the Preference tool_auto_approvals)
    tools unapprove <name|group:<group>>...  remove those entries (security level decides)
    tokens [provider/model]               count the active session's input tokens (system,
                                           tools, messages) with the provider, for its model
                                           or the one given
    help, ?                               show this help

    Press backspace on an empty line to leave this mode."""

_model_prompt() = isassigned(_ACTIVE) ? _session_label(active_session()) * " model> " : "model> "

function _nargs(cmd, args, n::UnitRange)
    length(args) in n && return nothing
    usage = Dict("models" => "models [provider]", "select" => "select [provider]",
                 "use" => "use provider/model | use provider",
                 "default" => "default [provider/model | provider [model-id]]",
                 "session" => "session new [name] [provider/model] | use <name|id> | restore | rm <name|id> [--files]",
                 "session new" => "session new [name] [provider/model]",
                 "session use" => "session use <name|id>", "session restore" => "session restore",
                 "session rm" => "session rm <name|id> [--files]",
                 "tools" => "tools [show <name> | use|add|drop|approve|unapprove <name>... | all | none]",
                 "tools show" => "tools show <name>", "tools use" => "tools use <name|group:<group>>...",
                 "tools add" => "tools add <name|group:<group>>...", "tools drop" => "tools drop <name|group:<group>>...",
                 "tools all" => "tools all", "tools none" => "tools none",
                 "tools approve" => "tools approve <name|group:<group>>...",
                 "tools unapprove" => "tools unapprove <name|group:<group>>...",
                 "tokens" => "tokens [provider/model]")
    throw(ArgumentError("usage: `$(get(usage, cmd, cmd))`"))
end

function _cmd_status(args)
    _nargs("status", args, 0:0)
    _show_details(stdout, active_session(); status = true)
    println()
end

function _cmd_providers(args)
    _nargs("providers", args, 0:0)
    foreach(l -> println("  ", l), _provider_labels(providers()))
end

function _cmd_models(args)
    _nargs("models", args, 0:1)
    current = _model_string(active_session())
    p = if isempty(args)
        current === nothing &&
            throw(ArgumentError("the active session has no model; name a provider, e.g. `models anthropic`"))
        active_session().model.provider
    else
        _provider(args[1])
    end
    models = _fetch_models(p)
    println(length(models), " models from ", provider_name(p), ":")
    foreach(m -> println(string(m) == current ? "  * " : "    ", m.id), models)
end

function _cmd_select(args)
    _nargs("select", args, 0:1)
    isempty(args) && return select_model!()
    occursin('/', args[1]) &&
        throw(ArgumentError("`select` opens a menu; to set a model directly use `use $(args[1])`"))
    select_model!(_provider(args[1]))
end

function _cmd_use(args)
    _nargs("use", args, 1:1)
    s = active_session()
    arg = args[1]
    m = occursin('/', arg) ? set_model!(s, arg) : use_provider!(s, _provider(arg))
    println("Session \"", s.name, "\" now uses ", m)
end

function _cmd_default(args)
    _nargs("default", args, 0:2)
    if isempty(args)
        return println("Default model: ", something(_load_pref("default_model"), "none"))
    end
    if length(args) == 2
        p = _provider(args[1])
        m = set_default_model!(p, args[2])
        return println("Default model for ", provider_name(p), " saved: ", m.id)
    end
    arg = args[1]
    if occursin('/', arg)
        m = set_default_model!(arg)
        println("Default model saved: ", m, " (used by new sessions)")
        active_session().model === nothing &&
            println("The active session has no model; `use $m` to use it here.")
    else
        p = _provider(arg)
        id = get(_provider_prefs(provider_name(p)), "default_model", nothing)
        println("Default model for ", provider_name(p), ": ", something(id, "none"))
    end
end

function _cmd_sessions(args)
    _nargs("sessions", args, 0:0)
    foreach(l -> println("  ", l), _session_rows(sessions()))
end

function _cmd_session(args)
    isempty(args) && _nargs("session", args, 1:3)
    sub, rest = args[1], args[2:end]
    if sub == "new"
        _nargs("session new", rest, 0:2)
        model = findfirst(a -> occursin('/', a), rest)
        names = [a for a in rest if !occursin('/', a)]
        (length(names) > 1 || length(rest) - length(names) > 1) && _nargs("session new", rest, 0:0)
        s = new_session!(isempty(names) ? nothing : names[1];
                         model = model === nothing ? nothing : rest[model])
        println("Started session \"", s.name, "\" using ", s.model)
    elseif sub == "use"
        _nargs("session use", rest, 1:1)
        s = use_session!(rest[1])
        s === nothing || println("Active session: ", s.name, " (", something(_model_string(s), "no model"), ")")
    elseif sub == "restore"
        _nargs("session restore", rest, 0:0)
        s = restore_session!()
        s === nothing || println("Active session: ", s.name, " (",
                                 something(_model_string(s), "no model"), ", ", length(s.messages), " messages)")
    elseif sub == "rm"
        files = "--files" in rest
        names = filter(!=("--files"), rest)
        _nargs("session rm", names, 1:1)
        s = delete_session!(names[1]; files)
        s === nothing || println("Deleted session \"", s.name, "\"", files ? " and its files" : "")
    else
        throw(ArgumentError("unknown `session` subcommand `$sub`; use new, use, restore or rm"))
    end
end

_cmd_help(args) = println(replace(_MODEL_HELP, r"^(?=.)"m => "  "))

function _list_tools(s::Session)
    all, mine = tools(), Set(t.name for t in tools(s))
    isempty(all) && return println("No tools registered; use `register_tool!(f)` or `@tool f` in Julia mode.")
    println("Session \"", s.name, "\" uses ", s.tools === nothing ? "every registered tool" :
            "$(length(mine)) of $(length(all)) tools", ":")
    width = maximum(t -> length(t.name), all)
    table = tool_auto_approvals()
    for g in _tool_groups()
        printstyled("  ", g, "\n"; bold = true)
        for t in all
            t.group == g || continue
            label = t.label == t.name ? "" : string(" (", repr(t.label), ")")
            desc = isempty(t.description) ? "" : _short(first(split(t.description, '\n')), 60)
            print(t.name in mine ? "  * " : "    ", rpad(t.name, width), "  ", desc, label)
            a = _auto_approval(t, table)
            a === nothing || printstyled(a ? "  [auto-approved]" : "  [always asks]"; color = a ? :green : :yellow)
            println()
        end
    end
end

_approval_label(a) = a === nothing ? "by security level and tool_approval" : a ? "auto-approved" : "always asks"

const _GROUP_ARG = "group:"

# Tool names, with each `group:<group>` replaced by the names of that group's tools.
_expand_tool_args(args) =
    unique!(reduce(vcat, (startswith(a, _GROUP_ARG) ? [t.name for t in tools(a[length(_GROUP_ARG)+1:end])] : [a]
                          for a in args); init = String[]))

function _session_tools_changed(s::Session)
    println("Session \"", s.name, "\" tools: ", _tools_label(s))
end

function _cmd_tools(args)
    s = active_session()
    isempty(args) && return _list_tools(s)
    sub, names = args[1], args[2:end]
    if sub == "show"
        _nargs("tools show", names, 1:1)
        haskey(_TOOLS, names[1]) || throw(ArgumentError("no tool named \"$(names[1])\" is registered"))
        show(stdout, MIME"text/plain"(), _TOOLS[names[1]])
        println("\n  approval: ", _approval_label(_auto_approval(_TOOLS[names[1]])))
    elseif sub in ("approve", "unapprove")
        isempty(names) && _nargs("tools $sub", names, 1:typemax(Int))
        for n in names
            set_tool_auto_approval!(startswith(n, _GROUP_ARG) ? n : _registered_tool(n), sub == "approve" ? true : nothing)
            println(n, ": ", sub == "approve" ? "auto-approved" : _approval_label(nothing))
        end
    elseif sub in ("use", "add", "drop")
        isempty(names) && _nargs("tools $sub", names, 1:typemax(Int))
        names = _expand_tool_args(names)
        _tool_names(names)
        if sub == "use"
            set_tools!(s, names)
        elseif sub == "add"
            s.tools === nothing &&
                return println("Session \"", s.name, "\" already uses every registered tool")
            set_tools!(s, [s.tools; names])
        else
            set_tools!(s, setdiff(s.tools === nothing ? [t.name for t in tools()] : s.tools, names))
        end
        _session_tools_changed(s)
    elseif sub in ("all", "none")
        _nargs("tools $sub", names, 0:0)
        set_tools!(s, sub == "all" ? nothing : String[])
        _session_tools_changed(s)
    else
        throw(ArgumentError("unknown `tools` subcommand `$sub`; use show, use, add, drop, all, none, approve or unapprove"))
    end
end

function _cmd_tokens(args)
    _nargs("tokens", args, 0:1)
    c = count_tokens(active_session(); model = isempty(args) ? nothing : args[1])
    show(stdout, MIME"text/plain"(), c)
    println()
end

const _MODEL_COMMANDS = Dict(
    "status" => _cmd_status, "st" => _cmd_status, "providers" => _cmd_providers,
    "models" => _cmd_models, "select" => _cmd_select, "use" => _cmd_use,
    "default" => _cmd_default, "sessions" => _cmd_sessions, "session" => _cmd_session,
    "tools" => _cmd_tools, "tokens" => _cmd_tokens, "help" => _cmd_help, "?" => _cmd_help)

function _model_command(line::AbstractString)
    words = split(strip(line))
    isempty(words) && return nothing
    cmd = get(_MODEL_COMMANDS, words[1], nothing)
    try
        cmd === nothing && throw(ArgumentError("unknown command `$(words[1])`; type `help`"))
        cmd(String.(words[2:end]))
    catch e
        e isa InterruptException && rethrow()
        _print_error(e)
    end
    return nothing
end

_model_mode_parser(line::AbstractString) = :($_model_command($line))

_matching(candidates, partial) = ([c for c in candidates if startswith(c, partial)], partial)

function _complete_model_spec(partial::AbstractString)
    names = [provider_name(p) for p in providers()]
    i = findfirst('/', partial)
    i === nothing && return _matching((n * "/" for n in names), partial)
    pname = partial[begin:prevind(partial, i)]
    return _matching((pname * "/" * id for id in get(_MODEL_ID_CACHE, pname, String[])), partial)
end

function _complete_model_mode(before::AbstractString)
    parts = split(lstrip(before), ' ')
    partial = String(parts[end])
    n = length(parts)
    n == 1 && return (sort!(first(_matching(keys(_MODEL_COMMANDS), partial))), partial)
    cmd = parts[1]
    if n == 2 && cmd in ("models", "select")
        return _matching((provider_name(p) for p in providers()), partial)
    elseif n == 2 && cmd in ("use", "default", "tokens")
        return _complete_model_spec(partial)
    elseif n == 3 && cmd == "default"
        return _matching(get(_MODEL_ID_CACHE, parts[2], String[]), partial)
    elseif cmd == "session"
        n == 2 && return _matching(("new", "use", "restore", "rm"), partial)
        n == 3 && parts[2] in ("use", "rm") && return _matching(unique(s.name for s in _SESSIONS), partial)
        n in (3, 4) && parts[2] == "new" && return _complete_model_spec(partial)
    elseif cmd == "tools"
        n == 2 && return _matching(("show", "use", "add", "drop", "all", "none", "approve", "unapprove"), partial)
        sub = parts[2]
        sub in ("use", "add", "drop", "approve", "unapprove") && return _matching(
            [sort!(collect(keys(_TOOLS))); [_GROUP_ARG * g for g in _tool_groups()]], partial)
        sub == "show" && n == 3 && return _matching(sort!(collect(keys(_TOOLS))), partial)
    end
    return (String[], partial)
end
