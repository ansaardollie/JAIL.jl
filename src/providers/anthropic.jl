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
default_max_tokens(::Type{Anthropic}) = 128000
# Per-model output caps. 3.5 is 4096 without the max-tokens-3-5-sonnet-2024-07-15 beta header.
function default_max_tokens(m::Model{Anthropic})
    occursin("3-5", m.id) && return 4096
    occursin("haiku-4-5", m.id) && return 64000
    return default_max_tokens(Anthropic)
end

# POST /v1/messages. anthropic/api_spec.yaml#L6, CreateMessageParams #L3437-L3692
_request_url(p::Anthropic) = p.base_url * "/v1/messages"

function _request_body(p::Anthropic, req::_Request)
    # InputMessage #L3745-L3785: role user|assistant, content blocks; system is top-level.
    # Consecutive turns of one role are merged (tool results then a prompt share a user turn).
    messages = Dict{String,Any}[]
    for m in _replayable(req.messages)
        role = m isa AssistantMessage ? "assistant" : "user"
        blocks = _anthropic_blocks(m, p)
        # Search blocks go back only while the request has the search tool.
        isempty(req.deferred) && filter!(b -> !(get(b, "type", nothing) in _ANTHROPIC_SEARCH_BLOCKS), blocks)
        if !isempty(messages) && messages[end]["role"] == role
            append!(messages[end]["content"], blocks)
        else
            push!(messages, Dict{String,Any}("role" => role, "content" => blocks))
        end
    end
    body = Dict{String,Any}("model" => req.model.id, "messages" => messages,
                            "max_tokens" => req.max_tokens)
    # Automatic prompt caching: the breakpoint follows the last cacheable block as the chain grows,
    # claude-docs/claude-docs-50-prompt-caching.md#L279-L299, #L475-L489 (TTL "1h" #L487-L493)
    cache = _anthropic_cache(p)
    cache === nothing || (body["cache_control"] = cache)
    req.system === nothing || (body["system"] = req.system)
    req.stream && (body["stream"] = true)   # #L3287
    # Tool #L5059-L5103; claude-docs/claude-docs-25-define-tools.md#L16-L53
    tools = Any[_function_json(t; schema_key = "input_schema") for t in req.tools]
    # Hosted tool search: the BM25 search tool (never deferred) plus every deferred definition,
    # claude-docs/claude-docs-35-tool-search-tool.md#L66-L72, #L546-L597
    if !isempty(req.deferred)
        push!(tools, Dict{String,Any}("type" => "tool_search_tool_bm25_20251119", "name" => "tool_search_tool_bm25"))
        append!(tools, (_deferred(_function_json(t; schema_key = "input_schema")) for t in req.deferred))
    end
    isempty(tools) || (body["tools"] = tools)
    req.temperature === nothing || (body["temperature"] = req.temperature)   # #L3569-L3577
    _anthropic_thinking!(body, req)
    return body
end

# Preference `providers.anthropic.prompt_cache`: "off" (default), "5m" or "1h".
function _anthropic_cache(p::Anthropic)
    v = get(_provider_prefs(provider_name(p)), "prompt_cache", "off")
    v == "off" && return nothing
    v == "5m" && return Dict{String,Any}("type" => "ephemeral")
    v == "1h" && return Dict{String,Any}("type" => "ephemeral", "ttl" => "1h")
    throw(ArgumentError("Preference `providers.anthropic.prompt_cache` must be \"5m\", \"1h\" or \"off\", got $(repr(v))"))
end

# Neither field is in the local spec. output_config.effort: claude-docs/claude-docs-10-effort.md#L40-L58,
# levels #L237. Effort drives thinking depth only with adaptive thinking (#L346-L352); `:none` turns
# thinking off (claude-docs-21-thinking.md#L301-L314, rejected by some models #L441-L443).
# display "summarized" returns readable thinking (#L49-L51, #L449-L455); invalid when disabled (#L481).
# Without an effort no `thinking` is sent, so show_reasoning alone keeps the model's default (on
# models that default to "omitted" display, no summaries).
function _anthropic_thinking!(body, req::_Request)
    e = req.thinking_effort
    e === nothing && return body
    if e === :none
        body["thinking"] = Dict{String,Any}("type" => "disabled")
        return body
    end
    body["output_config"] = Dict{String,Any}("effort" => string(e))
    t = body["thinking"] = Dict{String,Any}("type" => "adaptive")
    req.show_reasoning && (t["display"] = "summarized")
    return body
