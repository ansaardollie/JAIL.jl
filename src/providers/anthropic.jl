"""
    Anthropic(; base_url, api_key_env)

The Anthropic API. Unset fields come from Preferences, then from the defaults
`https://api.anthropic.com` and `ANTHROPIC_API_KEY`.

Requests use the Messages API (`POST /v1/messages`).
"""
struct Anthropic <: AbstractProvider
    base_url::String
    api_key_env::String
    Anthropic(base_url::AbstractString, api_key_env::AbstractString) =
        new(_normalize_url(base_url), _check_env_name(api_key_env))
end
Anthropic(; base_url = nothing, api_key_env = nothing) =
    Anthropic(_resolve_first_party(Anthropic, base_url, api_key_env)...)

# anthropic/api_spec.yaml (servers)
provider_name(::Type{Anthropic}) = "anthropic"
default_base_url(::Type{Anthropic}) = "https://api.anthropic.com"
default_api_key_env(::Type{Anthropic}) = "ANTHROPIC_API_KEY"
# claude-docs/claude-docs-03-get-started.md#L31-L32
anthropic_version(::Type{Anthropic}) = "2023-06-01"

# claude-docs/claude-docs-02-get-api-key.md#L45
_auth_headers(p::Anthropic) =
    ["x-api-key" => _api_key(p), "anthropic-version" => anthropic_version(Anthropic)]

# GET /v1/models, cursor pagination via after_id/last_id/has_more.
# https://platform.claude.com/docs/en/api/models/list (see provider_reviews/1_MODELS_list_models.md)
function _list_models(p::Anthropic, fetch)
    models = Model{Anthropic}[]
    query = Dict("limit" => "1000")
    while true
        page = fetch(p.base_url * "/v1/models"; query)
        append!(models, Model(p, String(m["id"])) for m in page["data"])
        last_id = get(page, "last_id", nothing)
        (get(page, "has_more", false) === true && last_id !== nothing) || return models
        query = Dict("limit" => "1000", "after_id" => String(last_id))
    end
end

# max_tokens is required: anthropic/api_spec.yaml#L3688-L3691
default_max_tokens(::Type{Anthropic}) = 8192

# POST /v1/messages. anthropic/api_spec.yaml#L6, CreateMessageParams #L3437-L3692
_request_url(p::Anthropic) = p.base_url * "/v1/messages"

function _request_body(::Anthropic, req::_Request)
    # InputMessage #L3745-L3785: role user|assistant, content blocks; system is top-level.
    # Consecutive turns of one role are merged (tool results then a prompt share a user turn).
    messages = Dict{String,Any}[]
    for m in _replayable(req.messages)
        role = m isa AssistantMessage ? "assistant" : "user"
        blocks = _anthropic_blocks(m)
        if !isempty(messages) && messages[end]["role"] == role
            append!(messages[end]["content"], blocks)
        else
            push!(messages, Dict{String,Any}("role" => role, "content" => blocks))
        end
    end
    body = Dict{String,Any}("model" => req.model.id, "messages" => messages,
                            "max_tokens" => req.max_tokens)
    req.system === nothing || (body["system"] = req.system)
    req.stream && (body["stream"] = true)   # #L3287
    # Tool #L5059-L5103; claude-docs/claude-docs-25-define-tools.md#L16-L53
    isempty(req.tools) || (body["tools"] = [_function_json(t; schema_key = "input_schema") for t in req.tools])
    return body
end

_text_block(text) = Dict{String,Any}("type" => "text", "text" => text)
_anthropic_blocks(m::UserMessage) = Any[_text_block(string(m))]

# ResponseToolUseBlock #L5015 re-sent as RequestToolUseBlock #L4967
function _anthropic_blocks(m::AssistantMessage)
    text = string(m)
    blocks = isempty(text) ? Any[] : Any[_text_block(text)]
    for c in _tool_calls(m)
        push!(blocks, Dict{String,Any}("type" => "tool_use", "id" => c.id, "name" => c.name,
                                       "input" => c.arguments))
    end
    return blocks
end

# RequestToolResultBlock #L4926-L4966; must come first in the user turn
# (claude-docs/claude-docs-26-handle-tool-calls.md#L63-L67)
_anthropic_blocks(m::ToolResultMessage) = Any[
    merge(Dict{String,Any}("type" => "tool_result", "tool_use_id" => r.call_id, "content" => r.content),
          r.is_error ? Dict{String,Any}("is_error" => true) : Dict{String,Any}()) for r in m.content]

