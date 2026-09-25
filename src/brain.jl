Base.@kwdef mutable struct AIBrain
    memory::String = "" # summary of the past queries, sent as system context
    history::Dict{String,Vector{String}} = Dict("ask" => String[], "ans" => String[]) # conversation history
    prompt::String = ""
    stream::Bool = true # if the model returns the stream response
    timeout::Int = 60 # seconds without data before a request is abandoned; local models may think for a while
    model::ModelProvider
    rag::String = "" # to store RAG result
    terminal_hint::Bool = true # tell the model the terminal size so output fits
    render_final::Bool = true # after streaming, also return the answer rendered as Markdown
    max_turns::Int = 10 # past turns resent verbatim by providers that take a message list (Responses API)
end


"""
change_model!(AskAI.Brain, "qwen2.5:72b")
"""
function change_model!(m::AIBrain, model::String)
    m.model.model = model
end


_request_error(err) = ErrorException("AskAI request failed, please check the configuration (see AskAI.setapi): $(sprint(showerror, err))")

(m::AIBrain)(question::AbstractString) = begin
    check_config(m.model)
    m.stream ? _ask_stream(m, question) : _ask_once(m, question)
end

"""
send a single non-streaming request and return the raw answer text, without touching memory or history
"""
function _complete(m::AIBrain, question::AbstractString)
    resp = HTTP.post(request_url(m.model, false), _request_headers(m.model), request_body(m.model, m, question);
                     read_idle_timeout=m.timeout, connect_timeout=10, retry=false)
    return parse_answer(m.model, resp, false)
end

function _remember!(m::AIBrain, question::AbstractString, text::AbstractString)
    m.memory *= "ask: $(question) \n ans: $(text) \n"
    push!(m.history["ask"], question)
    push!(m.history["ans"], text)
    errormonitor(@async check_memory!(m))
    return nothing
end

function _ask_once(m::AIBrain, question::AbstractString)
    text = try
        _complete(m, question)
    catch err
        throw(_request_error(err))
    end
    _remember!(m, question, text)
    return Markdown.parse(_format_markdown_for_terminal(text))
end

function _ask_stream(m::AIBrain, question::AbstractString)
    url = request_url(m.model, true)
    headers = _request_headers(m.model)
    body = request_body(m.model, m, question)
    channel = Channel{String}(3000)
    failure = Ref{Any}(nothing)

    @async try
        HTTP.open(:POST, url, headers; read_idle_timeout=m.timeout, connect_timeout=10, retry=false) do io
            write(io, body)
            HTTP.closewrite(io)
            r = HTTP.startread(io)
            r.status == 200 || error("HTTP $(r.status): $(String(read(io)))")
            repeats = 0
            last_str = ""
            emit(line) = begin
                text = parse_answer(m.model, strip(line), true)
                isempty(text) && return
                # stop a model stuck emitting the same chunk over and over
                repeats = text == last_str ? repeats + 1 : 0
                last_str = text
                put!(channel, text)
            end
            buffer = ""
            while repeats <= 10 && !eof(io)
                lines = split(buffer * String(readavailable(io)), "\n")
                buffer = String(pop!(lines)) # possibly incomplete line, finished by the next read
                foreach(emit, lines)
            end
            emit(buffer)
            HTTP.closeread(io)
        end
    catch err
        failure[] = err
    finally
        close(channel)
    end

    answer = IOBuffer()
    for chunk in channel
        position(answer) == 0 && print("\n\e[32m¬ \e[0m")
        print(chunk)
        flush(stdout)
        write(answer, chunk)
    end
    failure[] === nothing || throw(_request_error(failure[]))
    text = String(take!(answer))
    _remember!(m, question, text)
    println()
    m.render_final || return nothing
    # Render the final Markdown below the preserved stream output.
    return MD(_format_markdown_for_terminal("# Final Output \n\n" * text))
end

function _wrap_terminal_text(text::AbstractString, width::Int)
    words = split(strip(text))
    isempty(words) && return [""]
    lines = String[]
    current = ""
    for word in words
        if isempty(current)
            current = word
        elseif length(current) + length(word) + 1 <= width
            current *= " " * word
        else
            push!(lines, current)
            current = word
        end
    end
    push!(lines, current)
    return lines
end

function _table_cells(line::AbstractString)
    value = strip(line)
    startswith(value, "|") && (value = value[2:end])
    endswith(value, "|") && (value = value[1:end-1])
    return strip.(split(value, "|"))
end

function _is_table_separator(line::AbstractString)
    cells = _table_cells(line)
    !isempty(cells) && all(cell -> occursin(r"^:?-{3,}:?$", cell), cells)
end

function _is_pipe_table_header(lines, index::Int)
    index < length(lines) && occursin("|", lines[index]) && _is_table_separator(lines[index + 1])
end

function _format_wide_table(lines, width::Int)
    headers = _table_cells(lines[1])
    column_count = length(headers)
    rows = Vector{Vector{String}}()
    for line in lines[3:end]
        cells = _table_cells(line)
        isempty(cells) && continue
        values = if length(cells) == column_count
            cells
        elseif length(cells) > column_count
            normalized = cells[1:column_count]
            for (offset, cell) in enumerate(cells[column_count + 1:end])
                target = 1 + mod(offset - 1, column_count)
                !isempty(cell) && (normalized[target] *= " " * cell)
            end
            normalized
        else
            vcat(cells, fill("", column_count - length(cells)))
        end
        if !isempty(rows) && isempty(strip(values[1]))
            previous = rows[end]
            for index in eachindex(values)
                !isempty(strip(values[index])) && (previous[index] *= " " * values[index])
            end
        else
            push!(rows, values)
        end
    end
    formatted = String[]
    for values in rows
        push!(formatted, "")
        for (index, value) in enumerate(values)
            label = index <= length(headers) ? headers[index] : "Column $(index)"
            prefix = "- **$(label):** "
            wrapped = _wrap_terminal_text(value, max(width - length(prefix), 10))
            push!(formatted, prefix * wrapped[1])
            for continuation in wrapped[2:end]
                push!(formatted, "  " * continuation)
            end
        end
    end
    return formatted
end

function _format_markdown_for_terminal(text::AbstractString)
    width = max(displaysize(stdout)[2] - 2, 20)
    lines = split(String(text), "\n"; keepempty=true)
    formatted = String[]
    index = 1
    while index <= length(lines)
        if _is_pipe_table_header(lines, index)
            stop = index + 2
            while stop <= length(lines) && occursin("|", lines[stop]) && !isempty(strip(lines[stop]))
                stop += 1
            end
            table = lines[index:stop - 1]
            if maximum(length.(table)) > width
                append!(formatted, _format_wide_table(table, width))
                index = stop
                continue
            end
        end
        push!(formatted, lines[index])
        index += 1
    end
    return join(formatted, "\n")
end

"""
optimize the `memory` text: when it exceeds `L` characters, summarize it into about 300 words
"""
function check_memory!(m::AIBrain, L = 3000)
    if length(m.memory) > L
        summarizer = AIBrain(model = m.model, prompt = "Summarize the following in about 300 words:", stream = false, timeout = m.timeout, terminal_hint = false)
        m.memory = _complete(summarizer, m.memory)
    end
    return nothing
end

const MD = Markdown.parse
Base.show(io::IO, ::MIME"text/plain", m::AIBrain) = show(io, MIME"text/plain"(), MD("""
$(m.model.model)

\n for more \n
- memory: $(length(m.memory)) words
- history:  $(length(m.history["ans"])) conversation
- prompt: $(m.prompt)

"""))

