"""
    Google(; base_url, api_key_env)

The Google Gemini API. Unset fields come from Preferences, then from the defaults
`https://generativelanguage.googleapis.com` and `GEMINI_API_KEY`.

Requests use the Interactions API (`POST /v1beta/interactions`).
"""
struct Google <: AbstractProvider
    base_url::String
    api_key_env::String
    Google(base_url::AbstractString, api_key_env::AbstractString) =
        new(_normalize_url(base_url), _check_env_name(api_key_env))
end
Google(; base_url = nothing, api_key_env = nothing) =
    Google(_resolve_first_party(Google, base_url, api_key_env)...)

"""
    GoogleEnterprise(; project, location, service_account_path = nothing, api = :generate_content)

Gemini on Google Cloud: the Gemini Enterprise Agent Platform (Vertex AI). Unset keywords come
from Preferences. `project` and `location` (e.g. `"us-central1"` or `"global"`) have no
default, so the constructor throws until they are passed or saved with
[`configure_provider!`](@ref).

It authenticates with a Google Cloud OAuth2 access token, never an API key. Credentials are
looked up in order: the service-account key file at `service_account_path`, the file named by
`ENV["GOOGLE_APPLICATION_CREDENTIALS"]`, Application Default Credentials (from
`gcloud auth application-default login`), then the GCE/GKE metadata server. The token is
fetched on first use, kept on the provider value, and fetched again before it expires.

`api` picks the wire format:

- `:generate_content` (default): Vertex AI's `generateContent`. The full history is sent every
  turn.
- `:interactions`: the Interactions API that [`Google`](@ref) uses, which continues from the
  stored reply. On Vertex AI it does not handle tool results reliably.

Only Google's own models are supported, not Vertex AI partner models.

```julia
configure_provider!(GoogleEnterprise(project = "my-project", location = "global"))
chat!(Session("google_enterprise/gemini-2.5-flash"), "Hello")
```
"""
struct GoogleEnterprise <: AbstractProvider
    project::String
    location::String
    service_account_path::Union{Nothing,String}
    api::Symbol
    _token::Base.RefValue{Union{Nothing,_GCPAccessKey}}
    function GoogleEnterprise(project::AbstractString, location::AbstractString,
                              service_account_path::Union{Nothing,AbstractString}, api::Symbol)
        api in (:generate_content, :interactions) ||
            throw(ArgumentError("api must be :generate_content or :interactions, got :$api"))
        return new(String(project), String(location),
                   service_account_path === nothing ? nothing : String(service_account_path), api,
                   Ref{Union{Nothing,_GCPAccessKey}}(nothing))
    end
end

# The token cache is not part of a provider's identity.
Base.:(==)(a::GoogleEnterprise, b::GoogleEnterprise) =
    a.project == b.project && a.location == b.location &&
    a.service_account_path == b.service_account_path && a.api == b.api

# Also keeps the cached access token out of the REPL and logs.
function Base.show(io::IO, p::GoogleEnterprise)
    print(io, "GoogleEnterprise(project = ", repr(p.project), ", location = ", repr(p.location))
    p.service_account_path === nothing || print(io, ", service_account_path = ", repr(p.service_account_path))
    p.api === :generate_content || print(io, ", api = :", p.api)
    print(io, ")")
end

# Wire formats the Google providers speak. Google itself only ever speaks Interactions.
struct _InteractionsAPI end
struct _GenerateContentAPI end

# google/interactions.openapi.json#L9-L14
provider_name(::Type{Google}) = "google"
default_base_url(::Type{Google}) = "https://generativelanguage.googleapis.com"
default_api_key_env(::Type{Google}) = "GEMINI_API_KEY"
api_version(::Type{Google}) = "v1beta"

# google/interactions.openapi.json#L10338-L10340
_auth_headers(p::Google) = ["x-goog-api-key" => _api_key(p)]

