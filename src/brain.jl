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
    headers = Dict("Content-Type" => "application/json")
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
                return text |> Markdown.parse # show in the terminal
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
        # final reflash and print output
        print("\033c")
        replace(Brain.history["ans"][end], r"^ans: " => "# Final Output \n\n" ) |> MD

      end;
end

"""
for stream mode, displays a streaming response from the channel, updating the display in terminal with each chunk of text received.
"""
function showStreamStringFromChannel(channel::Channel)
    first_text = take!(channel)
    response = first_text
    println()
    print("\e[32m¬ \e[0m")
    print("\033[s")
    print(first_text)
    for chunk in channel
        print("\033[u\033[s")
        response *= chunk
        sleep(0.01)
        display(Markdown.parse(response))
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

