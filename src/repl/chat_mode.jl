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
function _render_tool_rows(io::IO, s::Session, results::Vector{ToolResult}; tty::Bool)
    labels = [_tool_label(r.name) for r in results]
    width = maximum(textwidth, labels)
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
end

function _render_stop(io::IO, reply::AssistantMessage)
    r = reply.stop_reason
    r === nothing || r === :end_turn || printstyled(io, "[stop reason: ", r, "]\n"; color = :yellow)
    return nothing
end

# `Response (model; N in; M out):`, with the tokens summed over every reply of the turn.
function _response_title(messages)
    replies = [m for m in messages if m isa AssistantMessage]
    parts = String[]
    i = findlast(r -> r.model !== nothing, replies)
    i === nothing || push!(parts, string(replies[i].model))
    used = [r.usage for r in replies if r.usage !== nothing]
    isempty(used) || push!(parts, string(sum(u -> u.input_tokens, used), " in"),
                           string(sum(u -> u.output_tokens, used), " out"))
    return string("Response", isempty(parts) ? "" : string(" (", join(parts, "; "), ")"), ":")
end

# Julia logo colors: purple around the whole turn, blue / red / green for its parts.
const _CHAT_COLOR = Colors.JULIA_LOGO_COLORS.purple
const _PROMPT_COLOR = Colors.JULIA_LOGO_COLORS.blue
const _TOOLS_COLOR = Colors.JULIA_LOGO_COLORS.red
const _RESPONSE_COLOR = Colors.JULIA_LOGO_COLORS.green
const _REASONING_COLOR = Colors.RGB(0.95, 0.77, 0.06)   # yellow; the logo colors have none

# The traces themselves are not shown, only a numbered link to each saved one.
function _render_reasoning_rows(io::IO, r::_ReasoningSaved; tty::Bool)
    width = ndigits(length(r.paths))
    for (i, path) in enumerate(r.paths)
        print(io, "  ", lpad(i, width), ". ")
        printstyled(io, tty ? _hyperlink("View", path) : Base.contractuser(path);
                    color = :light_black, underline = tty)
        println(io)
    end
end

# Bold 24-bit color text, plain when `io` has no color.
function _print_rgb(io::IO, c::Colors.RGB, text...)
    get(io, :color, false) || return print(io, text...)
    rgb = (round(Int, 255 * Float64(f(c))) for f in (Colors.red, Colors.green, Colors.blue))
    print(io, "\e[1m\e[38;2;", join(rgb, ';'), 'm', text..., "\e[39m\e[22m")
end

_blank_line(l) = isempty(strip(replace(l, r"\e\[[0-9;]*m" => "")))

# What `f(io)` prints, as lines, keeping `io`'s color setting and narrowed by `indent` columns.
function _captured_lines(f, io::IO, indent::Int)
    h, w = displaysize(io)
    buf = IOBuffer()
    f(IOContext(buf, :color => get(io, :color, false), :displaysize => (h, max(20, w - indent))))
    lines = String.(split(String(take!(buf)), '\n'))
    # Trailing blank lines may still hold style resets: fold them into the last kept line.
    while length(lines) > 1 && _blank_line(lines[end])
        tail = pop!(lines)
        lines[end] *= tail
    end
    return length(lines) == 1 && _blank_line(lines[1]) ? String[] : lines
end

# A box like `@info`'s, in heavy lines (bold alone doesn't thicken box glyphs in most terminals).
function _box(io::IO, color::Colors.RGB, title::AbstractString, lines)
    _print_rgb(io, color, "┏ ", title)
    println(io)
    for l in lines
        _print_rgb(io, color, "┃")
        _blank_line(l) ? println(io, l) : println(io, " ", l)
    end
    _print_rgb(io, color, "┗")
    println(io)
end

_prompt_lines(io::IO, prompt, indent::Int) =
    _captured_lines(o -> show(o, MIME"text/plain"(), Markdown.parse(string(prompt))), io, indent)
_prompt_box(io::IO, prompt) = _box(io, _PROMPT_COLOR, "Prompt:", _prompt_lines(io, prompt, 2))