# Message #L3823-L3960. The spec's stop_reason enum is stale; the full list is in
# claude-docs/claude-docs-07-handling-stop-reasons.md#L13-L21 (pause_turn -> :other for now)
const _ANTHROPIC_STOP = Dict(
    "end_turn" => :end_turn, "max_tokens" => :max_tokens, "stop_sequence" => :stop_sequence,
    "tool_use" => :tool_use, "refusal" => :refusal,
    "model_context_window_exceeded" => :max_tokens)

function _parse_reply(::Anthropic, req::_Request, json)
    parts = AbstractContentPart[]
    for b in json["content"]
        t = get(b, "type", nothing)
        t == "text" && push!(parts, TextPart(b["text"]))
        t == "tool_use" && push!(parts, ToolCall(b["id"], b["name"], _arguments(get(b, "input", nothing))))
    end
    reason = _stop_reason(parts, get(_ANTHROPIC_STOP, something(get(json, "stop_reason", nothing), ""), :other))
    usage = _usage(get(json, "usage", nothing), "input_tokens", "output_tokens")  # #L5172
    return AssistantMessage(parts; model = req.model, stop_reason = reason, usage,
                            id = get(json, "id", nothing))
end

# Stream events: claude-docs/claude-docs-15-streaming.md#L296-L306 (flow), #L318-L319 (error),
# #L328-L336 (text_delta), #L539-L563 (full example). message_delta usage is cumulative.
# tool_use blocks start with `input: {}` and stream input_json_delta.partial_json (#L933-L960).
_supports_streaming(::Type{Anthropic}) = true

mutable struct _AnthropicStream
    id::Any
    text::Dict{Int,IOBuffer}          # content block index => text (text blocks only)
    calls::Dict{Int,Vector{Any}}      # content block index => [id, name, input JSON buffer]
    stop_reason::Any
    input_tokens::Int
    output_tokens::Int
    error::Union{Nothing,String}
end
_stream_state(::Anthropic, req::_Request) = _AnthropicStream(nothing, Dict(), Dict(), nothing, 0, 0, nothing)

function _stream_event!(st::_AnthropicStream, data::AbstractString, on_text)
    ev = JSON.parse(data)
    t = get(ev, "type", nothing)
    if t == "message_start"
        m = ev["message"]
        st.id = get(m, "id", nothing)
        u = something(get(m, "usage", nothing), Dict())
        st.input_tokens = something(get(u, "input_tokens", 0), 0)
        st.output_tokens = something(get(u, "output_tokens", 0), 0)
    elseif t == "content_block_start"
        b = ev["content_block"]
        bt = get(b, "type", nothing)
        bt == "text" && (st.text[ev["index"]] = IOBuffer())
        bt == "tool_use" && (st.calls[ev["index"]] = Any[b["id"], b["name"], IOBuffer()])
    elseif t == "content_block_delta"
        d = ev["delta"]
        if get(d, "type", nothing) == "text_delta"
            write(get!(IOBuffer, st.text, ev["index"]), d["text"])
            on_text(d["text"])
        elseif get(d, "type", nothing) == "input_json_delta" && haskey(st.calls, ev["index"])
            write(st.calls[ev["index"]][3], d["partial_json"])
        end
    elseif t == "message_delta"
        st.stop_reason = something(get(ev["delta"], "stop_reason", nothing), Some(st.stop_reason))
        u = get(ev, "usage", nothing)
        u === nothing || (st.output_tokens = something(get(u, "output_tokens", st.output_tokens), 0))
    elseif t == "error"
        st.error = _error_message(get(ev, "error", nothing))
    end
    return nothing
end

function _stream_finish(st::_AnthropicStream, req::_Request)
    st.error === nothing || error("anthropic stream error: ", st.error)
    block(i) = haskey(st.text, i) ? _text_block(String(take!(st.text[i]))) :
        Dict{String,Any}("type" => "tool_use", "id" => st.calls[i][1], "name" => st.calls[i][2],
                         "input" => _arguments(String(take!(st.calls[i][3]))))
    blocks = [block(i) for i in sort!(collect(union(keys(st.text), keys(st.calls))))]
    json = Dict{String,Any}("id" => st.id, "content" => blocks, "stop_reason" => st.stop_reason,
                            "usage" => Dict("input_tokens" => st.input_tokens,
                                            "output_tokens" => st.output_tokens))
    return _parse_reply(req.model.provider, req, json)
end