# GET /v1beta/models, page-token pagination. https://ai.google.dev/api/models
# Keeping only generateContent models is an UNVERIFIED proxy for Interactions support.
function _list_models(p::Google, fetch)
    url = string(p.base_url, "/", api_version(Google), "/models")
    models = Model{Google}[]
    token = nothing
    while true
        query = Dict("pageSize" => "1000")
        token === nothing || (query["pageToken"] = token)
        page = fetch(url; query)
        for m in get(page, "models", ())
            "generateContent" in get(m, "supportedGenerationMethods", ()) || continue
            push!(models, Model(p, String(chopprefix(m["name"], "models/"))))
        end
        token = get(page, "nextPageToken", nothing)
        (token === nothing || isempty(token)) && return models
    end
end

# CreateModelInteractionParams.store, google/interactions.openapi.json#L3850;
# stored by default: gemini-docs/gemini-docs-069-interactions-overview.md#L16-L19
_has_store_field(::Type{Google}) = true
# previous_interaction_id #L3904; gemini-docs-069-interactions-overview.md#L147-L152, #L295-L300
_supports_chaining(::Type{Google}) = true

# POST /{api_version}/interactions, google/interactions.openapi.json#L1142
_request_url(p::Google) = string(p.base_url, "/", api_version(Google), "/interactions")

# Stateless replay as a Step list: gemini-docs/gemini-docs-002-get-started.md#L656-L686.
# UserInputStep #L9639, ModelOutputStep #L7523, TextContent #L8529
_text_content(text) = [Dict("type" => "text", "text" => text)]

_google_steps(m::UserMessage) = Any[Dict("type" => "user_input", "content" => _text_content(string(m)))]

# FunctionCallStep #L5145 (thought steps are not kept: see todos/pending/4_MESSAGES_replay_reasoning.md)
function _google_steps(m::AssistantMessage)
    text = string(m)
    steps = isempty(text) ? Any[] : Any[Dict("type" => "model_output", "content" => _text_content(text))]
    for c in _tool_calls(m)
        push!(steps, Dict("type" => "function_call", "id" => c.id, "name" => c.name, "arguments" => c.arguments))
    end
    return steps
end

# FunctionResultStep #L5239; gemini-docs/gemini-docs-036-function-calling.md#L1175-L1193
_google_steps(m::ToolResultMessage) = Any[
    merge(Dict{String,Any}("type" => "function_result", "call_id" => r.call_id, "name" => r.name,
                           "result" => r.content),
          r.is_error ? Dict{String,Any}("is_error" => true) : Dict{String,Any}()) for r in m.content]

_request_body(p::Google, req::_Request) = _request_body(_InteractionsAPI(), p, req)

function _request_body(::_InteractionsAPI, p, req::_Request)
    input = Any[]
    foreach(m -> append!(input, _google_steps(m)), _replayable(req.messages))
    body = Dict{String,Any}("model" => req.model.id, "input" => input, "store" => req.store)
    req.system === nothing || (body["system_instruction"] = req.system)
    req.previous_id === nothing || (body["previous_interaction_id"] = req.previous_id)
    # GenerationConfig.max_output_tokens #L5314
    req.max_tokens === nothing ||
        (body["generation_config"] = Dict("max_output_tokens" => req.max_tokens))
    req.stream && (body["stream"] = true)   # CreateModelInteractionParams.stream #L3983
    # tools #L3992, Function #L5093-L5115; parameter-schema subset UNVERIFIED
    # (provider_reviews/4_TOOLS_function_calling.md)
    isempty(req.tools) || (body["tools"] = [_function_json(t; type = "function") for t in req.tools])
    return body
end

_parse_reply(::Google, req::_Request, json) = _parse_reply(_InteractionsAPI(), req, json)

