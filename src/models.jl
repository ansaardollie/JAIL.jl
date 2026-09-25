abstract type ModelProvider end

"""
model::String: name of the model provided in Google Gemini, like 'gemini-2.0-flash'
api::String: your google gemini api key
"""
Base.@kwdef mutable struct Gemini <: ModelProvider
    model::String
    api::String
end

"""
model::String: name of the model provided in local ollama
url::String: the url of ollama model, IP:port is needed
"""
Base.@kwdef mutable struct Ollama <: ModelProvider
    model::String
    url::String
end

"""
model::String: name of the model exposed by an OpenAI-compatible API
url::String: API host URL, with or without the `/v1` path
api::String: optional API key; blank is valid for local endpoints
chat_completions::Bool: use `/v1/chat/completions` instead of the default `/v1/responses` API
"""
Base.@kwdef mutable struct OpenAICompatible <: ModelProvider
    model::String
    url::String
    api::String = ""
    chat_completions::Bool = false
end

"""
placeholder provider used until `setapi` succeeds
"""
Base.@kwdef mutable struct NotConfigured <: ModelProvider
    model::String = "not configured"
end

"""
list available models in the current provider (or `m`); errors are thrown, not returned

```julia
AskAI.setapi("ollama", "glm4:latest")
AskAI.available_models(pretty=true) # pretty = false to return raw string vector
```
  available models:

    •  glm4:latest

    •  deepseek-r1:70b
"""
function available_models(m::ModelProvider = Brain.model; pretty::Bool = true)
    models = _list_models(m)
    return pretty ? MD(join(vcat(["available models:"], models), "\n - ")) : models
end

_get_json(m::ModelProvider, url) = JSON3.read(HTTP.get(url, _request_headers(m); connect_timeout=10, retry=false).body)

_list_models(::NotConfigured) = error(CONFIG_HELP)
function _list_models(m::Gemini)
    res = _get_json(m, "https://generativelanguage.googleapis.com/v1beta/models")[:models]
    return [replace(i[:name], "models/" => "") for i in res if "generateContent" in i[:supportedGenerationMethods]]
end
_list_models(m::Ollama) = [String(i[:name]) for i in _get_json(m, "$(_base_url(m))/api/tags")[:models]]
_list_models(m::OpenAICompatible) = [String(i[:id]) for i in _get_json(m, "$(_base_url(m))/v1/models")[:data]]

"""
throw an error if the model provider is unconfigured or has empty required values
"""
check_config(::NotConfigured) = error(CONFIG_HELP)
function check_config(m::ModelProvider)
    absent = [name for (name, value) in _required_config(m) if isempty(strip(value))]
    isempty(absent) || error("AskAI is missing: $(join(absent, ", ")). Call AskAI.setapi(provider, model; url, api).")
    return nothing
end

_required_config(m::Gemini) = ["model (ASK_AI_MODEL)" => m.model, "API key (ASK_AI_API_KEY or GEMINI_API_KEY)" => m.api]
_required_config(m::Ollama) = ["model (ASK_AI_MODEL)" => m.model, "URL (ASK_AI_BASE_URL)" => m.url]
_required_config(m::OpenAICompatible) = ["model (ASK_AI_MODEL)" => m.model, "URL (ASK_AI_BASE_URL)" => m.url]

function _terminal_prompt_context()
    rows, columns = displaysize(stdout)
    return "The terminal is $(columns) columns wide and $(rows) rows high. Keep output lines within $(max(columns - 2, 1)) columns, wrap long lines, and avoid unnecessarily wide tables."
end

"""
system instructions built from the brain's prompt, RAG context and conversation memory
"""
function _system_prompt(b; memory::Bool = true)
    parts = String[]
    b.terminal_hint && push!(parts, _terminal_prompt_context())
    isempty(b.prompt) || push!(parts, b.prompt)
    isempty(b.rag) || push!(parts, "Reference material:\n" * b.rag)
    memory && !isempty(b.memory) && push!(parts, "Conversation so far:\n" * b.memory)
    return join(parts, "\n\n")
end

"""
wrap the question, with the brain's context as system instructions, into the provider's JSON request body
"""
function request_body end
function request_body(m::Gemini, b, question::AbstractString)
    body = Dict{String,Any}("contents" => [Dict("role" => "user", "parts" => [Dict("text" => question)])])
    system = _system_prompt(b)
    isempty(system) || (body["systemInstruction"] = Dict("parts" => [Dict("text" => system)]))
    return JSON3.write(body)
end
function request_body(m::Ollama, b, question::AbstractString)
    body = Dict{String,Any}("model" => m.model, "prompt" => question, "stream" => b.stream)
    system = _system_prompt(b)
    isempty(system) || (body["system"] = system)
    return JSON3.write(body)
