const _AGENT_HELP = """
    Anything you type is sent to the active session's model in agent mode (tools, skills, the
    applied agent), e.g. `&` then `Fix the failing test in test/runtests.jl`. The prompt shows the
    agent; change it in the `|` mode with `agent select`.

    Enter sends; Ctrl+J or Alt+Enter inserts a new line (as in the `}` mode).

    /<skill> [args...]   run a skill: its instructions become the prompt; arguments are separated
                          by spaces ("..." or '...' keep spaces), missing ones are asked for
    /clear               clear the active session's history
    /help                show this help and the skills

    Press backspace on an empty line to leave this mode."""

const _AGENT_COMMANDS = ("/clear", "/help")

_agent_prompt() = isassigned(_ACTIVE) ? string("(", _agent_name(active_session()), ") agent> ") : "agent> "

function _skill_usage(k::Skill)
    isempty(k.arguments) && return string("/", k.name)
    k.argument_hint === nothing || return string("/", k.name, " ", k.argument_hint)
    return string("/", k.name, " ", join((a.required ? "<$(a.name)>" : "[$(a.name)]" for a in k.arguments), " "))
end

function _agent_help(io::IO)
    println(io, replace(_AGENT_HELP, r"^(?=.)"m => "  "))
    ks = _user_skills()
    isempty(ks) && return println(io, "\n  No skills found (create one with `skill new` in the `|` mode).")
    println(io, "\n  Skills:")
    width = maximum(k -> textwidth(_skill_usage(k)), ks)
    for k in ks
        println(io, "    ", rpad(_skill_usage(k), width), "  ", _short(k.description, 70))
    end
end

function _agent_session()
    s = active_session()
    s.model === nothing && throw(ArgumentError(
        "session \"$(s.name)\" has no model; choose one in the `|` mode with `use provider/model` or `select`"))
    return s
end

function _agent_turn_display(io::IO, s::Session, prompt, turn, header; tty::Bool)
    stream = _stream_pref() && _supports_streaming(s.model.provider)
    reply = _display_turn(io, s, prompt; mode = _AgentMode(turn), stream, tty, header)
    return _render_stop(io, reply)
end

function _agent_send(io::IO, line::AbstractString; tty::Bool = io isa Base.TTY)
    s = _agent_session()
    return _agent_turn_display(io, s, line, _agent_turn(s), _agent_prompt() * line; tty)
end

function _agent_skill(io::IO, line::AbstractString; tty::Bool = io isa Base.TTY)
    word = first(split(line))
    name, rest = word[2:end], strip(line[lastindex(word)+1:end])
    s = _agent_session()
    k = _by_name(_user_skills(), name, "skill")
    k === nothing && return nothing
    prompt = _skill_prompt(k, _split_args(rest))
    turn = _agent_turn(s)
    _activate!(turn, k)
    allowed = _ref_names(_resolve_tool_refs(k.allowed_tools))
    isempty(allowed) || printstyled(io, "skill ", k.name, " runs without asking: ", join(allowed, ", "), "\n";
                                    color = :light_black)
    return _agent_turn_display(io, s, prompt, turn, _agent_prompt() * line; tty)
end

function _agent_slash(io::IO, line::AbstractString)
    cmd = first(split(line))
    if cmd == "/clear"
        s = active_session()
        n = length(s.messages)
        empty!(s)
        println(io, "Cleared ", n, " messages from session \"", s.name, "\"")
    elseif cmd == "/help"
        _agent_help(io)
    else
        _agent_skill(io, line)
    end
end

function _agent_command(line::AbstractString; io::IO = stdout)
    text = strip(line)
    isempty(text) && return nothing
    try
        startswith(text, '/') ? _agent_slash(io, text) : _agent_send(io, text)
    catch e
        if e isa InterruptException
            println(io, "Interrupted; nothing was added to the history.")
        else
            _print_error(e)
        end
    end
    return nothing
end

_agent_mode_parser(line::AbstractString) = :($_agent_command($line))

function _complete_agent_mode(before::AbstractString)
    startswith(before, '/') && !occursin(' ', before) || return (String[], "")
    names = try
        ["/" * k.name for k in _user_skills()]
    catch
        String[]
    end
    return _matching(sort!(unique!([collect(_AGENT_COMMANDS); names])), before)
end
