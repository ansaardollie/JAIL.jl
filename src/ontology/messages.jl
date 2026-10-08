"""
    AbstractContentPart

One piece of a message's content: [`TextPart`](@ref), a [`ToolCall`](@ref) the model made, a
[`ToolResult`](@ref) sent back, the model's [`ReasoningPart`](@ref), or a step of a provider's
hosted tool search ([`ToolSearchPart`](@ref)).
"""
abstract type AbstractContentPart end

"""
    TextPart(text)

Plain text content.
"""
struct TextPart <: AbstractContentPart
    text::String
end

"""
    ToolCall(id, name, arguments)

A request from the model, inside an [`AssistantMessage`](@ref), to run the tool `name` with
`arguments` (the JSON object the model produced, keyed by parameter name). `id` pairs it with
its [`ToolResult`](@ref).
"""
struct ToolCall <: AbstractContentPart
    id::String
    name::String
    arguments::Dict{String,Any}
    ToolCall(id::AbstractString, name::AbstractString, arguments::AbstractDict = Dict{String,Any}()) =
        new(String(id), String(name), Dict{String,Any}(string(k) => v for (k, v) in arguments))
end

"""
    ToolResult(call_id, name, content; is_error = false, id = nothing)

The outcome of running the [`ToolCall`](@ref) with id `call_id`: the text the model sees, and
whether it is an error (the tool threw, the arguments were invalid, or the call was declined).

`id` is JAIL's own version 7 UUID for the call/result pair, set by [`agent!`](@ref) when it runs
the call; the pair is saved as `<storage_dir>/tools/<session id>/<id>.json`, and text the call
carried (Julia code, a shell command, a new file's contents) as
`<storage_dir>/generated/<type>/<session id>/<id>/generated.<ext>` (see
[`restore_session!`](@ref)). It is never sent to the provider.
"""
struct ToolResult <: AbstractContentPart
    call_id::String
    name::String
    content::String
    is_error::Bool
    id::Union{Nothing,UUID}
    ToolResult(call_id::AbstractString, name::AbstractString, content::AbstractString;
               is_error::Bool = false, id::Union{Nothing,UUID} = nothing) =
        new(String(call_id), String(name), String(content), is_error, id)
end

"""
    ReasoningPart(text, format::Symbol, data = Dict())

The model's reasoning inside an [`AssistantMessage`](@ref): `text` is the readable summary
(often empty unless `show_reasoning` is on, see [`chat!`](@ref)), and
`data` is the provider's opaque record of it (signatures, encrypted content), in the wire
`format` it came from: `:anthropic`, `:openai_responses`, `:google_interactions`,
`:google_generate_content`, or `:chat_completions` (reasoning text some OpenAI-compatible servers
return; never sent back). Don't read or edit `data`; providers require it back unchanged.

It is not part of `string(msg)`. When the history is sent again in full, it goes back unchanged,
but only to the provider type and wire format that produced it; others never see it.

```jldoctest
julia> r = ReasoningPart("Check the units first.", :anthropic)
ReasoningPart(:anthropic, "Check the units first.")

julia> string(AssistantMessage([r, TextPart("22°C")]))
"22°C"
```
"""
struct ReasoningPart <: AbstractContentPart
    text::String
    format::Symbol
    data::Dict{String,Any}
    ReasoningPart(text::AbstractString, format::Symbol, data::AbstractDict = Dict{String,Any}()) =
        new(String(text), format, Dict{String,Any}(string(k) => v for (k, v) in data))
end

"""
    ToolSearchPart(format::Symbol, data = Dict())

A step of the provider's own (hosted) tool search inside an [`AssistantMessage`](@ref): the
search the model ran or the tools it found, as the provider's opaque record `data` in the wire
`format` it came from (`:anthropic` for `server_tool_use` / `tool_search_tool_result` blocks,
`:openai_responses` for `tool_search_call` / `tool_search_output` items). Don't edit `data`;
providers require it back unchanged.

It is not part of `string(msg)`. When the history is sent again in full, it goes back only to
the provider type and wire format that produced it, and only while that request uses hosted tool
search. See the Tools guide on tool search.
"""
struct ToolSearchPart <: AbstractContentPart
    format::Symbol
    data::Dict{String,Any}
    ToolSearchPart(format::Symbol, data::AbstractDict = Dict{String,Any}()) =
        new(format, Dict{String,Any}(string(k) => v for (k, v) in data))
end

"""
    AbstractMessage

One entry in a conversation's history: a [`UserMessage`](@ref), an [`AssistantMessage`](@ref),
or a [`ToolResultMessage`](@ref). A [`Session`](@ref) stores them as `Vector{AbstractMessage}`.
System instructions are not a message; they live on `Session.system`.

`string(msg)` returns the message's text (tool calls and results are not text).
"""
abstract type AbstractMessage end

_parts(text::AbstractString) = AbstractContentPart[TextPart(text)]
_parts(parts::AbstractVector) = convert(Vector{AbstractContentPart}, parts)

"""
    UserMessage(text)
    UserMessage(parts::Vector{<:AbstractContentPart})

A turn written by the user.
"""
struct UserMessage <: AbstractMessage
    content::Vector{AbstractContentPart}
    UserMessage(content::Union{AbstractString,AbstractVector}) = new(_parts(content))
end

"""
    Usage(input_tokens, output_tokens)

Token counts the provider reported for one reply. `input_tokens` includes tokens read from or
written to a prompt cache.
"""
struct Usage
    input_tokens::Int
    output_tokens::Int
end

const _STOP_REASONS = (:end_turn, :max_tokens, :stop_sequence, :tool_use, :refusal,
                      :content_filter, :other)

