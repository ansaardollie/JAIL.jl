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

function _request_body(p::Google, req::_Request)
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
_supports_streaming(::Type{Google}) = true

mutable struct _GoogleStream
    steps::Dict{Int,String}      # step index => step type
    text::Dict{Int,IOBuffer}     # model_output step index => text
    calls::Dict{Int,Vector{Any}} # function_call step index => [id, name, start arguments, delta buffer]
    interaction::Any             # partial Interaction from interaction.created / .completed
    status::Any
    error::Union{Nothing,String}
end
_stream_state(::Google, req::_Request) = _GoogleStream(Dict(), Dict(), Dict(), nothing, nothing, nothing)

function _stream_event!(st::_GoogleStream, data::AbstractString, on_text)
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
    return _parse_reply(req.model.provider, req, json)
end