end

# POST /v1/messages/count_tokens #L1118-L1187; BetaCountMessageTokensParams #L1527-L1711 (model,
# messages (required), system, tools); response input_tokens #L1712-L1725
_count_url(p::Anthropic, ::AbstractModel) = p.base_url * "/v1/messages/count_tokens"
_count_body(p::Anthropic, req::_Request) =
    filter(kv -> kv.first in ("model", "messages", "system", "tools"), _request_body(p, req))
_parse_count(::Anthropic, json) = Int(json["input_tokens"])
_count_needs_messages(::Type{Anthropic}) = true

_text_block(text) = Dict{String,Any}("type" => "text", "text" => text)
_anthropic_blocks(m::UserMessage, p) = Any[_text_block(string(m))]

# ResponseToolUseBlock #L5015 re-sent as RequestToolUseBlock #L4967. `thinking` and
# `redacted_thinking` blocks (not in the local spec) go back unchanged and in their original order:
# claude-docs/claude-docs-21-thinking.md#L909-L924, #L1133-L1145
function _anthropic_blocks(m::AssistantMessage, p)
    blocks = Any[]
    for c in m.content
        if c isa TextPart && !isempty(c.text)
            last = isempty(blocks) ? nothing : blocks[end]
            last !== nothing && last["type"] == "text" ? (last["text"] *= c.text) :
                push!(blocks, _text_block(c.text))
        elseif c isa ToolCall
            push!(blocks, Dict{String,Any}("type" => "tool_use", "id" => c.id, "name" => c.name,
                                           "input" => c.arguments))
        elseif c isa ReasoningPart && _replays(c, m, p, :anthropic)
            push!(blocks, c.data)
        elseif c isa ToolSearchPart && _replays(c, m, p, :anthropic)
            push!(blocks, c.data)
        end
    end
    return blocks
end

# Hosted search blocks, passed back unchanged: claude-docs/claude-docs-35-tool-search-tool.md#L617-L668
const _ANTHROPIC_SEARCH_BLOCKS = ("server_tool_use", "tool_search_tool_result")