# Interaction #L6412 (status enum, steps, usage); Usage #L9561; Error #L4795
function _parse_reply(::_InteractionsAPI, req::_Request, json)
    status = get(json, "status", nothing)
    if status == "failed"
        errs = something(get(json, "errors", nothing), [])
        error("google interaction failed: ",
              isempty(errs) ? "(no error details)" : join(map(_error_message, errs), "; "))
    end
    parts = AbstractContentPart[]
    for step in something(get(json, "steps", nothing), ())
        st = get(step, "type", nothing)
        if st == "function_call"
            push!(parts, ToolCall(step["id"], step["name"], _arguments(get(step, "arguments", nothing))))
            continue
        end
        st == "model_output" || continue
        for c in something(get(step, "content", nothing), ())
            get(c, "type", nothing) == "text" && push!(parts, TextPart(c["text"]))
        end
    end
    reason = status == "completed" ? :end_turn :
             status == "incomplete" ? :max_tokens :
             status == "requires_action" ? :tool_use : :other
    reason = _stop_reason(parts, reason)
    usage = _usage(get(json, "usage", nothing), "total_input_tokens", "total_output_tokens")
    return AssistantMessage(parts; model = req.model, stop_reason = reason, usage,
                            id = get(json, "id", nothing))
end

# InteractionSseEvent (discriminator event_type): interaction.created / .status_update /
# .completed, step.start / .delta / .stop, error. Text arrives as step.delta `{type: "text"}`
# inside a model_output step. gemini-docs/gemini-docs-070-streaming.md#L133-L184. A function_call
# step starts with `arguments: {}` and streams `arguments_delta` strings (#L207-L250).
# The stream ends with a non-JSON sentinel `event: done` / `data: [DONE]` (#L168-L169).
_supports_streaming(::Type{Google}) = true

mutable struct _GoogleStream
    steps::Dict{Int,String}      # step index => step type
    text::Dict{Int,IOBuffer}     # model_output step index => text
    calls::Dict{Int,Vector{Any}} # function_call step index => [id, name, start arguments, delta buffer]
    interaction::Any             # partial Interaction from interaction.created / .completed
    status::Any
    error::Union{Nothing,String}
end
_stream_state(::Google, req::_Request) = _stream_state(_InteractionsAPI(), req)
_stream_state(::_InteractionsAPI, req::_Request) = _GoogleStream(Dict(), Dict(), Dict(), nothing, nothing, nothing)

function _stream_event!(st::_GoogleStream, data::AbstractString, on_text)
    strip(data) == "[DONE]" && return nothing
    ev = JSON.parse(data)
    t = get(ev, "event_type", nothing)
    if t == "step.start"
        step = ev["step"]
        st.steps[ev["index"]] = string(get(step, "type", ""))
        get(step, "type", nothing) == "function_call" && (st.calls[ev["index"]] =
            Any[step["id"], step["name"], get(step, "arguments", nothing), IOBuffer()])
    elseif t == "step.delta"
        d = ev["delta"]
        if get(d, "type", nothing) == "text" && get(st.steps, ev["index"], "model_output") == "model_output"
            write(get!(IOBuffer, st.text, ev["index"]), d["text"])
            on_text(d["text"])
        elseif get(d, "type", nothing) == "arguments_delta" && haskey(st.calls, ev["index"])
            write(st.calls[ev["index"]][4], string(get(d, "arguments", "")))
        end
    elseif t in ("interaction.created", "interaction.completed")
        st.interaction = ev["interaction"]
        st.status = get(st.interaction, "status", st.status)
    elseif t == "interaction.status_update"
        st.status = get(ev, "status", st.status)
    elseif t == "error"
        st.error = _error_message(get(ev, "error", nothing))
    end
    return nothing
end

function _stream_finish(st::_GoogleStream, req::_Request)
    st.error === nothing || error("google stream error: ", st.error)
    i = something(st.interaction, Dict())
    function step(k)
        haskey(st.text, k) && return Dict("type" => "model_output", "content" => _text_content(String(take!(st.text[k]))))
        id, name, start, buf = st.calls[k]
        streamed = String(take!(buf))
        return Dict("type" => "function_call", "id" => id, "name" => name,
                    "arguments" => isempty(streamed) ? start : streamed)
    end
    steps = [step(k) for k in sort!(collect(union(keys(st.text), keys(st.calls))))]
    json = Dict{String,Any}("id" => get(i, "id", nothing), "status" => st.status,
                            "usage" => get(i, "usage", nothing), "steps" => steps,
                            "errors" => get(i, "errors", nothing))
    return _parse_reply(_InteractionsAPI(), req, json)
