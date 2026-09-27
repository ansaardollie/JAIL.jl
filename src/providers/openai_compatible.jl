"""
    OpenAICompatible(name, base_url; api_key_env = nothing, api = :responses)
    OpenAICompatible(name)

A server speaking the OpenAI wire format (LM Studio, vLLM, OpenRouter, ...). `name` is how the
endpoint is referred to in model strings (`"lmstudio/llama-3.1-8b"`). `api_key_env` is the name
of the ENV var holding the key, or `nothing` for servers without auth. `api` is `:responses`
(default) or `:chat_completions` for servers that lack the Responses API.

`OpenAICompatible(name)` loads an endpoint saved with [`register_provider!`](@ref).
"""
struct OpenAICompatible <: AbstractOpenAIProvider
    name::String
    base_url::String
    api_key_env::Union{Nothing,String}
    api::Symbol
    function OpenAICompatible(name::AbstractString, base_url::AbstractString;
                              api_key_env::Union{Nothing,AbstractString} = nothing,
                              api::Symbol = :responses)
        _check_compatible_name(name)
        api in (:responses, :chat_completions) ||
            throw(ArgumentError("api must be :responses or :chat_completions, got :$api"))
        env = api_key_env === nothing ? nothing : _check_env_name(api_key_env)
        return new(String(name), _normalize_url(base_url), env, api)
    end
end

function OpenAICompatible(name::AbstractString)
    t = get(_provider_prefs(), name, nothing)
    (t === nothing || get(t, "type", nothing) != "openai_compatible") && throw(ArgumentError(
        "no OpenAI-compatible provider named \"$name\" is registered; use " *
        "`register_provider!(OpenAICompatible(\"$name\", base_url))`"))
    return OpenAICompatible(name, t["base_url"];
                            api_key_env = get(t, "api_key_env", nothing),
                            api = Symbol(get(t, "api", "responses")))
end

provider_name(p::OpenAICompatible) = p.name

_wire(p::OpenAICompatible) = p.api === :chat_completions ? _ChatCompletionsAPI() : _ResponsesAPI()

# POST /chat/completions, the fallback for servers without Responses.
# openapi/api_spec.yaml#L2249, CreateChatCompletionRequest #L42331
_request_url(::_ChatCompletionsAPI, p) = p.base_url * "/chat/completions"

function _request_body(::_ChatCompletionsAPI, p, req::_Request)
    messages = Dict{String,String}[]
    req.system === nothing || push!(messages, Dict("role" => "system", "content" => req.system))
    for m in _replayable(req.messages)
        push!(messages, Dict("role" => _role(m), "content" => string(m)))
    end
    body = Dict{String,Any}("model" => req.model.id, "messages" => messages)
    # Deprecated at OpenAI in favour of max_completion_tokens (#L42574-L42586), but it is the
    # field compatible servers accept. UNVERIFIED per server.
    req.max_tokens === nothing || (body["max_tokens"] = req.max_tokens)
    return body
end

# CreateChatCompletionResponse #L42695 (finish_reason enum #L42733-L42738);
# message #L40876; usage #L41457
function _parse_reply(::_ChatCompletionsAPI, req::_Request, json)
    choice = first(json["choices"])
    msg = choice["message"]
    parts = AbstractContentPart[]
    content = get(msg, "content", nothing)
    content === nothing || isempty(content) || push!(parts, TextPart(content))
    refusal = get(msg, "refusal", nothing)
    refusal === nothing || push!(parts, TextPart(refusal))
    fr = get(choice, "finish_reason", nothing)
    reason = refusal !== nothing ? :refusal :
             fr == "stop" ? :end_turn :
             fr == "length" ? :max_tokens :
             fr in ("tool_calls", "function_call") ? :tool_use :
             fr == "content_filter" ? :content_filter : :other
    usage = _usage(get(json, "usage", nothing), "prompt_tokens", "completion_tokens")
    return AssistantMessage(parts; model = req.model, stop_reason = reason, usage,
                            id = get(json, "id", nothing))
end

function Base.show(io::IO, p::OpenAICompatible)
    print(io, "OpenAICompatible(", repr(p.name), ", ", repr(p.base_url))
    p.api_key_env === nothing || print(io, "; api_key_env = ", repr(p.api_key_env))
    p.api === :responses || print(io, p.api_key_env === nothing ? "; " : ", ", "api = :", p.api)
    print(io, ")")
end

const _RESERVED_NAMES = ("openai", "anthropic", "google")

function _check_compatible_name(name::AbstractString)
    occursin(r"^[A-Za-z0-9._-]+$", name) || throw(ArgumentError(
        "provider name may only contain letters, digits, '.', '_' and '-', got \"$name\""))
    name in _RESERVED_NAMES && throw(ArgumentError(
        "\"$name\" is reserved for the built-in provider; pick another name"))
    return nothing
end
