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
_step_type(::UserMessage) = "user_input"
_step_type(::AssistantMessage) = "model_output"

function _request_body(p::Google, req::_Request)
    input = [Dict("type" => _step_type(m),
                  "content" => [Dict("type" => "text", "text" => string(m))])
             for m in _replayable(req.messages)]
    body = Dict{String,Any}("model" => req.model.id, "input" => input, "store" => req.store)
    req.system === nothing || (body["system_instruction"] = req.system)
    req.previous_id === nothing || (body["previous_interaction_id"] = req.previous_id)
    # GenerationConfig.max_output_tokens #L5314
    req.max_tokens === nothing ||
        (body["generation_config"] = Dict("max_output_tokens" => req.max_tokens))
    req.stream && (body["stream"] = true)   # CreateModelInteractionParams.stream #L3983
    return body
end

# Interaction #L6412 (status enum, steps, usage); Usage #L9561; Error #L4795
function _parse_reply(::Google, req::_Request, json)
    status = get(json, "status", nothing)
    if status == "failed"
        errs = something(get(json, "errors", nothing), [])
        error("google interaction failed: ",
              isempty(errs) ? "(no error details)" : join(map(_error_message, errs), "; "))
    end
    parts = AbstractContentPart[]
    for step in something(get(json, "steps", nothing), ())
        get(step, "type", nothing) == "model_output" || continue
        for c in something(get(step, "content", nothing), ())
            get(c, "type", nothing) == "text" && push!(parts, TextPart(c["text"]))
        end
    end
    reason = status == "completed" ? :end_turn :
             status == "incomplete" ? :max_tokens :
             status == "requires_action" ? :tool_use : :other
    usage = _usage(get(json, "usage", nothing), "total_input_tokens", "total_output_tokens")
    return AssistantMessage(parts; model = req.model, stop_reason = reason, usage,
                            id = get(json, "id", nothing))
end

# InteractionSseEvent (discriminator event_type): interaction.created / .status_update /
# .completed, step.start / .delta / .stop, error. Text arrives as step.delta `{type: "text"}`
# inside a model_output step. gemini-docs/gemini-docs-070-streaming.md#L133-L184
_supports_streaming(::Type{Google}) = true

mutable struct _GoogleStream
    steps::Dict{Int,String}      # step index => step type
    text::Dict{Int,IOBuffer}     # model_output step index => text
    interaction::Any             # partial Interaction from interaction.created / .completed
    status::Any
    error::Union{Nothing,String}
end
_stream_state(::Google, req::_Request) = _GoogleStream(Dict(), Dict(), nothing, nothing, nothing)

function _stream_event!(st::_GoogleStream, data::AbstractString, on_text)
    ev = JSON.parse(data)
    t = get(ev, "event_type", nothing)
    if t == "step.start"
        st.steps[ev["index"]] = string(get(ev["step"], "type", ""))
    elseif t == "step.delta"
        d = ev["delta"]
        if get(d, "type", nothing) == "text" && get(st.steps, ev["index"], "model_output") == "model_output"
            write(get!(IOBuffer, st.text, ev["index"]), d["text"])
            on_text(d["text"])
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
    steps = [Dict("type" => "model_output",
                  "content" => [Dict("type" => "text", "text" => String(take!(st.text[k])))])
             for k in sort!(collect(keys(st.text)))]
    json = Dict{String,Any}("id" => get(i, "id", nothing), "status" => st.status,
                            "usage" => get(i, "usage", nothing), "steps" => steps,
                            "errors" => get(i, "errors", nothing))
    return _parse_reply(req.model.provider, req, json)
end