end

_coalesce(explicit, saved) = explicit === nothing ? saved : explicit

function GoogleEnterprise(; project = nothing, location = nothing, service_account_path = nothing,
                          api = nothing)
    t = _provider_prefs(provider_name(GoogleEnterprise))
    project = _coalesce(project, get(t, "project", nothing))
    location = _coalesce(location, get(t, "location", nothing))
    service_account_path = _coalesce(service_account_path, get(t, "service_account_path", nothing))
    api = _coalesce(api, get(t, "api", nothing))
    project === nothing && throw(ArgumentError(
        "GoogleEnterprise needs a project; pass `project = \"my-project\"` or save one first " *
        "with `configure_provider!(GoogleEnterprise(; project = \"my-project\", location = \"...\"))`"))
    location === nothing && throw(ArgumentError(
        "GoogleEnterprise needs a location, e.g. \"us-central1\" or \"global\""))
    return GoogleEnterprise(project, location, service_account_path,
                            api === nothing ? :generate_content : Symbol(api))
end

provider_name(::Type{GoogleEnterprise}) = "google_enterprise"

# aiplatform.{location}.googleapis.com, except the "global" location which has no prefix.
# aiplatform-spec.json#L36733 (rootUrl); regional routing per python-genai's _api_client.py.
_gcp_location_url(location::AbstractString) =
    location == "global" ? "https://aiplatform.googleapis.com" :
                            "https://$(location)-aiplatform.googleapis.com"

function _gcp_access_token(p::GoogleEnterprise)
    key = p._token[]
    key !== nothing && !_is_expired(key) && return key.token
    token = _fetch_gcp_access_token(p.service_account_path)
    p._token[] = _GCPAccessKey(token, Dates.now() + _GCP_TOKEN_LIFETIME)
    return token
end

_auth_headers(p::GoogleEnterprise) = ["Authorization" => "Bearer $(_gcp_access_token(p))",
                                      "x-goog-user-project" => p.project]

_wire(p::GoogleEnterprise) = p.api === :interactions ? _InteractionsAPI() : _GenerateContentAPI()

_request_url(p::GoogleEnterprise, req::_Request) = _request_url(_wire(p), p, req)
_request_body(p::GoogleEnterprise, req::_Request) = _request_body(_wire(p), p, req)
_parse_reply(p::GoogleEnterprise, req::_Request, json) = _parse_reply(_wire(p), req, json)
_stream_state(p::GoogleEnterprise, req::_Request) = _stream_state(_wire(p), req)

_vertex_scope(p::GoogleEnterprise, version) = string(_gcp_location_url(p.location), "/", version,
                                                     "/projects/", p.project, "/locations/", p.location)

# Same Interactions resource as Google (v1beta1 only), at the project/location-scoped path.
_request_url(::_InteractionsAPI, p::GoogleEnterprise, ::_Request) = _vertex_scope(p, "v1beta1") * "/interactions"

# Only the Interactions wire stores replies server-side; generateContent is stateless.
_has_store_field(p::GoogleEnterprise) = p.api === :interactions
_supports_chaining(p::GoogleEnterprise) = p.api === :interactions
_supports_streaming(::Type{GoogleEnterprise}) = true

# --- generateContent (Vertex AI v1) ---------------------------------------------------------
# aiplatform.projects.locations.publishers.models.generateContent / streamGenerateContent,
# ai-platform-spec.json#L16296-L16357. Streaming as SSE needs `?alt=sse`, which the discovery doc's
# `alt` enum (#L36773) omits; python-genai uses it (libs/python-genai/google/genai/models.py#L4753).
function _request_url(::_GenerateContentAPI, p::GoogleEnterprise, req::_Request)
    base = string(_vertex_scope(p, "v1"), "/publishers/google/models/", req.model.id)
    return req.stream ? base * ":streamGenerateContent?alt=sse" : base * ":generateContent"
end