# RequestToolResultBlock #L4926-L4966; must come first in the user turn
# (claude-docs/claude-docs-26-handle-tool-calls.md#L63-L67)
_anthropic_blocks(m::ToolResultMessage, p) = Any[
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
        t in ("thinking", "redacted_thinking") &&
            push!(parts, ReasoningPart(something(get(b, "thinking", nothing), ""), :anthropic, b))
        t in _ANTHROPIC_SEARCH_BLOCKS && push!(parts, ToolSearchPart(:anthropic, b))
    end
    reason = _stop_reason(parts, get(_ANTHROPIC_STOP, something(get(json, "stop_reason", nothing), ""), :other))
    usage = _anthropic_usage(get(json, "usage", nothing))  # #L5172
    return AssistantMessage(parts; model = req.model, stop_reason = reason, usage,
                            id = get(json, "id", nothing))
end

# With caching, input_tokens covers only the uncached part; the total adds cache reads and writes
# (claude-docs/claude-docs-50-prompt-caching.md#L689-L694), as other providers report it.
function _anthropic_usage(u)
    u === nothing && return nothing
    n(k) = something(get(u, k, 0), 0)
    return Usage(n("input_tokens") + n("cache_read_input_tokens") + n("cache_creation_input_tokens"),
                 n("output_tokens"))
end

# Stream events: claude-docs/claude-docs-15-streaming.md#L296-L306 (flow), #L318-L319 (error),
# #L328-L336 (text_delta), #L539-L563 (full example). message_delta usage is cumulative.
# tool_use blocks start with `input: {}` and stream input_json_delta.partial_json (#L933-L960).
# thinking blocks stream thinking_delta then one signature_delta; redacted_thinking arrives whole
# in content_block_start (claude-docs-21-thinking.md#L511, #L776-L791, #L1133-L1138).
# Tool search: server_tool_use streams like tool_use; tool_search_tool_result arrives whole
# (claude-docs-35-tool-search-tool.md#L796-L813, claude-docs-30-server-tools.md#L1088).
_supports_streaming(::Type{Anthropic}) = true
# claude-docs/claude-docs-35-tool-search-tool.md#L38-L58 (Claude 4.5 models and later)
_supports_hosted_tool_search(::Type{Anthropic}) = true

mutable struct _AnthropicStream
    id::Any
    text::Dict{Int,IOBuffer}          # content block index => text (text blocks only)
    calls::Dict{Int,Vector{Any}}      # content block index => [id, name, input JSON buffer]
    thinking::Dict{Int,Dict{String,Any}}  # content block index => thinking / redacted_thinking block
    search::Dict{Int,Vector{Any}}     # content block index => [search block, input JSON buffer or nothing]
    stop_reason::Any
    input_tokens::Int
    output_tokens::Int
    error::Union{Nothing,String}
    reasoned::Bool                    # some reasoning text was reported
end
_stream_state(::Anthropic, req::_Request) = _AnthropicStream(nothing, Dict(), Dict(), Dict(), Dict(), nothing, 0, 0, nothing, false)

function _stream_event!(st::_AnthropicStream, data::AbstractString, on::_StreamHooks)
    ev = JSON.parse(data)
    t = get(ev, "type", nothing)
    if t == "message_start"
        m = ev["message"]
        st.id = get(m, "id", nothing)
        u = something(get(m, "usage", nothing), Dict())
        st.input_tokens = _anthropic_usage(u).input_tokens
        st.output_tokens = something(get(u, "output_tokens", 0), 0)
    elseif t == "content_block_start"
        b = ev["content_block"]
        bt = get(b, "type", nothing)
        bt == "text" && (st.text[ev["index"]] = IOBuffer())
        bt == "tool_use" && (st.calls[ev["index"]] = Any[b["id"], b["name"], IOBuffer()])
        bt in ("thinking", "redacted_thinking") && (st.thinking[ev["index"]] = Dict{String,Any}(b))
        bt == "server_tool_use" && (st.search[ev["index"]] = Any[Dict{String,Any}(b), IOBuffer()])
        bt == "tool_search_tool_result" && (st.search[ev["index"]] = Any[Dict{String,Any}(b), nothing])
    elseif t == "content_block_delta"
        d = ev["delta"]
        if get(d, "type", nothing) == "text_delta"
            write(get!(IOBuffer, st.text, ev["index"]), d["text"])
            on.text(d["text"])
        elseif get(d, "type", nothing) == "input_json_delta" && haskey(st.calls, ev["index"])
            write(st.calls[ev["index"]][3], d["partial_json"])
        elseif get(d, "type", nothing) == "input_json_delta" && haskey(st.search, ev["index"]) &&
               st.search[ev["index"]][2] !== nothing
            write(st.search[ev["index"]][2], d["partial_json"])
        elseif get(d, "type", nothing) == "thinking_delta" && haskey(st.thinking, ev["index"])
            b = st.thinking[ev["index"]]
            prev = get(b, "thinking", "")
            b["thinking"] = string(prev, d["thinking"])
            # Blocks are separated by a blank line; an omitted block streams one empty delta.
            if !isempty(d["thinking"])
                isempty(prev) && st.reasoned && on.reasoning("\n\n")
                on.reasoning(d["thinking"])
                st.reasoned = true
            end
        elseif get(d, "type", nothing) == "signature_delta" && haskey(st.thinking, ev["index"])
            st.thinking[ev["index"]]["signature"] = d["signature"]
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
    function search_block(i)
        b, buf = st.search[i]
        buf === nothing && return b
        streamed = String(take!(buf))
        b["input"] = isempty(streamed) ? something(get(b, "input", nothing), Dict{String,Any}()) : _arguments(streamed)
        return b
    end
    block(i) = haskey(st.thinking, i) ? st.thinking[i] :
        haskey(st.search, i) ? search_block(i) :
        haskey(st.text, i) ? _text_block(String(take!(st.text[i]))) :
        Dict{String,Any}("type" => "tool_use", "id" => st.calls[i][1], "name" => st.calls[i][2],
                         "input" => _arguments(String(take!(st.calls[i][3]))))
    blocks = [block(i) for i in sort!(collect(union(keys(st.text), keys(st.calls), keys(st.thinking), keys(st.search))))]
    json = Dict{String,Any}("id" => st.id, "content" => blocks, "stop_reason" => st.stop_reason,
                            "usage" => Dict("input_tokens" => st.input_tokens,
                                            "output_tokens" => st.output_tokens))
    return _parse_reply(req.model.provider, req, json)
end
