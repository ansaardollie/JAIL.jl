abstract type modelProvider end

"""
model::String: name of the model provided in Google Gemini, like 'gemini-2.0-flash'
api::String: your google gemini api key
"""
Base.@kwdef mutable struct Gemini <: modelProvider
    model::String
    api::String
end

"""
model::String: name of the model provided in local ollama
url::String: the url of ollama model, IP:port is needed
"""
Base.@kwdef mutable struct ollama <: modelProvider
    model::String
    url::String
end

"""
model::String: name of the model exposed by an OpenAI-compatible API
baseurl::String: API host URL, without the `/v1` path
api::String: optional API key; blank is valid for local endpoints
"""
Base.@kwdef mutable struct OpenAICompatible <: modelProvider
    model::String
    baseurl::String
    api::String = ""
end

"""
list avaliabel models in currrent provider

```julia
AskAI.setapi("Gemini|gemini-2.0-flash|AIzaSyBqwIWyterU29hkdUNkSHYoBRSi4AN4fgU")
AskAI.avaliableModels(pretty=true) # pretty = false to return raw string vector
```
  avalibale models:

    •  glm4:latest

    •  deepseek-r1:70b
"""
function avaliableModels end
function avaliableModels(m::modelProvider; pretty::Bool = true )
    if typeof(m) == Gemini
        url = "https://generativelanguage.googleapis.com/v1beta/models?key=$(m.api)"
        try
            resp = HTTP.get(url)
            if resp.status == 200
                res =  JSON3.read(resp.body)[:models]
                models = [replace(i["name"],"models/" => "") for i in res if "generateContent" in i["supportedGenerationMethods"]]
                if pretty
                    join( vcat(["avalibale models:"],models), "\n - ") |> MD
                else
                    models
                end

            end
        catch error
            return "error code $(resp.status)"
        end

    elseif typeof(m) == ollama
        url = m.url * "/api/tags"
        try
            resp = HTTP.get(url)
            if resp.status == 200
                models = [i["name"] for i in JSON3.read(resp.body)[:models]]
                if pretty
                    join( vcat(["avalibale models:"],models), "\n - ") |> MD
                else
                    models
                end
            end
        catch error
            return "error code $(resp.status)"
        end

    elseif typeof(m) == OpenAICompatible
        url = "$(_baseURL(m))/v1/models"
        try
            resp = HTTP.get(url, _requestHeaders(m))
            if resp.status == 200
                models = [i[:id] for i in JSON3.read(resp.body)[:data]]
                if pretty
                    join(vcat(["avalibale models:"], models), "\n - ") |> MD
                else
                    models
                end
            end
        catch error
            return "error: $(sprint(showerror, error))"
        end

    end
end
avaliableModels(;kws...) = avaliableModels(Brain.model;kws...)

"""
throw an error if the model provider still holds placeholder or empty config values
"""
function checkConfig(m::modelProvider)
    target = m isa Gemini ? m.api : m isa ollama ? m.url : m.baseurl
    if isempty(strip(m.model)) || m.model == "noModel" || isempty(strip(target)) || target == "noAPI"
        error("AskAI is not configured. Set ENV[\"AskAI_config\"] before loading, or call AskAI.setapi(\"provider|model|apiOrURL\").")
    end
    return nothing
end

"""
warp question into json data
"""
function _terminalPromptContext()
    rows, columns = displaysize(stdout)
    return "The terminal is $(columns) columns wide and $(rows) rows high. Keep output lines within $(max(columns - 2, 1)) columns, wrap long lines, and avoid unnecessarily wide tables."
end

function question2JSONString(m::modelProvider, question::AbstractString)
    question = _terminalPromptContext() * "\n" * Brain.RAG * "\n" * Brain.memory * "\n" * Brain.prompt * "\n" * question
    if typeof(m) == Gemini
        return JSON3.write(Dict("contents" => Dict("parts" => [Dict("text" => question)])))

    elseif typeof(m) == ollama
        return JSON3.write(Dict("model" => m.model,
                                "prompt" => question,
                                "stream" => Brain.stream))
    elseif typeof(m) == OpenAICompatible
        return JSON3.write(Dict("model" => m.model,
                                "messages" => [Dict("role" => "user", "content" => question)],
                                "stream" => Brain.stream))
    end

    @error "Error in converting question into json string"
end

"""
construct the URL for HTTP request, based on model provider
"""
function getRESTURL(m::modelProvider)
    if typeof(m) == Gemini
        if !Brain.stream
            return  "https://generativelanguage.googleapis.com/v1beta/models/$(m.model):generateContent?key=$(m.api)"
        else
            return "https://generativelanguage.googleapis.com/v1beta/models/$(m.model):streamGenerateContent?alt=sse&key=$(m.api)"
        end
    elseif  typeof(m) == ollama
        return "$(rstrip(m.url, '/'))/api/generate"
    elseif typeof(m) == OpenAICompatible
        return "$(_baseURL(m))/v1/chat/completions"
    end
end

function _requestHeaders(m::modelProvider)
    headers = Dict("Content-Type" => "application/json")
    if m isa OpenAICompatible && !isempty(strip(m.api))
        headers["Authorization"] = "Bearer $(m.api)"
    end
    return headers
end

function _baseURL(m::OpenAICompatible)
    url = strip(m.baseurl)
    return startswith(url, "http://") || startswith(url, "https://") ? rstrip(url, '/') : "https://$(rstrip(url, '/'))"
end

"""
retrieve answer from AI response
"""
function getAnswer end
function getAnswer(m::Gemini, resp)
    if !AskAI.Brain.stream
        return JSON3.read(resp.body)[:candidates][1][:content][:parts][1]["text"]
    else
        if startswith(resp, "data: ")
            data = JSON3.read(replace(resp, r"^data: " => ""))
            return data[:candidates][1][:content][:parts][1]["text"]
        else
            return ""
        end
    end
end

function getAnswer(m::ollama, resp)
    try
        resp = !AskAI.Brain.stream ?  JSON3.read(resp.body)["response"] : JSON3.read(resp)["response"]
    catch error
        resp = ""
    end
    return resp
end

function getAnswer(m::OpenAICompatible, resp)
    try
        data = !AskAI.Brain.stream ? JSON3.read(resp.body) : JSON3.read(replace(resp, r"^data: " => ""))
        if !haskey(data, :choices) || isempty(data[:choices])
            return ""
        end
        choice = data[:choices][1]
        if AskAI.Brain.stream
            return haskey(choice, :delta) && haskey(choice[:delta], :content) ? String(choice[:delta][:content]) : ""
        end
        return haskey(choice, :message) && haskey(choice[:message], :content) ? String(choice[:message][:content]) : ""
    catch error
        return ""
    end
end