# The finished turn: with `response`, one box in the chat color around the Prompt (when
# `prompt` is given), Reasoning (when `reasoning` is a `_ReasoningSaved`), Tool calls and Response
# boxes; without, just the Reasoning and Tool calls boxes.
function _render_turn(io::IO, s::Session, turn; tty::Bool, prompt = nothing, response::Bool = true,
                      reasoning::Union{Nothing,_ReasoningSaved} = nothing)
    results = ToolResult[r for m in turn if m isa ToolResultMessage for r in m.content]
    indent = response ? 4 : 2
    sections = Tuple{Colors.RGB,String,Vector{String}}[]
    prompt === nothing || push!(sections, (_PROMPT_COLOR, "Prompt:", _prompt_lines(io, prompt, indent)))
    reasoning === nothing || push!(sections, (_REASONING_COLOR, "Reasoning ($(length(reasoning.paths))):",
        _captured_lines(o -> _render_reasoning_rows(o, reasoning; tty), io, indent)))
    isempty(results) || push!(sections, (_TOOLS_COLOR, "Tool calls ($(length(results))):",
        _captured_lines(o -> _render_tool_rows(o, s, results; tty), io, indent)))
    response && push!(sections, (_RESPONSE_COLOR, _response_title(turn),
        _captured_lines(o -> _render_texts(o, turn), io, indent)))
    draw(o) = foreach(((c, t, ls),) -> _box(o, c, t, ls), sections)
    response ? _box(io, _CHAT_COLOR, "Chat: $(s.name)", _captured_lines(draw, io, 2)) : draw(io)
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
    reply = _display_turn(io, s, line; stream, tty, header = _CHAT_PROMPT * line)
    return _render_stop(io, reply)
end

# One turn shown as in the `}` mode, also used by `chat!(...; stream = true)`. `output = false`
# leaves out the rendered reply text (the REPL displays the returned reply instead).
function _display_turn(io::IO, s::Session, prompt; stream::Bool, tty::Bool = io isa Base.TTY,
                       header::AbstractString = string(prompt), output::Bool = true,
                       show_reasoning = nothing, kwargs...)
    n0 = length(s.messages)
    show_reasoning = _show_reasoning(show_reasoning)
    status, alt, line_start = Ref(false), Ref(false), Ref(true)
    phase = Ref(:none)   # what the last streamed chunk was: :reasoning, :text or :none
    saved = Ref{Union{Nothing,_ReasoningSaved}}(nothing)
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
            printstyled(io, header, "\n\n"; color = :light_black)
        end
    end
    function show_delta(t)
        clear_status()
        enter_alt()
        if phase[] === :reasoning
            print(io, line_start[] ? "\n" : "\n\n")
            line_start[] = true
        end
        phase[] = :text
        print(io, t)
        isempty(t) || (line_start[] = endswith(t, '\n'))
    end
    function show_reasoning_delta(t)
        clear_status()
        enter_alt()
        phase[] === :reasoning || line_start[] || (println(io); line_start[] = true)
        phase[] = :reasoning
        printstyled(io, t; color = :light_black, italic = true)
        isempty(t) || (line_start[] = endswith(t, '\n'))
    end
    function on_step(x)
        x isa _ReasoningSaved && (saved[] = x; return)
        phase[] = :none
        if x isa AssistantMessage
            lines = stream ? filter(!isnothing, [_search_line(p) for p in x.content if p isa ToolSearchPart]) : []
            if !isempty(lines)
                clear_status()
                enter_alt()
                line_start[] || (println(io); line_start[] = true)
                foreach(l -> printstyled(io, l, "\n"; color = :cyan), lines)
            end
            return
        end
        # The confirmation prompt needs the line to itself; when streaming, the preview is shown.
        x isa Union{_Confirming,_Prompting} && (clear_status(); return stream)
        x isa _ToolsFinished && (stream || show_status("thinking…"); return)
        if stream
            clear_status()
            enter_alt()
            line_start[] || (println(io); line_start[] = true)
            _print_tool(io, x)
        elseif x isa ToolCall
            show_status("→ $(_tool_label(x.name))…", :cyan)
        elseif x isa _RunningTogether
            show_status("→ $(join((_tool_label(c.name) for c in x.calls), ", "))…", :cyan)
        else
            show_status("thinking…")
        end
    end
    show_prompt = output && !isinteractive()
    # Text streamed to a non-terminal is printed as it comes, so the prompt goes first.
    stream && !tty && show_prompt && _prompt_box(io, prompt)
    show_status("thinking…")
    reply = try
        _chat!(s, prompt; on_text = stream ? show_delta : nothing,
               on_reasoning = stream && show_reasoning ? show_reasoning_delta : nothing,
               on_step, show_reasoning, kwargs...)
    finally
        clear_status()
        alt[] && print(io, _ALT_SCREEN_OFF)
    end
    turn = s.messages[n0+2:end]
    if stream && !tty
        # Not a terminal: the streamed raw text and tool lines stay as printed.
        line_start[] || println(io)
        _render_turn(io, s, turn; tty, response = false, reasoning = saved[])
    else
        _render_turn(io, s, turn; tty, response = output, prompt = show_prompt ? prompt : nothing,
                     reasoning = saved[])
    end
    return reply
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