"""
    AssistantMessage(text; model = nothing, stop_reason = nothing, usage = nothing, id = nothing)
    AssistantMessage(parts::Vector{<:AbstractContentPart}; ...)

A turn written by the model. Replies from [`chat!`](@ref) carry the `model` that produced them,
a `stop_reason`, the token `usage`, and the provider's `id` for the reply (OpenAI response id,
Google interaction id, Anthropic message id). Hand-written ones (e.g. few-shot examples) may
leave those as `nothing`. A reply that calls tools holds [`ToolCall`](@ref) parts and has
`stop_reason = :tool_use`. A thinking model's reply may also hold [`ReasoningPart`](@ref)s.

`stop_reason` is one of `:end_turn`, `:max_tokens`, `:stop_sequence`, `:tool_use`, `:refusal`,
`:content_filter` or `:other`.
"""
struct AssistantMessage <: AbstractMessage
    content::Vector{AbstractContentPart}
    model::Union{Nothing,AbstractModel}
    stop_reason::Union{Nothing,Symbol}
    usage::Union{Nothing,Usage}
    id::Union{Nothing,String}
    function AssistantMessage(content::Union{AbstractString,AbstractVector};
                              model::Union{Nothing,AbstractModel} = nothing,
                              stop_reason::Union{Nothing,Symbol} = nothing,
                              usage::Union{Nothing,Usage} = nothing,
                              id::Union{Nothing,AbstractString} = nothing)
        stop_reason === nothing || stop_reason in _STOP_REASONS || throw(ArgumentError(
            "stop_reason must be one of :$(join(_STOP_REASONS, ", :")); got :$stop_reason"))
        return new(_parts(content), model, stop_reason, usage, id === nothing ? nothing : String(id))
    end
end

"""
    ToolResultMessage(results::Vector{ToolResult})

The results of one round of tool calls, sent back to the model. [`chat!`](@ref) adds one after
each reply that calls tools.
"""
struct ToolResultMessage <: AbstractMessage
    content::Vector{ToolResult}
end

_tool_calls(m::AbstractMessage) = ToolCall[p for p in m.content if p isa ToolCall]

function Base.print(io::IO, m::AbstractMessage)
    for p in m.content
        p isa TextPart && print(io, p.text)
    end
end

_role(::UserMessage) = "user"
_role(::AssistantMessage) = "assistant"
_role(::ToolResultMessage) = "tool"

_short(s::AbstractString, n) = (s = replace(s, r"\s+" => " "); length(s) <= n ? s : first(s, n - 1) * "…")

function _preview(m::AbstractMessage, n = 40)
    return _short(string(m), n)
end

_call_signature(c::ToolCall; n = 30) = string(c.name, "(",
    join((string(k, " = ", _short(repr(c.arguments[k]), n)) for k in sort!(collect(keys(c.arguments)))), ", "), ")")

Base.show(io::IO, c::ToolCall) = print(io, "ToolCall(", _call_signature(c), ")")
Base.show(io::IO, r::ToolResult) =
    print(io, "ToolResult(", r.name, r.is_error ? " error " : " ", repr(_short(r.content, 40)), ")")
Base.show(io::IO, r::ReasoningPart) = print(io, "ReasoningPart(:", r.format, ", ", repr(_short(r.text, 40)), ")")
Base.show(io::IO, t::ToolSearchPart) = print(io, "ToolSearchPart(:", t.format, ", ", repr(_search_kind(t)), ")")

# Wire type of the block or item (`server_tool_use`, `tool_search_output`, ...).
_search_kind(t::ToolSearchPart) = string(get(t.data, "type", ""))

# Reasoning and tool search steps go back only to the provider type and wire format that produced them.
_replays(r::Union{ReasoningPart,ToolSearchPart}, m::AssistantMessage, p::AbstractProvider, format::Symbol) =
    r.format === format && m.model !== nothing && typeof(m.model.provider) === typeof(p)

Base.show(io::IO, m::UserMessage) = print(io, "UserMessage(", repr(_preview(m)), ")")

function Base.show(io::IO, m::AssistantMessage)
    print(io, "AssistantMessage(", repr(_preview(m)))
    calls = _tool_calls(m)
    isempty(calls) || print(io, ", ", join((c.name for c in calls), ", "))
    m.model === nothing || print(io, ", ", m.model)
    m.stop_reason === nothing || print(io, ", :", m.stop_reason)
    print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", m::AssistantMessage)
    meta = String[]
    m.model === nothing || push!(meta, string(m.model))
    m.stop_reason === nothing || push!(meta, string(m.stop_reason))
    m.usage === nothing || push!(meta, "$(m.usage.input_tokens) in / $(m.usage.output_tokens) out")
    print(io, "AssistantMessage", isempty(meta) ? "" : " (" * join(meta, ", ") * ")")
    text = string(m)
    if !isempty(strip(text))
        println(io)
        show(io, MIME"text/plain"(), Markdown.parse(text))
    end
    foreach(c -> print(io, "\n→ ", _call_signature(c)), _tool_calls(m))
end

Base.show(io::IO, m::ToolResultMessage) =
    print(io, "ToolResultMessage(", join((r.name for r in m.content), ", "), ")")

function Base.show(io::IO, ::MIME"text/plain", m::ToolResultMessage)
    print(io, "ToolResultMessage")
    foreach(r -> print(io, "\n← ", r.name, r.is_error ? " (error): " : ": ", _short(r.content, 70)), m.content)
end

Base.show(io::IO, u::Usage) = print(io, "Usage(", u.input_tokens, " in, ", u.output_tokens, " out)")