end
function request_body(m::OpenAICompatible, b, question::AbstractString)
    if !m.chat_completions
        asks, answers = b.history["ask"], b.history["ans"]
        first_turn = max(1, length(answers) - b.max_turns + 1)
        # the memory summary only carries context for turns too old to resend verbatim
        system = _system_prompt(b; memory = first_turn > 1)
        # a system message rather than `instructions`, which some gateways drop for non-OpenAI backends
        input = isempty(system) ? Dict{String,String}[] : [Dict("role" => "system", "content" => system)]
        for i in first_turn:length(answers)
            push!(input, Dict("role" => "user", "content" => asks[i]), Dict("role" => "assistant", "content" => answers[i]))
        end
        push!(input, Dict("role" => "user", "content" => question))
        return JSON3.write(Dict("model" => m.model, "input" => input, "stream" => b.stream, "store" => false))
    end
    system = _system_prompt(b)
    messages = [Dict("role" => "user", "content" => question)]
    isempty(system) || pushfirst!(messages, Dict("role" => "system", "content" => system))
    return JSON3.write(Dict("model" => m.model, "messages" => messages, "stream" => b.stream))
end

"""
construct the URL for HTTP request, based on model provider
"""
function request_url end
function request_url(m::Gemini, stream::Bool)
    base = "https://generativelanguage.googleapis.com/v1beta/models/$(m.model)"
    return stream ? "$(base):streamGenerateContent?alt=sse" : "$(base):generateContent"
end
request_url(m::Ollama, stream::Bool) = "$(_base_url(m))/api/generate"
request_url(m::OpenAICompatible, stream::Bool) = "$(_base_url(m))/v1/$(m.chat_completions ? "chat/completions" : "responses")"

_request_headers(m::ModelProvider) = Dict("Content-Type" => "application/json")
_request_headers(m::Gemini) = Dict("Content-Type" => "application/json", "x-goog-api-key" => m.api)
function _request_headers(m::OpenAICompatible)
    headers = Dict("Content-Type" => "application/json")
    isempty(strip(m.api)) || (headers["Authorization"] = "Bearer $(m.api)")
    return headers
end

_base_url(m::Ollama) = rstrip(strip(m.url), '/')
function _base_url(m::OpenAICompatible)
    url = replace(rstrip(strip(m.url), '/'), r"/v1$" => "") # accept OPENAI_BASE_URL-style values ending in /v1
    return startswith(url, "http://") || startswith(url, "https://") ? url : "https://$(url)"
end

"""
retrieve answer text from an AI response (non-stream) or a single stream line (stream);
non-stream parse failures throw, unparseable stream lines yield ""
"""
function parse_answer end
function parse_answer(m::Gemini, resp, stream::Bool)
    stream || return _gemini_text(JSON3.read(resp.body))
    startswith(resp, "data: ") || return ""
    return try _gemini_text(JSON3.read(chopprefix(resp, "data: "))) catch; "" end
end
_gemini_text(data) = String(data[:candidates][1][:content][:parts][1][:text])

function parse_answer(m::Ollama, resp, stream::Bool)
    stream || return String(JSON3.read(resp.body)[:response])
    return try String(JSON3.read(resp)[:response]) catch; "" end
end

function parse_answer(m::OpenAICompatible, resp, stream::Bool)
    m.chat_completions || return _responses_answer(resp, stream)
    stream || return _choice_content(JSON3.read(resp.body), :message)
    return try _choice_content(JSON3.read(chopprefix(resp, "data: ")), :delta) catch; "" end
end

# `content` is null or absent in role-only and reasoning-only chunks
function _choice_content(data, key::Symbol)
    choices = get(data, :choices, nothing)
    (choices === nothing || isempty(choices)) && return ""
    content = get(get(choices[1], key, Dict()), :content, nothing)
    return content isa AbstractString ? String(content) : ""
end

# stream: only `response.output_text.delta` events carry visible text; `event:` lines and reasoning events yield ""
function _responses_answer(resp, stream::Bool)
    stream || return _responses_text(JSON3.read(resp.body))
    startswith(resp, "data: ") || return ""
    return try
        data = JSON3.read(chopprefix(resp, "data: "))
        get(data, :type, "") == "response.output_text.delta" ? String(data[:delta]) : ""
    catch
        ""
    end
end

function _responses_text(data)
    texts = [String(c[:text]) for item in get(data, :output, []) if get(item, :type, "") == "message"
             for c in get(item, :content, []) if get(c, :type, "") == "output_text"]
    isempty(texts) && haskey(data, :output_text) && return String(data[:output_text])
    return join(texts)
end
