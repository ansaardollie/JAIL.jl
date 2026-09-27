"""
    AbstractModel

A model offered by a provider.
"""
abstract type AbstractModel end

"""
    Model(provider::AbstractProvider, id::AbstractString)
    Model("provider/model-id")

A provider-specific model. The string form splits on the first `/`, so
`Model("openrouter/openai/gpt-5")` is model `"openai/gpt-5"` on the `openrouter` provider.
The provider named in a string is resolved through the current Preferences.
"""
struct Model{P<:AbstractProvider} <: AbstractModel
    provider::P
    id::String
    function Model(provider::P, id::AbstractString) where {P<:AbstractProvider}
        isempty(strip(id)) && throw(ArgumentError("model id must not be empty"))
        return new{P}(provider, String(id))
    end
end

function Model(s::AbstractString)
    i = findfirst('/', s)
    i === nothing && throw(ArgumentError(
        "expected \"provider/model\" (e.g. \"anthropic/claude-sonnet-4-5\"), got \"$s\""))
    return Model(_provider(s[begin:prevind(s, i)]), s[nextind(s, i):end])
end

Base.print(io::IO, m::Model) = print(io, provider_name(m.provider), '/', m.id)
Base.show(io::IO, m::Model) = print(io, "Model(", repr(string(m)), ")")
