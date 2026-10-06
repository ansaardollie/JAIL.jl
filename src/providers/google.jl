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
    GoogleEnterprise(; project, location, service_account_path = nothing, api = :interactions)

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

- `:interactions` (default): the Interactions API that [`Google`](@ref) uses, which continues
  from the stored reply. On Vertex AI it serves Gemini 3 models only (Gemini 2.5 models are
  rejected) and is not available in every location.
- `:generate_content`: Vertex AI's `generateContent`, for any Gemini model. The full history is
  sent every turn.

Only Google's own models are supported, not Vertex AI partner models.

```julia
configure_provider!(GoogleEnterprise(project = "my-project", location = "global"))
chat!(Session("google_enterprise/gemini-3.1-flash-lite"), "Hello")
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
    p.api === :interactions || print(io, ", api = :", p.api)
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

_google_steps(m::UserMessage, p) = Any[Dict("type" => "user_input", "content" => _text_content(string(m)))]

# FunctionCallStep #L5145, ThoughtStep #L8706. Thought steps must be resent exactly as received in a
# full replay: gemini-docs/gemini-docs-034-thought-signatures.md#L725-L731
function _google_steps(m::AssistantMessage, p)
    steps = Any[]
    for c in m.content
        if c isa TextPart && !isempty(c.text)
            last = isempty(steps) ? nothing : steps[end]
            if last !== nothing && last["type"] == "model_output"
                last["content"][end]["text"] *= c.text
            else
                push!(steps, Dict{String,Any}("type" => "model_output", "content" => _text_content(c.text)))
            end
        elseif c isa ToolCall
            push!(steps, Dict{String,Any}("type" => "function_call", "id" => c.id, "name" => c.name,
                                          "arguments" => c.arguments))
        elseif c isa ReasoningPart && _replays(c, m, p, :google_interactions)
            push!(steps, c.data)
        end
    end
    return steps
end

# FunctionResultStep #L5239-L5300. `result` as TextContent items, as in the spec's example: Vertex AI
# ignores a plain-string result (the model answers without it).
_google_steps(m::ToolResultMessage, p) = Any[
    merge(Dict{String,Any}("type" => "function_result", "call_id" => r.call_id, "name" => r.name,
                           "result" => _text_content(r.content)),
          r.is_error ? Dict{String,Any}("is_error" => true) : Dict{String,Any}()) for r in m.content]

_request_body(p::Google, req::_Request) = _request_body(_InteractionsAPI(), p, req)

function _request_body(::_InteractionsAPI, p, req::_Request)
    input = Any[]
    foreach(m -> append!(input, _google_steps(m, p)), _replayable(req.messages))
    body = Dict{String,Any}("model" => req.model.id, "input" => input, "store" => req.store)
    req.system === nothing || (body["system_instruction"] = req.system)
    req.previous_id === nothing || (body["previous_interaction_id"] = req.previous_id)
    # GenerationConfig #L5314: max_output_tokens, thinking_level (ThinkingLevel #L8654),
    # thinking_summaries (ThinkingSummaries #L8676). `temperature` is not in the spec's
    # GenerationConfig but is documented there (gemini-docs/gemini-docs-027-text-generation.md#L343-L355;
    # deprecated on the latest models, gemini-docs-087-changelog.md#L167-L170).
    config = Dict{String,Any}()
    req.max_tokens === nothing || (config["max_output_tokens"] = req.max_tokens)
    req.thinking_effort === nothing || (config["thinking_level"] = string(req.thinking_effort))
    req.show_reasoning && (config["thinking_summaries"] = "auto")
    req.temperature === nothing || (config["temperature"] = req.temperature)
    # GenerationConfig.tool_choice #L5362-L5390
    req.tool_choice === :none && !isempty(req.tools) && (config["tool_choice"] = "none")
    isempty(config) || (body["generation_config"] = config)
    req.stream && (body["stream"] = true)   # CreateModelInteractionParams.stream #L3983
    # tools #L3992, Function #L5093-L5115; parameter-schema subset UNVERIFIED
    # (provider_reviews/4_TOOLS_function_calling.md)
    isempty(req.tools) || (body["tools"] = [_function_json(t; type = "function") for t in req.tools])
    return body
end

_parse_reply(::Google, req::_Request, json) = _parse_reply(_InteractionsAPI(), req, json)

# POST /v1beta/models/{model}:countTokens (google/counting-tokens.md#L26). Interactions has no counting
# endpoint, so the history goes as generateContent contents; system instructions and tools need the
# `generateContentRequest` wrapper (#L39-L40), whose `model` and `contents` are required
# (https://ai.google.dev/api/batch-api#GenerateContentRequest).
_count_url(p::Google, m::AbstractModel) = string(p.base_url, "/", api_version(Google), "/models/", m.id, ":countTokens")
function _count_body(p::Google, req::_Request)
    body = _request_body(_GenerateContentAPI(), p, req)
    body["model"] = "models/" * req.model.id
    return Dict{String,Any}("generateContentRequest" => body)
end
# CountTokensResponse.totalTokens, #L809-L820 (Vertex: ai-platform-spec.json#L53549-L53572); zero may be omitted
_parse_count(::Union{Google,GoogleEnterprise}, json) = Int(get(json, "totalTokens", 0))
_count_needs_messages(::Type{Google}) = true

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
        elseif st == "thought"
            push!(parts, ReasoningPart(_summary_text(get(step, "summary", nothing)), :google_interactions, step))
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
# A thought step streams `thought_summary` deltas, then its `thought_signature` (#L207, #L240-L243;
# gemini-docs-034-thought-signatures.md#L294-L303).
_supports_streaming(::Type{Google}) = true

mutable struct _GoogleStream
    steps::Dict{Int,String}      # step index => step type
    text::Dict{Int,IOBuffer}     # model_output step index => text
    calls::Dict{Int,Vector{Any}} # function_call step index => [id, name, start arguments, delta buffer]
    thoughts::Dict{Int,Dict{String,Any}}  # thought step index => the step
    interaction::Any             # partial Interaction from interaction.created / .completed
    status::Any
    error::Union{Nothing,String}
    reasoned::Int                # index of the last thought step whose summary was reported, or -1
end
_stream_state(::Google, req::_Request) = _stream_state(_InteractionsAPI(), req)
_stream_state(::_InteractionsAPI, req::_Request) = _GoogleStream(Dict(), Dict(), Dict(), Dict(), nothing, nothing, nothing, -1)

function _stream_event!(st::_GoogleStream, data::AbstractString, on::_StreamHooks)
    strip(data) == "[DONE]" && return nothing
    ev = JSON.parse(data)
    t = get(ev, "event_type", nothing)
    if t == "step.start"
        step = ev["step"]
        st.steps[ev["index"]] = string(get(step, "type", ""))
        get(step, "type", nothing) == "function_call" && (st.calls[ev["index"]] =
            Any[step["id"], step["name"], get(step, "arguments", nothing), IOBuffer()])
        get(step, "type", nothing) == "thought" && (st.thoughts[ev["index"]] = Dict{String,Any}(step))
        # A model_output step can start with text already in it (gemini-docs-034-thought-signatures.md#L538).
        if get(step, "type", nothing) == "model_output"
            for c in something(get(step, "content", nothing), ())
                get(c, "type", nothing) == "text" || continue
                write(get!(IOBuffer, st.text, ev["index"]), c["text"])
                on.text(c["text"])
            end
        end
    elseif t == "step.delta"
        d = ev["delta"]
        if get(d, "type", nothing) == "text" && get(st.steps, ev["index"], "model_output") == "model_output"
            write(get!(IOBuffer, st.text, ev["index"]), d["text"])
            on.text(d["text"])
        elseif get(d, "type", nothing) == "arguments_delta" && haskey(st.calls, ev["index"])
            write(st.calls[ev["index"]][4], string(get(d, "arguments", "")))
        elseif get(d, "type", nothing) == "thought_summary" && haskey(st.thoughts, ev["index"])
            summary = get!(Vector{Any}, st.thoughts[ev["index"]], "summary")
            c = d["content"]
            # Deltas continue one summary text rather than adding items.
            if !isempty(summary) && get(summary[end], "type", nothing) == "text" == get(c, "type", nothing)
                summary[end] = Dict{String,Any}("type" => "text", "text" => summary[end]["text"] * c["text"])
            else
                push!(summary, c)
            end
            text = get(c, "text", nothing)
            if get(c, "type", nothing) == "text" && text isa AbstractString && !isempty(text)
                # A new thought step is separated from the previous one by a blank line.
                st.reasoned >= 0 && st.reasoned != ev["index"] && on.reasoning("\n\n")
                on.reasoning(text)
                st.reasoned = ev["index"]
            end
        elseif get(d, "type", nothing) == "thought_signature" && haskey(st.thoughts, ev["index"])
            st.thoughts[ev["index"]]["signature"] = d["signature"]
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
        haskey(st.thoughts, k) && return st.thoughts[k]
        haskey(st.text, k) && return Dict("type" => "model_output", "content" => _text_content(String(take!(st.text[k]))))
        id, name, start, buf = st.calls[k]
        streamed = String(take!(buf))
        return Dict("type" => "function_call", "id" => id, "name" => name,
                    "arguments" => isempty(streamed) ? start : streamed)
    end
    steps = [step(k) for k in sort!(collect(union(keys(st.text), keys(st.calls), keys(st.thoughts))))]
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
                            api === nothing ? :interactions : Symbol(api))
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

# publishers.models.countTokens, ai-platform-spec.json#L16210-L16240; CountTokensRequest #L49367-L49404
# takes contents, systemInstruction and tools top-level. Used whatever the `api`.
_count_url(p::GoogleEnterprise, m::AbstractModel) =
    string(_vertex_scope(p, "v1"), "/publishers/google/models/", m.id, ":countTokens")
_count_body(p::GoogleEnterprise, req::_Request) = _request_body(_GenerateContentAPI(), p, req)

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

_gc_text(text) = Dict{String,Any}("text" => text)

# Content #L65205-L65226: role "user" or "model"; Part #L70413-L70530
_gc_contents!(cs, m::UserMessage, p) = push!(cs, Dict("role" => "user", "parts" => [_gc_text(string(m))]))

# Part.thoughtSignature (#L70523) can sit on any part (gemini-docs-034-thought-signatures.md#L16).
# A ReasoningPart holding only a signature goes back onto the part that follows it; a `thought`
# part (#L70507) goes back whole.
function _gc_contents!(cs, m::AssistantMessage, p)
    parts = Any[]
    sig = nothing
    for c in m.content
        part = if c isa TextPart && !isempty(c.text)
            _gc_text(c.text)
        elseif c isa ToolCall
            call = Dict{String,Any}("name" => c.name, "args" => c.arguments)
            id = _wire_call_id(c.id)
            id === nothing || (call["id"] = id)
            Dict{String,Any}("functionCall" => call)
        elseif c isa ReasoningPart && _replays(c, m, p, :google_generate_content)
            get(c.data, "thought", false) === true || (sig = c.data["thoughtSignature"]; continue)
            copy(c.data)
        else
            continue
        end
        sig === nothing || (part["thoughtSignature"] = sig; sig = nothing)
        push!(parts, part)
    end
    sig === nothing || push!(parts, Dict{String,Any}("text" => "", "thoughtSignature" => sig))
    push!(cs, Dict("role" => "model", "parts" => parts))
end

# FunctionResponse #L56327-L56370: `response.output`, or `response.error` for a failed call
function _gc_contents!(cs, m::ToolResultMessage, p)
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
    foreach(m -> _gc_contents!(contents, m, p), _replayable(req.messages))
    body = Dict{String,Any}("contents" => contents)
    req.system === nothing || (body["systemInstruction"] = Dict("parts" => [_gc_text(req.system)]))
    # GenerationConfig #L44067: maxOutputTokens #L44118, temperature #L44175, thinkingConfig #L44193
    # (ThinkingConfig #L57798: includeThoughts #L57800, thinkingLevel enum in upper case #L57809)
    config = Dict{String,Any}()
    req.max_tokens === nothing || (config["maxOutputTokens"] = req.max_tokens)
    req.temperature === nothing || (config["temperature"] = req.temperature)
    thinking = Dict{String,Any}()
    req.thinking_effort === nothing || (thinking["thinkingLevel"] = uppercase(string(req.thinking_effort)))
    req.show_reasoning && (thinking["includeThoughts"] = true)
    isempty(thinking) || (config["thinkingConfig"] = thinking)
    isempty(config) || (body["generationConfig"] = config)
    # Tool.functionDeclarations #L43019; FunctionDeclaration.parametersJsonSchema #L68049 takes
    # plain JSON Schema (`parameters` is the narrower OpenAPI subset, no ["t", "null"] types)
    isempty(req.tools) || (body["tools"] = [Dict("functionDeclarations" =>
        [_function_json(t; schema_key = "parametersJsonSchema") for t in req.tools])])
    # Vertex ToolConfig.functionCallingConfig.mode (ai-platform-spec.json#L69685-L69699, #L38424-L38455)
    req.tool_choice === :none && !isempty(req.tools) &&
        (body["toolConfig"] = Dict("functionCallingConfig" => Dict("mode" => "NONE")))
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
            if get(part, "thought", false) === true
                push!(parts, ReasoningPart(something(get(part, "text", nothing), ""), :google_generate_content, part))
                continue
            end
            sig = get(part, "thoughtSignature", nothing)
            sig === nothing ||
                push!(parts, ReasoningPart("", :google_generate_content, Dict("thoughtSignature" => sig)))
            if haskey(part, "functionCall")
                f = part["functionCall"]
                id = something(get(f, "id", nothing), _SYNTHETIC_CALL_ID * Random.randstring(12))
                push!(parts, ToolCall(id, f["name"], _arguments(get(f, "args", nothing))))
            elseif !isempty(something(get(part, "text", nothing), ""))
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

function _stream_event!(st::_GenerateContentStream, data::AbstractString, on::_StreamHooks)
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
            sig = get(part, "thoughtSignature", nothing)
            prev = isempty(st.parts) ? nothing : st.parts[end]
            if get(part, "thought", false) === true
                # A thought summary arrives in pieces too: one part per run of thought chunks.
                if prev !== nothing && get(prev, "thought", false) === true && text isa AbstractString
                    prev["text"] = string(get(prev, "text", ""), text)
                    sig === nothing || (prev["thoughtSignature"] = sig)
                else
                    push!(st.parts, Dict{String,Any}(part))
                end
                text isa AbstractString && !isempty(text) && on.reasoning(text)
            elseif haskey(part, "functionCall")
                push!(st.parts, Dict{String,Any}(part))
            elseif text isa AbstractString
                if sig === nothing && prev !== nothing && haskey(prev, "text") && get(prev, "thought", false) !== true
                    prev["text"] *= text
                elseif sig !== nothing || !isempty(text)
                    push!(st.parts, Dict{String,Any}(part))
                end
                isempty(text) || on.text(text)
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

