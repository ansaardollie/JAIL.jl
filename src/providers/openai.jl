"""
    OpenAI(; base_url, api_key_env)

The OpenAI API. Unset fields come from Preferences, then from the defaults
`https://api.openai.com/v1` and `OPENAI_API_KEY`.

Requests use the Responses API only (`POST /responses`).
"""
struct OpenAI <: AbstractOpenAIProvider
    base_url::String
    api_key_env::String
    OpenAI(base_url::AbstractString, api_key_env::AbstractString) =
        new(_normalize_url(base_url), _check_env_name(api_key_env))
end
OpenAI(; base_url = nothing, api_key_env = nothing) =
    OpenAI(_resolve_first_party(OpenAI, base_url, api_key_env)...)

# openapi/api_spec.yaml#L14-L15
provider_name(::Type{OpenAI}) = "openai"
default_base_url(::Type{OpenAI}) = "https://api.openai.com/v1"
default_api_key_env(::Type{OpenAI}) = "OPENAI_API_KEY"

# Shared by OpenAI and OpenAICompatible. openapi/api_spec.yaml#L110188-L110191 (bearer)
function _auth_headers(p::AbstractOpenAIProvider)
    key = _api_key(p)
    return key === nothing ? Pair{String,String}[] : ["Authorization" => "Bearer $key"]
end

# GET /models, no pagination. openapi/api_spec.yaml#L10097-L10115, #L52219-L52233
function _list_models(p::AbstractOpenAIProvider, fetch)
    return [Model(p, String(m["id"])) for m in fetch(p.base_url * "/models")["data"]]
end

# Wire formats an AbstractOpenAIProvider can speak. OpenAI itself only ever speaks Responses.
struct _ResponsesAPI end
struct _ChatCompletionsAPI end
_wire(::OpenAI) = _ResponsesAPI()

_request_url(p::AbstractOpenAIProvider) = _request_url(_wire(p), p)
_request_body(p::AbstractOpenAIProvider, req::_Request) = _request_body(_wire(p), p, req)
_parse_reply(p::AbstractOpenAIProvider, req::_Request, json) = _parse_reply(_wire(p), req, json)
_stream_state(p::AbstractOpenAIProvider, req::_Request) = _stream_state(_wire(p), req)

# Both wire formats stream (`stream: true`): Responses #L45451 via ResponseProperties, Chat #L42331
_supports_streaming(::Type{<:AbstractOpenAIProvider}) = true

# openapi/api_spec.yaml#L45529-L45538 (store, default true)
_has_store_field(::Type{OpenAI}) = true
# previous_response_id #L69250-L69257; conversation-state doc #L554-L602
_supports_chaining(::Type{OpenAI}) = true

# POST /responses. openapi/api_spec.yaml#L21038, CreateResponse #L45451-L45600
_request_url(::_ResponsesAPI, p) = p.base_url * "/responses"

function _request_body(::_ResponsesAPI, p, req::_Request)
    # EasyInputMessage with string content, #L47189-L47240; history replay as in
    # core-concepts/openai-core-concepts-02-conversation-state-20260926.md#L40-L53
    input = Any[]
    foreach(m -> _responses_items!(input, m, p), _replayable(req.messages))
    body = Dict{String,Any}("model" => req.model.id, "input" => input)
    req.system === nothing || (body["instructions"] = req.system)          # #L45539
    req.max_tokens === nothing || (body["max_output_tokens"] = req.max_tokens)  # #L45590
    _has_store_field(p) && (body["store"] = req.store)
    req.previous_id === nothing || (body["previous_response_id"] = req.previous_id)
    req.stream && (body["stream"] = true)
    # FunctionTool #L79526-L79575; `strict` omitted so the server normalises when it can
    # (tool-guides/openai-tool-guides-02-function-calling-20260926.md#L1045-L1053)
    isempty(req.tools) || (body["tools"] = [_function_json(t; type = "function") for t in req.tools])
    req.temperature === nothing || (body["temperature"] = req.temperature)   # #L54160-L54172
    # reasoning #L45481-L45484: Reasoning.effort #L66705, ReasoningEffort #L66769; summary #L66706-L66722
    reasoning = Dict{String,Any}()
    req.thinking_effort === nothing || (reasoning["effort"] = string(req.thinking_effort))
    req.show_reasoning && (reasoning["summary"] = "auto")
    isempty(reasoning) || (body["reasoning"] = reasoning)
    return body
end

function _function_json(t::ToolSpec; type = nothing, schema_key = "parameters")
    d = Dict{String,Any}("name" => t.name, schema_key => _parameters_schema(t))
    type === nothing || (d["type"] = type)
    isempty(t.description) || (d["description"] = t.description)
    return d
end

_responses_items!(input, m::UserMessage, p) = push!(input, Dict("role" => "user", "content" => string(m)))

# FunctionToolCall #L49877-L49935, re-sent without its `fc_` item id. ReasoningItem #L66801-L66868
# (`encrypted_content` returned by default) goes back as received: tool-guides/
# openai-tool-guides-02-function-calling-20260926.md#L475-L477, core-concepts/
# openai-core-concepts-02-conversation-state-20260926.md#L176
function _responses_items!(input, m::AssistantMessage, p)
    text = nothing
    for c in m.content
        if c isa TextPart && !isempty(c.text)
            if text === nothing
                text = Dict{String,Any}("role" => "assistant", "content" => c.text)
                push!(input, text)
            else
                text["content"] *= c.text
            end
            continue
        elseif c isa ToolCall
            push!(input, Dict("type" => "function_call", "call_id" => c.id, "name" => c.name,
                              "arguments" => JSON.json(c.arguments)))
        elseif c isa ReasoningPart && _replays(c, m, p, :openai_responses)
            push!(input, c.data)
        end
        text = nothing
    end
