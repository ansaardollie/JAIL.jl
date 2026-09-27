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

# Terminal rows between the start of `text` (printed from column 1) and the cursor after it.
function _rows_above_cursor(text::AbstractString, cols::Integer)
    function rows(line)
        w = 0
        for c in line
            w = c == '\t' ? (w ÷ 8 + 1) * 8 : w + textwidth(c)
        end
        return max(1, cld(w, cols))
    end
    lines = split(text, '\n')
    return sum(rows, lines[1:end-1]; init = 0) + rows(lines[end]) - 1
end

# Streams raw text, then replaces it with the Markdown rendering. Raw rows that scrolled off the
# top can't be erased, so a tall reply leaves its first raw lines in the scrollback.
function _chat_send(io::IO, line::AbstractString; tty::Bool = io isa Base.TTY,
                    screen = tty ? displaysize(io) : (24, 80))
    s = active_session()
    s.model === nothing && throw(ArgumentError(
        "session \"$(s.name)\" has no model; choose one in the `|` mode with `use provider/model` or `select`"))
    stream = _stream_pref() && _supports_streaming(s.model.provider)
    waiting = Ref(tty)
    tty && printstyled(io, "thinking…"; color = :light_black)
    stop_waiting() = waiting[] && (print(io, "\r\e[2K"); waiting[] = false)
    shown = IOBuffer()
    on_text = stream ? (t -> (stop_waiting(); print(io, t); write(shown, t))) : nothing
    reply = try
        _chat!(s, line; on_text)
    catch
        stop_waiting()
        position(shown) > 0 && println(io)
        rethrow()
    end
    stop_waiting()
    raw = String(take!(shown))
    isempty(raw) && return _render_reply(io, reply)
    if tty
        up = min(_rows_above_cursor(raw, screen[2]), screen[1] - 1)
        print(io, up > 0 ? "\e[$(up)A" : "", "\r\e[J")
        return _render_reply(io, reply)
    end
    endswith(raw, '\n') || println(io)
    _render_stop(io, reply)
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
