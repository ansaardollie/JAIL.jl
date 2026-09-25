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

    end
end
avaliableModels(;kws...) = avaliableModels(Brain.model;kws...)

"""
throw an error if the model provider still holds placeholder or empty config values
"""
function checkConfig(m::modelProvider)
    target = m isa Gemini ? m.api : m.url
    if isempty(strip(m.model)) || m.model == "noModel" || isempty(strip(target)) || target == "noAPI"
        error("AskAI is not configured. Set ENV[\"AskAI_config\"] before loading, or call AskAI.setapi(\"provider|model|apiOrURL\").")
    end
    return nothing
end

"""
warp question into json data
"""
function question2JSONString(m::modelProvider, question::AbstractString)
    question = Brain.RAG * "\n" * Brain.memory * "\n" *  Brain.prompt * "\n" * question
    if typeof(m) == Gemini
        return JSON3.write(Dict("contents" => Dict("parts" => [Dict("text" => question)])))

    elseif typeof(m) == ollama
        return JSON3.write(Dict("model" => m.model,
                                "prompt" => question,
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
        strip(m.url, '/')
        return "$(m.url)/api/generate"
    end
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