# FunctionCall.id is optional (#L65345). When the model omits it JAIL makes one up to pair the
# call with its ToolResult, and never sends that made-up id back.
const _SYNTHETIC_CALL_ID = "jail_call_"
_wire_call_id(id::AbstractString) = startswith(id, _SYNTHETIC_CALL_ID) ? nothing : id

# Part.thoughtSignature (#L70413-L70488) must go back on the functionCall part it came with; kept
# here by call id because ToolCall has no field for it.
const _THOUGHT_SIGNATURES = Dict{String,String}()

_gc_text(text) = Dict{String,Any}("text" => text)

# Content #L65205-L65226: role "user" or "model"; Part #L70413-L70488
_gc_contents!(cs, m::UserMessage) = push!(cs, Dict("role" => "user", "parts" => [_gc_text(string(m))]))

function _gc_contents!(cs, m::AssistantMessage)
    text = string(m)
    parts = isempty(text) ? Any[] : Any[_gc_text(text)]
    for c in _tool_calls(m)
        call = Dict{String,Any}("name" => c.name, "args" => c.arguments)
        id = _wire_call_id(c.id)
        id === nothing || (call["id"] = id)
        part = Dict{String,Any}("functionCall" => call)
        sig = get(_THOUGHT_SIGNATURES, c.id, nothing)
        sig === nothing || (part["thoughtSignature"] = sig)
        push!(parts, part)
    end
    push!(cs, Dict("role" => "model", "parts" => parts))
end

# FunctionResponse #L56327-L56370: `response.output`, or `response.error` for a failed call
function _gc_contents!(cs, m::ToolResultMessage)
    parts = map(m.content) do r
        resp = Dict{String,Any}("name" => r.name,
                                "response" => Dict(r.is_error ? "error" => r.content : "output" => r.content))
        id = _wire_call_id(r.call_id)
        id === nothing || (resp["id"] = id)
        Dict{String,Any}("functionResponse" => resp)
    end
    push!(cs, Dict("role" => "user", "parts" => parts))
end

# GenerateContentRequest #L63405-L63460
function _request_body(::_GenerateContentAPI, p, req::_Request)
    contents = Any[]
    foreach(m -> _gc_contents!(contents, m), _replayable(req.messages))
    body = Dict{String,Any}("contents" => contents)
    req.system === nothing || (body["systemInstruction"] = Dict("parts" => [_gc_text(req.system)]))
    # GenerationConfig.maxOutputTokens #L44118
    req.max_tokens === nothing || (body["generationConfig"] = Dict("maxOutputTokens" => req.max_tokens))
    # Tool.functionDeclarations #L43019; FunctionDeclaration.parametersJsonSchema #L68049 takes
    # plain JSON Schema (`parameters` is the narrower OpenAPI subset, no ["t", "null"] types)
    isempty(req.tools) || (body["tools"] = [Dict("functionDeclarations" =>
        [_function_json(t; schema_key = "parametersJsonSchema") for t in req.tools])])
    return body
end

# Candidate.finishReason #L46412-L46450
function _gc_stop_reason(fr)
    fr == "STOP" && return :end_turn
    fr == "MAX_TOKENS" && return :max_tokens
    fr in ("SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII", "MODEL_ARMOR") &&
        return :content_filter
    return :other
end

# GenerateContentResponse #L65127-L65165; Candidate #L46380-L46474; UsageMetadata #L70563-L70652
function _parse_reply(::_GenerateContentAPI, req::_Request, json)
    candidates = something(get(json, "candidates", nothing), ())
    parts = AbstractContentPart[]
    fr = nothing
    if isempty(candidates)
        # promptFeedback is set when the prompt itself was blocked (#L65131-L65135)
        get(json, "promptFeedback", nothing) === nothing || (fr = "SAFETY")
    else
        cand = first(candidates)
        fr = get(cand, "finishReason", nothing)
        content = something(get(cand, "content", nothing), Dict())
        for part in something(get(content, "parts", nothing), ())
            if haskey(part, "functionCall")
                f = part["functionCall"]
                id = something(get(f, "id", nothing), _SYNTHETIC_CALL_ID * Random.randstring(12))
                sig = get(part, "thoughtSignature", nothing)
                sig === nothing || (_THOUGHT_SIGNATURES[id] = sig)
                push!(parts, ToolCall(id, f["name"], _arguments(get(f, "args", nothing))))
            elseif haskey(part, "text") && get(part, "thought", false) !== true
                push!(parts, TextPart(part["text"]))
            end
        end
    end
    reason = _stop_reason(parts, _gc_stop_reason(fr))
    usage = _usage(get(json, "usageMetadata", nothing), "promptTokenCount", "candidatesTokenCount")
    return AssistantMessage(parts; model = req.model, stop_reason = reason, usage,
                            id = get(json, "responseId", nothing))
