Base.@kwdef mutable struct AIBrain
    memory::AbstractString  = "" # summary of the past query
    history::Dict = Dict("ask" => [], "ans" => []) # conversation history
    prompt::AbstractString  = ""
    stream::Bool=true # if the model returns the stream response
    timeout::Int = 10 # set the timeout for the http request
    model::modelProvider # = "gemini-2.0-flash" # the model
    RAG::AbstractString = "" # to store RAG result
end


"""
changeModels!(AskAI.Brain, "qwen2.5:72b")
"""
function changeModels!(m::AIBrain, model::String)
    m.model.model = model
end


(m::AIBrain)( question::AbstractString ) = begin
    checkConfig(m.model)
    headers = _requestHeaders(m.model)
    url = getRESTURL(m.model)
    body = question2JSONString(m.model,question)
    if !m.stream
        try
            resp = HTTP.post(url, headers, body; read_idle_timeout=m.timeout, connect_timeout=m.timeout, retry=false)
            if resp.status == 200
                # text = JSON3.read(resp.body)[:candidates][1][:content][:parts][1]["text"]
                text = getAnswer(m.model, resp)
                m.memory *= "ask: $(question) \n ans: $(text) \n"
                push!(m.history["ask"], question)
                push!(m.history["ans"], text)
                @async checkMemory!(m)
                return Markdown.parse(_formatMarkdownForTerminal(text)) # show in the terminal
            else
                return "respond code: $(resp.status)🔗🚫"
            end
        catch err
            error("AskAI request failed, please check the config (provider|model|apiOrURL): $(sprint(showerror, err))")
        end
    else
        ##########################
        # for streaming response #
        ##########################

        m.memory *= "ask: $(question) \n"
        push!(m.history["ask"], question)

        channel = Channel{String}(3000)
        channel2 = Channel{String}(3000)

        @async try
          HTTP.open(:POST, url, headers; read_idle_timeout=m.timeout, connect_timeout=m.timeout, retry=false) do io
            write(io, body)
            HTTP.closewrite(io)
            r = HTTP.startread(io)
            r.status == 200 || error("HTTP $(r.status): $(String(read(io)))")
            EOF_signal = 0
            last_str="EOF"
            while EOF_signal <= 10 && !eof(io)
                chunk = String(readavailable(io))
                lines = String.(filter(!isempty, split(chunk, "\n")))
                for line in lines
                    currentText = getAnswer(m.model,line)
                    isempty(currentText) && continue
                    # If the model falls into a repetitive loop, I should stop it
                    if last_str === currentText
                         EOF_signal += 1
                    end
                    last_str = currentText
                    push!(channel,currentText)
                    push!(channel2,currentText)
                end
            end
            HTTP.closeread(io)
          end
          isopen(channel) && close(channel);
          isopen(channel2) && close(channel2);
        catch err
            # closing with the exception makes take! in the main task rethrow instead of blocking
            ex = ErrorException("AskAI request failed, please check the config (provider|model|apiOrURL): $(sprint(showerror, err))")
            close(channel, ex)
            close(channel2, ex)
        end
        showStreamStringFromChannel(channel) # show in the terminal
        streamToMemory(m,channel2)
        @async checkMemory!(m)
        flush(stdout)
        println()
        # Render the final Markdown below the preserved stream output.
        final_text = replace(Brain.history["ans"][end], r"^ans: " => "# Final Output \n\n" )
        MD(_formatMarkdownForTerminal(final_text))

      end;
end

function _wrapTerminalText(text::AbstractString, width::Int)
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

function _tableCells(line::AbstractString)
    value = strip(line)
    startswith(value, "|") && (value = value[2:end])
    endswith(value, "|") && (value = value[1:end-1])
    return strip.(split(value, "|"))
end

function _isTableSeparator(line::AbstractString)
    cells = _tableCells(line)
    !isempty(cells) && all(cell -> occursin(r"^:?-{3,}:?$", cell), cells)
end

function _isPipeTableHeader(lines, index::Int)
    index < length(lines) && occursin("|", lines[index]) && _isTableSeparator(lines[index + 1])
end

function _formatWideTable(lines, width::Int)
    headers = _tableCells(lines[1])
    column_count = length(headers)
    rows = Vector{Vector{String}}()
    for line in lines[3:end]
        cells = _tableCells(line)
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
            wrapped = _wrapTerminalText(value, max(width - length(prefix), 10))
            push!(formatted, prefix * wrapped[1])
            for continuation in wrapped[2:end]
                push!(formatted, "  " * continuation)
            end
        end
    end
    return formatted
end

function _formatMarkdownForTerminal(text::AbstractString)
    width = max(displaysize(stdout)[2] - 2, 20)
    lines = split(String(text), "\n"; keepempty=true)
    formatted = String[]
    index = 1
    while index <= length(lines)
        if _isPipeTableHeader(lines, index)
            stop = index + 2
            while stop <= length(lines) && occursin("|", lines[stop]) && !isempty(strip(lines[stop]))
                stop += 1
            end
            table = lines[index:stop - 1]
            if maximum(length.(table)) > width
                append!(formatted, _formatWideTable(table, width))
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
For stream mode, append each response chunk directly to the terminal.
"""
function showStreamStringFromChannel(channel::Channel)
    first_text = take!(channel)
    println()
    print("\e[32m¬ \e[0m")
    print(first_text)
    flush(stdout)
    for chunk in channel
        print(chunk)
        flush(stdout)
    end
end


"""
for stream mode, take string from the channel, convert to markdown, and save as `memory` context
"""
function streamToMemory(m::AIBrain,channel::Channel)
    first_text = take!(channel)
    response = first_text

    m.memory *= "ans: $(response)"
    cache = "ans: $(response)"

    for chunk in channel
        m.memory *= "$(chunk)"
        cache *= "$(chunk)"
    end
    push!(m.history["ans"], cache)
end

"""
optimalize the `memory text`, when the memory words length exceeds 3000 words,  summary it into 300 words
"""
function checkMemory!(m::AIBrain,L = 3000)
    if length(m.memory) > L
        tmpBrain = AIBrain(api=AI_API_KEY,prompt = "summary below into 300 words:")
        m.memory = tmpBrain( m.memory) |> string;
    end
    return nothing
end;

MD = Markdown.parse
Base.show(io::IO, ::MIME"text/plain", m::AIBrain) = begin
    MD("""
$(m.model.model)

\n for more \n
- memory: $(length(m.memory)) words
- history:  $(length(m.history["ans"])) conversation
- prompt: $(m.prompt)

""") |> show
end

