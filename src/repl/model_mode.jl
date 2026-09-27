const _MODEL_HELP = """
    status, st                            show the active session and its model
    providers                             list providers and whether their API key is set
    models [provider]                     list models (default: the active model's provider)
    select [provider]                     choose the active session's model from menus
    use provider/model                    set the active session's model
    default [provider/model]              show or save the default model for new sessions
    sessions                              list sessions (* = active)
    session new [name] [provider/model]   start a session and make it active
    session use <name>                    switch the active session
    session rm <name>                     delete a session (not the active one)
    help, ?                               show this help

    Press backspace on an empty line to leave this mode."""

_model_prompt() = isassigned(_ACTIVE) ? _session_label(active_session()) * " model> " : "model> "

function _nargs(cmd, args, n::UnitRange)
    length(args) in n && return nothing
    usage = Dict("models" => "models [provider]", "select" => "select [provider]",
                 "use" => "use provider/model", "default" => "default [provider/model]",
                 "session" => "session new [name] [provider/model] | use <name> | rm <name>",
                 "session new" => "session new [name] [provider/model]",
                 "session use" => "session use <name>", "session rm" => "session rm <name>")
    throw(ArgumentError("usage: `$(get(usage, cmd, cmd))`"))
end

function _cmd_status(args)
    _nargs("status", args, 0:0)
    s = active_session()
    println("Session:  ", s.name)
    if s.model === nothing
        println("Model:    none (choose one with `use provider/model` or `select`)")
    else
        println("Model:    ", s.model.id)
        println("Provider: ", s.model.provider)
    end
    default = _load_pref("default_model")
    default == _model_string(s) || println("Default:  ", something(default, "none"))
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
    println("Session \"", s.name, "\" now uses ", set_model!(s, args[1]))
end

function _cmd_default(args)
    _nargs("default", args, 0:1)
    if isempty(args)
        return println("Default model: ", something(_load_pref("default_model"), "none"))
    end
    m = set_default_model!(args[1])
    println("Default model saved: ", m, " (used by new sessions)")
    active_session().model === nothing &&
        println("The active session has no model; `use $m` to use it here.")
end

function _cmd_sessions(args)
    _nargs("sessions", args, 0:0)
    ss = sessions()
    width = maximum(s -> length(s.name), ss)
    mwidth = maximum(s -> length(something(_model_string(s), "no model")), ss)
    for s in ss
        println(s === active_session() ? "  * " : "    ", rpad(s.name, width), "  ",
                rpad(something(_model_string(s), "no model"), mwidth), "  ",
                length(s.messages), " messages")
    end
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
        println("Active session: ", s.name, " (", something(_model_string(s), "no model"), ")")
    elseif sub == "rm"
        _nargs("session rm", rest, 1:1)
        println("Deleted session \"", delete_session!(rest[1]).name, "\"")
    else
        throw(ArgumentError("unknown `session` subcommand `$sub`; use new, use or rm"))
    end
end

_cmd_help(args) = println(replace(_MODEL_HELP, r"^(?=.)"m => "  "))

const _MODEL_COMMANDS = Dict(
    "status" => _cmd_status, "st" => _cmd_status, "providers" => _cmd_providers,
    "models" => _cmd_models, "select" => _cmd_select, "use" => _cmd_use,
    "default" => _cmd_default, "sessions" => _cmd_sessions, "session" => _cmd_session,
    "help" => _cmd_help, "?" => _cmd_help)

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
    elseif n == 2 && cmd in ("use", "default")
        return _complete_model_spec(partial)
    elseif cmd == "session"
        n == 2 && return _matching(("new", "use", "rm"), partial)
        n == 3 && parts[2] in ("use", "rm") && return _matching((s.name for s in _SESSIONS), partial)
        n in (3, 4) && parts[2] == "new" && return _complete_model_spec(partial)
    end
    return (String[], partial)
end