end

# FunctionCallOutputItemParam #L81074-L81130 (no error flag: the text says what went wrong)
_responses_items!(input, m::ToolResultMessage, p) =
    foreach(r -> push!(input, Dict("type" => "function_call_output", "call_id" => r.call_id,
                                   "output" => r.content)), m.content)

# Response #L66872-L67060; output message #L54863-L54913; output_text #L78719, refusal #L78800
function _parse_reply(::_ResponsesAPI, req::_Request, json)
    status = get(json, "status", nothing)
    status == "failed" && error("$(provider_name(req.model.provider)) response failed: ",
                                _error_message(get(json, "error", nothing)))
    parts = AbstractContentPart[]
    refused = false
    for item in something(get(json, "output", nothing), ())
        t = get(item, "type", nothing)
        if t == "function_call"
            push!(parts, ToolCall(item["call_id"], item["name"], _arguments(get(item, "arguments", nothing))))
            continue
        elseif t == "reasoning"
            data = Dict{String,Any}(k => v for (k, v) in item if k != "status")
            # Raw reasoning `content` (#L66853-L66858) stands in when there is no summary.
            text = _summary_text(get(item, "summary", nothing))
            isempty(text) && (text = _summary_text(get(item, "content", nothing)))
            push!(parts, ReasoningPart(text, :openai_responses, data))
            continue
        end
        t == "message" || continue
        for c in something(get(item, "content", nothing), ())
            t = get(c, "type", nothing)
            if t == "output_text"
                push!(parts, TextPart(c["text"]))
            elseif t == "refusal"
                push!(parts, TextPart(c["refusal"]))
                refused = true
            end
        end
    end
    reason = refused ? :refusal :
             status == "completed" ? :end_turn :
             status == "incomplete" ? _incomplete_reason(get(json, "incomplete_details", nothing)) :
             :other
    reason = _stop_reason(parts, reason)
    usage = _usage(get(json, "usage", nothing), "input_tokens", "output_tokens")  # #L70636
    return AssistantMessage(parts; model = req.model, stop_reason = reason, usage,
                            id = get(json, "id", nothing))
end

# POST /responses/input_tokens, #L29898-L29935: the Responses input format (TokenCountsBody
# #L84371-L84469 has no store/max_output_tokens/stream). Also used by OpenAICompatible, whatever its `api`.
_count_url(p::AbstractOpenAIProvider, ::AbstractModel) = p.base_url * "/responses/input_tokens"
_count_body(p::AbstractOpenAIProvider, req::_Request) =
    filter(kv -> kv.first in ("model", "input", "instructions", "tools"), _request_body(_ResponsesAPI(), p, req))
# TokenCountsResource #L84471-L84487
_parse_count(::AbstractOpenAIProvider, json) = Int(json["input_tokens"])

# incomplete_details.reason, #L66944-L66965
function _incomplete_reason(details)
    r = details === nothing ? nothing : get(details, "reason", nothing)
    return r == "max_output_tokens" ? :max_tokens : r == "content_filter" ? :content_filter : :other
end

# Stream events: response.output_text.delta #L70512, response.refusal.delta #L69679; the terminal
# response.completed #L67455 / .incomplete #L68572 / .failed #L67945 carry the full Response;
# error #L67898. core-concepts/openai-core-concepts-04-streaming-20260926.md#L142-L228
# Reasoning: response.reasoning_summary_text.delta #L69475-L69530 (one summary part per
# summary_index, each started by response.reasoning_summary_part.added #L69333), and
# response.reasoning_text.delta #L69577 (raw reasoning, e.g. from open-weight models).
mutable struct _ResponsesStream
    final::Any
    error::Union{Nothing,String}
    reasoned::Bool
end
_stream_state(::_ResponsesAPI, req::_Request) = _ResponsesStream(nothing, nothing, false)

function _stream_event!(st::_ResponsesStream, data::AbstractString, on::_StreamHooks)
    ev = JSON.parse(data)
    t = get(ev, "type", nothing)
    if t in ("response.output_text.delta", "response.refusal.delta")
        on.text(ev["delta"])
    elseif t == "response.reasoning_summary_part.added"
        st.reasoned && on.reasoning("\n\n")
    elseif t in ("response.reasoning_summary_text.delta", "response.reasoning_text.delta")
        d = ev["delta"]
        isempty(d) || (on.reasoning(d); st.reasoned = true)
    elseif t in ("response.completed", "response.incomplete", "response.failed")
        st.final = ev["response"]
    elseif t == "error"
        st.error = string(get(ev, "message", data))
    end
    return nothing
end

function _stream_finish(st::_ResponsesStream, req::_Request)
    name = provider_name(req.model.provider)
    st.error === nothing || error("$name stream error: ", st.error)
    st.final === nothing && error("$name stream ended without a final response")
    return _parse_reply(_ResponsesAPI(), req, st.final)
end
