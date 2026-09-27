const _CHAT_HELP = """
    Anything you type is sent to the active session's model, e.g. `}` then `What does @inbounds do?`.
    The conversation continues until you clear it or switch session (in the `|` mode).

    Enter sends. For a new line use Ctrl+J or Alt+Enter, or Shift/Ctrl/Cmd+Enter if your terminal
    reports them (VS Code needs a keybinding; see the REPL modes page of the docs).
    Pasted multi-line text is inserted without sending.

    /clear    clear the active session's history (model and system instructions are kept)
    /help     show this help

    Press backspace on an empty line to leave this mode."""

_session_label(s::Session) = string("(", s.name, ": ", something(_model_string(s), "no model"), ")")

const _CHAT_PROMPT = "chat> "

# Ctrl+J sends '\n' (Enter sends '\r'). Shift/Ctrl/Cmd+Enter as CSI u (kitty, iTerm2, WezTerm) and
# xterm modifyOtherKeys. Alt+Enter ("\e\r") already inserts a newline in LineEdit's default keymap.
const _NEWLINE_KEYS = ("\n", "\e[13;2u", "\e[13;5u", "\e[13;9u", "\e[27;2;13~", "\e[27;5;13~")

function _add_newline_keys!(mode)
    keys = Dict{Any,Any}(k => (s, o...) -> REPL.LineEdit.edit_insert_newline(s) for k in _NEWLINE_KEYS)
    mode.keymap_dict = REPL.LineEdit.keymap_merge(mode.keymap_dict, keys)
    return mode
end

const _CHAT_COMMANDS = ("/clear", "/help")

function _chat_slash(io::IO, line::AbstractString)
    cmd = first(split(line))
    if cmd == "/clear"
        s = active_session()
        n = length(s.messages)
        empty!(s)
        println(io, "Cleared ", n, " messages from session \"", s.name, "\"")
    elseif cmd == "/help"
        println(io, replace(_CHAT_HELP, r"^(?=.)"m => "  "))
    else
        throw(ArgumentError("unknown command `$cmd`; type `/help`"))
    end
end

function _render_reply(io::IO, reply::AssistantMessage)
    text = string(reply)
    if isempty(strip(text))
        printstyled(io, "(empty reply)\n"; color = :light_black)
    else
        show(io, MIME"text/plain"(), Markdown.parse(text))
        println(io)
    end
    _render_stop(io, reply)
end

function _render_stop(io::IO, reply::AssistantMessage)
    r = reply.stop_reason
    r === nothing || r === :end_turn || printstyled(io, "[stop reason: ", r, "]\n"; color = :yellow)
    return nothing
end

function _stream_pref()
    v = _load_pref("stream", false)
    v isa Bool || throw(ArgumentError("Preference `stream` must be true or false, got $(repr(v))"))
    return v
end

const _ALT_SCREEN_ON = "\e[?1049h\e[H\e[2J"
const _ALT_SCREEN_OFF = "\e[?1049l"

# On a terminal the reply streams on the alternate screen (like `less`), which never enters the
# scrollback; switching back restores the REPL screen and only the Markdown rendering is printed.
function _chat_send(io::IO, line::AbstractString; tty::Bool = io isa Base.TTY)
    s = active_session()
    s.model === nothing && throw(ArgumentError(
        "session \"$(s.name)\" has no model; choose one in the `|` mode with `use provider/model` or `select`"))
    stream = _stream_pref() && _supports_streaming(s.model.provider)
    waiting, alt = Ref(tty), Ref(false)
    tty && printstyled(io, "thinking…"; color = :light_black)
    stop_waiting() = waiting[] && (print(io, "\r\e[2K"); waiting[] = false)
    function show_delta(t)
        stop_waiting()
        if tty && !alt[]
            print(io, _ALT_SCREEN_ON)
            alt[] = true
            printstyled(io, _CHAT_PROMPT, line, "\n\n"; color = :light_black)
        end
        print(io, t)
    end
    reply = try
        _chat!(s, line; on_text = stream ? show_delta : nothing)
    finally
        stop_waiting()
        alt[] && print(io, _ALT_SCREEN_OFF)
    end
    (tty || !stream) && return _render_reply(io, reply)
    # Not a terminal: the streamed raw text stays as printed.
    endswith(string(reply), '\n') || println(io)
    return _render_stop(io, reply)
end

function _chat_command(line::AbstractString; io::IO = stdout)
    text = strip(line)
    isempty(text) && return nothing
    try
        startswith(text, '/') ? _chat_slash(io, text) : _chat_send(io, text)
    catch e
        if e isa InterruptException
            println(io, "Interrupted; nothing was added to the history.")
        else
            _print_error(e)
        end
    end
    return nothing
end

_chat_mode_parser(line::AbstractString) = :($_chat_command($line))

function _complete_chat_mode(before::AbstractString)
    startswith(before, '/') && !occursin(' ', before) || return (String[], "")
    return _matching(_CHAT_COMMANDS, before)
end
