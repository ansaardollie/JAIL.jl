"""
    AbstractContentPart

One piece of a message's content. Only [`TextPart`](@ref) exists so far; images, reasoning and
tool calls will be further subtypes.
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
    AbstractMessage

One entry in a conversation's history: a [`UserMessage`](@ref) or an
[`AssistantMessage`](@ref). A [`Session`](@ref) stores them as `Vector{AbstractMessage}`.
System instructions are not a message; they live on `Session.system`.

`string(msg)` returns the message's text.
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

Token counts the provider reported for one reply.
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
leave those as `nothing`.

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

function Base.print(io::IO, m::AbstractMessage)
    for p in m.content
        p isa TextPart && print(io, p.text)
    end
end

_role(::UserMessage) = "user"
_role(::AssistantMessage) = "assistant"

function _preview(m::AbstractMessage, n = 40)
    s = replace(string(m), r"\s+" => " ")
    return length(s) <= n ? s : first(s, n - 1) * "…"
end

Base.show(io::IO, m::UserMessage) = print(io, "UserMessage(", repr(_preview(m)), ")")

function Base.show(io::IO, m::AssistantMessage)
    print(io, "AssistantMessage(", repr(_preview(m)))
    m.model === nothing || print(io, ", ", m.model)
    m.stop_reason === nothing || print(io, ", :", m.stop_reason)
    print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", m::AssistantMessage)
    meta = String[]
    m.model === nothing || push!(meta, string(m.model))
    m.stop_reason === nothing || push!(meta, string(m.stop_reason))
    m.usage === nothing || push!(meta, "$(m.usage.input_tokens) in / $(m.usage.output_tokens) out")
    println(io, "AssistantMessage", isempty(meta) ? "" : " (" * join(meta, ", ") * ")")
    print(io, string(m))
end

Base.show(io::IO, u::Usage) = print(io, "Usage(", u.input_tokens, " in, ", u.output_tokens, " out)")
