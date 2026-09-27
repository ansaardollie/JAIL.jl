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

# openapi/api_spec.yaml#L45529-L45538 (store, default true)
_has_store_field(::Type{OpenAI}) = true
# previous_response_id #L69250-L69257; conversation-state doc #L554-L602
_supports_chaining(::Type{OpenAI}) = true

# POST /responses. openapi/api_spec.yaml#L21038, CreateResponse #L45451-L45600
_request_url(::_ResponsesAPI, p) = p.base_url * "/responses"

function _request_body(::_ResponsesAPI, p, req::_Request)
    # EasyInputMessage with string content, #L47189-L47240; history replay as in
    # core-concepts/openai-core-concepts-02-conversation-state-20260926.md#L40-L53
    input = [Dict("role" => _role(m), "content" => string(m)) for m in _replayable(req.messages)]
    body = Dict{String,Any}("model" => req.model.id, "input" => input)
    req.system === nothing || (body["instructions"] = req.system)          # #L45539
    req.max_tokens === nothing || (body["max_output_tokens"] = req.max_tokens)  # #L45590
    _has_store_field(p) && (body["store"] = req.store)
    req.previous_id === nothing || (body["previous_response_id"] = req.previous_id)
    return body
end

# Response #L66872-L67060; output message #L54863-L54913; output_text #L78719, refusal #L78800
function _parse_reply(::_ResponsesAPI, req::_Request, json)
    status = get(json, "status", nothing)
    status == "failed" && error("$(provider_name(req.model.provider)) response failed: ",
                                _error_message(get(json, "error", nothing)))
    parts = AbstractContentPart[]
    refused = false
    for item in something(get(json, "output", nothing), ())
        get(item, "type", nothing) == "message" || continue
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
    usage = _usage(get(json, "usage", nothing), "input_tokens", "output_tokens")  # #L70636
    return AssistantMessage(parts; model = req.model, stop_reason = reason, usage,
                            id = get(json, "id", nothing))
end

# incomplete_details.reason, #L66944-L66965
function _incomplete_reason(details)
    r = details === nothing ? nothing : get(details, "reason", nothing)
    return r == "max_output_tokens" ? :max_tokens : r == "content_filter" ? :content_filter : :other
end
