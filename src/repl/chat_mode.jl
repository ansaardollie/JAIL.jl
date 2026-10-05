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

# All reply texts of the turn as one Markdown document.
function _render_texts(io::IO, messages)
    replies = [m for m in messages if m isa AssistantMessage]
    texts = filter(t -> !isempty(strip(t)), map(string, replies))
    if isempty(texts)
        all(r -> isempty(_tool_calls(r)), replies) && printstyled(io, "(empty reply)\n"; color = :light_black)
    else
        show(io, MIME"text/plain"(), Markdown.parse(join(texts, "\n\n")))
        println(io)
    end
end

function _file_url(path::AbstractString)
    io = IOBuffer()
    print(io, "file://")
    for b in codeunits(abspath(path))
        c = Char(b)
        b < 0x80 && (isletter(c) || isdigit(c) || c in "-._~/") ? write(io, b) :
            print(io, '%', uppercase(string(b; base = 16, pad = 2)))
    end
    return String(take!(io))
end

# OSC 8 hyperlink; terminals without support show just the text.
_hyperlink(text::AbstractString, path::AbstractString) =
    string("\e]8;;", _file_url(path), "\e\\", text, "\e]8;;\e\\")

# One line per call of the turn: ✓/✗, the tool's label, and a link to its saved call/result JSON
# (on a terminal `View`, else the path).
function _render_tool_summary(io::IO, s::Session, messages; tty::Bool)
    results = ToolResult[r for m in messages if m isa ToolResultMessage for r in m.content]
    isempty(results) && return false
    labels = [_tool_label(r.name) for r in results]
    width = maximum(textwidth, labels)
    printstyled(io, "Tool calls (", length(results), "):\n"; bold = true)
    for (r, label) in zip(results, labels)
        printstyled(io, "  ", r.is_error ? "✗ " : "✓ "; color = r.is_error ? :red : :green)
        path = (r.id === nothing || s._store.dir === nothing) ? nothing :
            _tool_record_path(s._store.dir, s.id, r.id)
        if path !== nothing && isfile(path)
            printstyled(io, rpad(label, width), "  "; color = :cyan)
            printstyled(io, tty ? _hyperlink("View", path) : Base.contractuser(path);
                        color = :light_black, underline = tty)
        else
            printstyled(io, label; color = :cyan)
        end
        println(io)
    end
    return true
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

# On a terminal the reply streams on the alternate screen (like `less`), with a line per tool call
# and result as they happen; the alternate screen never enters the scrollback. Without streaming,
# a transient status line shows `thinking…` or the running tool. Either way the turn is then
# printed as the tool-calls block followed by the rendered reply text.
function _chat_send(io::IO, line::AbstractString; tty::Bool = io isa Base.TTY)
    s = active_session()
    s.model === nothing && throw(ArgumentError(
        "session \"$(s.name)\" has no model; choose one in the `|` mode with `use provider/model` or `select`"))
    stream = _stream_pref() && _supports_streaming(s.model.provider)
    n0 = length(s.messages)
    status, alt, line_start = Ref(false), Ref(false), Ref(true)
    clear_status() = status[] && (print(io, "\r\e[2K"); status[] = false)
    function show_status(text, color = :light_black)
        tty || return
        clear_status()
        printstyled(io, text; color)
        status[] = true
    end
    function enter_alt()
        if tty && !alt[]
            print(io, _ALT_SCREEN_ON)
            alt[] = true
            printstyled(io, _CHAT_PROMPT, line, "\n\n"; color = :light_black)
        end
    end
    function show_delta(t)
        clear_status()
        enter_alt()
        print(io, t)
        isempty(t) || (line_start[] = endswith(t, '\n'))
    end
    function on_step(x)
        x isa AssistantMessage && return
        # The confirmation prompt needs the line to itself; when streaming, the preview is shown.
        x isa Union{_Confirming,_Prompting} && (clear_status(); return stream)
        if stream
            clear_status()
            enter_alt()
            line_start[] || (println(io); line_start[] = true)
            _print_tool(io, x)
        elseif x isa ToolCall
            show_status("→ $(_tool_label(x.name))…", :cyan)
        else
            show_status("thinking…")
        end
    end
    show_status("thinking…")
    reply = try
        _chat!(s, line; on_text = stream ? show_delta : nothing, on_step)
    finally
        clear_status()
        alt[] && print(io, _ALT_SCREEN_OFF)
    end
    turn = s.messages[n0+2:end]
    if stream && !tty
        # Not a terminal: the streamed raw text and tool lines stay as printed.
        line_start[] || println(io)
        _render_tool_summary(io, s, turn; tty)
    else
        _render_tool_summary(io, s, turn; tty) && printstyled(io, "\nOutput:\n"; bold = true)
        _render_texts(io, turn)
    end
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
