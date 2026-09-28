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
    messages = Dict{String,Any}[]
    req.system === nothing || push!(messages, Dict("role" => "system", "content" => req.system))
    foreach(m -> _chat_messages!(messages, m), _replayable(req.messages))
    body = Dict{String,Any}("model" => req.model.id, "messages" => messages)
    # Deprecated at OpenAI in favour of max_completion_tokens (#L42574-L42586), but it is the
    # field compatible servers accept. UNVERIFIED per server.
    req.max_tokens === nothing || (body["max_tokens"] = req.max_tokens)
    req.stream && (body["stream"] = true)   # #L42521
    # ChatCompletionTool #L41167-L41183 wrapping FunctionObject #L49838-L49870
    isempty(req.tools) || (body["tools"] = [Dict("type" => "function", "function" => _function_json(t))
                                            for t in req.tools])
    return body
end

_chat_messages!(ms, m::UserMessage) = push!(ms, Dict{String,Any}("role" => "user", "content" => string(m)))

# Assistant message with tool_calls #L40454-L40520 (ChatCompletionMessageToolCall #L40242-L40277)
function _chat_messages!(ms, m::AssistantMessage)
    text, calls = string(m), _tool_calls(m)
    d = Dict{String,Any}("role" => "assistant", "content" => isempty(text) && !isempty(calls) ? nothing : text)
    isempty(calls) || (d["tool_calls"] = [Dict("id" => c.id, "type" => "function",
        "function" => Dict("name" => c.name, "arguments" => JSON.json(c.arguments))) for c in calls])
    push!(ms, d)
end

# ChatCompletionRequestToolMessage #L40800-L40830, one per result
_chat_messages!(ms, m::ToolResultMessage) = foreach(m.content) do r
    push!(ms, Dict{String,Any}("role" => "tool", "tool_call_id" => r.call_id, "content" => r.content))
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
    for tc in something(get(msg, "tool_calls", nothing), ())
        f = tc["function"]
        push!(parts, ToolCall(tc["id"], f["name"], _arguments(get(f, "arguments", nothing))))
    end
    fr = get(choice, "finish_reason", nothing)
    reason = refusal !== nothing ? :refusal :
             fr == "stop" ? :end_turn :
             fr == "length" ? :max_tokens :
             fr in ("tool_calls", "function_call") ? :tool_use :
             fr == "content_filter" ? :content_filter : :other
    reason = _stop_reason(parts, reason)
    usage = _usage(get(json, "usage", nothing), "prompt_tokens", "completion_tokens")
    return AssistantMessage(parts; model = req.model, stop_reason = reason, usage,
                            id = get(json, "id", nothing))
end

# Chunks: CreateChatCompletionStreamResponse #L42853 (choices[].delta #L41065, finish_reason;
# usage only with stream_options.include_usage, not sent). The stream ends with `data: [DONE]`.
# Tool calls arrive as delta.tool_calls chunks keyed by `index` (#L40278-L40310).
mutable struct _ChatStream
    id::Any
    content::IOBuffer
    refusal::IOBuffer
    calls::Dict{Int,Vector{Any}}   # index => [id, name, arguments buffer]
    finish_reason::Any
    usage::Any
end
_stream_state(::_ChatCompletionsAPI, req::_Request) =
    _ChatStream(nothing, IOBuffer(), IOBuffer(), Dict(), nothing, nothing)

function _stream_event!(st::_ChatStream, data::AbstractString, on_text)
    strip(data) == "[DONE]" && return nothing
    ev = JSON.parse(data)
    st.id = something(get(ev, "id", nothing), Some(st.id))
    u = get(ev, "usage", nothing)
    u === nothing || (st.usage = u)
    for c in something(get(ev, "choices", nothing), ())
        d = something(get(c, "delta", nothing), Dict())
        for (key, buf) in (("content", st.content), ("refusal", st.refusal))
            t = get(d, key, nothing)
            t isa AbstractString && !isempty(t) && (write(buf, t); on_text(t))
        end
        for tc in something(get(d, "tool_calls", nothing), ())
            call = get!(() -> Any[nothing, nothing, IOBuffer()], st.calls, something(get(tc, "index", 0), 0))
            id = get(tc, "id", nothing)
            id === nothing || (call[1] = id)
            f = something(get(tc, "function", nothing), Dict())
            name = get(f, "name", nothing)
            name === nothing || (call[2] = name)
            args = get(f, "arguments", nothing)
            args isa AbstractString && write(call[3], args)
        end
        fr = get(c, "finish_reason", nothing)
        fr === nothing || (st.finish_reason = fr)
    end
    return nothing
end

function _stream_finish(st::_ChatStream, req::_Request)
    refusal = String(take!(st.refusal))
    msg = Dict{String,Any}("content" => String(take!(st.content)),
                           "refusal" => isempty(refusal) ? nothing : refusal,
                           "tool_calls" => [Dict("id" => string(something(c[1], "call_$i")),
                                                 "function" => Dict("name" => string(c[2]),
                                                                    "arguments" => String(take!(c[3]))))
                                            for (i, c) in sort!(collect(st.calls); by = first)])
    json = Dict{String,Any}("id" => st.id, "usage" => st.usage,
                            "choices" => [Dict("message" => msg, "finish_reason" => st.finish_reason)])
    return _parse_reply(_ChatCompletionsAPI(), req, json)
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