end

# Each SSE event is a whole GenerateContentResponse chunk: text arrives in pieces, a functionCall
# part arrives complete, usageMetadata and finishReason come with the last chunk.
mutable struct _GenerateContentStream
    parts::Vector{Dict{String,Any}}   # merged candidate parts, in arrival order
    finish_reason::Any
    usage::Any
    id::Any
    error::Union{Nothing,String}
end
_stream_state(::_GenerateContentAPI, req::_Request) = _GenerateContentStream(Dict{String,Any}[], nothing, nothing, nothing, nothing)

function _stream_event!(st::_GenerateContentStream, data::AbstractString, on_text)
    isempty(strip(data)) && return nothing
    ev = JSON.parse(data)
    if haskey(ev, "error")
        st.error = _error_message(ev["error"])
        return nothing
    end
    st.id = something(get(ev, "responseId", nothing), Some(st.id))
    u = get(ev, "usageMetadata", nothing)
    u === nothing || (st.usage = u)
    get(ev, "promptFeedback", nothing) === nothing || (st.finish_reason = something(st.finish_reason, "SAFETY"))
    for cand in something(get(ev, "candidates", nothing), ())
        fr = get(cand, "finishReason", nothing)
        fr === nothing || (st.finish_reason = fr)
        content = something(get(cand, "content", nothing), Dict())
        for part in something(get(content, "parts", nothing), ())
            text = get(part, "text", nothing)
            if text isa AbstractString && get(part, "thought", false) !== true && !haskey(part, "functionCall")
                isempty(text) && continue
                prev = isempty(st.parts) ? nothing : st.parts[end]
                if prev !== nothing && haskey(prev, "text")
                    prev["text"] *= text
                else
                    push!(st.parts, Dict{String,Any}("text" => text))
                end
                on_text(text)
            elseif haskey(part, "functionCall")
                push!(st.parts, Dict{String,Any}(part))
            end
        end
    end
    return nothing
end

function _stream_finish(st::_GenerateContentStream, req::_Request)
    st.error === nothing || error("google_enterprise stream error: ", st.error)
    json = Dict{String,Any}("responseId" => st.id, "usageMetadata" => st.usage,
                            "candidates" => [Dict("content" => Dict("parts" => st.parts),
                                                  "finishReason" => st.finish_reason)])
    return _parse_reply(_GenerateContentAPI(), req, json)
end

# GET /v1beta1/publishers/google/models, on the global host with no project/location path (billed
# via the x-goog-user-project header instead); confirmed live, not in ai-platform-spec.json.
# Page-token pagination, max pageSize 300. There is no capability field to filter on, so the
# whole Google catalog comes back, including non-text models.
function _list_models(p::GoogleEnterprise, fetch)
    url = "https://aiplatform.googleapis.com/v1beta1/publishers/google/models"
    models = Model{GoogleEnterprise}[]
    token = nothing
    while true
        query = Dict("pageSize" => "300")   # server-enforced max
        token === nothing || (query["pageToken"] = token)
        page = fetch(url; query)
        for m in get(page, "publisherModels", ())
            push!(models, Model(p, String(chopprefix(m["name"], "publishers/google/models/"))))
        end
        token = get(page, "nextPageToken", nothing)
        (token === nothing || isempty(token)) && return models
    end
end

