const _FIRST_PARTY = (OpenAI, Anthropic, Google)
const _FirstParty = Union{OpenAI,Anthropic,Google}

function _provider(name::AbstractString)
    for P in _FIRST_PARTY
        provider_name(P) == name && return P()
    end
    t = get(_provider_prefs(), name, nothing)
    t !== nothing && get(t, "type", nothing) == "openai_compatible" && return OpenAICompatible(name)
    known = join((provider_name(p) for p in providers()), ", ")
    throw(ArgumentError("unknown provider \"$name\" (known: $known)"))
end

# Only non-default fields are stored, so future default changes still apply.
function _to_prefs(p::P) where {P<:_FirstParty}
    t = Dict{String,Any}()
    p.base_url == default_base_url(P) || (t["base_url"] = p.base_url)
    p.api_key_env == default_api_key_env(P) || (t["api_key_env"] = p.api_key_env)
    return t
end

function _to_prefs(p::OpenAICompatible)
    t = Dict{String,Any}("type" => "openai_compatible", "base_url" => p.base_url)
    p.api_key_env === nothing || (t["api_key_env"] = p.api_key_env)
    p.api === :responses || (t["api"] = String(p.api))
    return t
end

_settings(::_FirstParty) = (:base_url, :api_key_env)
_settings(::OpenAICompatible) = (:base_url, :api_key_env, :api)

# `nothing` means "back to the default"
_with(p::P; base_url = p.base_url, api_key_env = p.api_key_env) where {P<:_FirstParty} =
    P(something(base_url, default_base_url(P)), something(api_key_env, default_api_key_env(P)))

function _with(p::OpenAICompatible; base_url = p.base_url, api_key_env = p.api_key_env, api = p.api)
    base_url === nothing && throw(ArgumentError("an OpenAI-compatible provider needs a base_url"))
    return OpenAICompatible(p.name, base_url; api_key_env, api = something(api, :responses))
end

"""
    configure_provider!(p::AbstractProvider; base_url, api_key_env)
    configure_provider!(p::OpenAICompatible; base_url, api_key_env, api)

Persist connection settings for `p` in Preferences and return the reloaded provider. Keywords
override `p`'s fields; `nothing` removes the saved value, so a built-in provider falls back to
its default and an [`OpenAICompatible`](@ref) endpoint to no key (`api_key_env`) or
`:responses` (`api`). An `OpenAICompatible` endpoint must be registered first with
[`register_provider!`](@ref), and its `base_url` can't be `nothing`.

`api_key_env` is the *name* of the ENV var holding the key; the key itself is never stored.

```julia
configure_provider!(Anthropic(); api_key_env = "MY_ANTHROPIC_KEY")
configure_provider!(Anthropic(); api_key_env = nothing)   # back to ANTHROPIC_API_KEY
```
"""
function configure_provider!(p::AbstractProvider; kwargs...)
    if p isa OpenAICompatible && !haskey(_provider_prefs(), p.name)
        throw(ArgumentError("\"$(p.name)\" is not registered; use `register_provider!` first"))
    end
    bad = setdiff(keys(kwargs), _settings(p))
    isempty(bad) || throw(ArgumentError(
        "cannot configure $(join(bad, ", ")) on $(provider_name(p)); settings are: " *
        join(_settings(p), ", ")))
    q = _with(p; kwargs...)
    _save_provider_prefs!(provider_name(q), _to_prefs(q))
    return _provider(provider_name(q))
end

"""
    register_provider!(p::OpenAICompatible)

Save an OpenAI-compatible endpoint in Preferences under `p.name`, replacing any endpoint already
saved under that name. Afterwards models can be written as `"\$(p.name)/<model-id>"`.
"""
function register_provider!(p::OpenAICompatible)
    _save_provider_prefs!(p.name, _to_prefs(p))
    return p
end

"""
    providers() -> Vector{AbstractProvider}

The built-in providers followed by every registered [`OpenAICompatible`](@ref) endpoint, each
with its current configuration.
"""
function providers()
    ps = AbstractProvider[P() for P in _FIRST_PARTY]
    for (name, t) in sort!(collect(_provider_prefs()); by = first)
        get(t, "type", nothing) == "openai_compatible" && push!(ps, OpenAICompatible(name))
    end
    return ps
end

"""
    set_default_model!(model::Union{AbstractString,Model}) -> Model

Persist the default model in Preferences, e.g. `set_default_model!("anthropic/claude-sonnet-4-5")`.
New sessions start with it, and so does the `"default"` session the next time JAIL loads;
existing sessions are not changed (use [`set_model!`](@ref)).

Only the provider name and model id are stored; provider settings come from
[`configure_provider!`](@ref). The model id is not checked against the provider.
"""
set_default_model!(s::AbstractString) = set_default_model!(Model(s))
function set_default_model!(m::Model)
    name = provider_name(m.provider)
    m.provider == _provider(name) || @warn(
        "The default model only stores \"$m\"; this provider instance's custom settings are not " *
        "saved. Use `configure_provider!` to persist them.")
    _save_pref!("default_model", string(m))
    return m
end

"""
    default_model() -> Model

The model saved with [`set_default_model!`](@ref), resolved against current Preferences.
Throws if no default model is saved.
"""
function default_model()
    s = _load_pref("default_model")
    s === nothing && error(
        "No default model is set. Choose one with e.g. " *
        "`set_default_model!(\"anthropic/claude-sonnet-4-5\")`; `list_models(Anthropic())` shows options.")
    return Model(s)
end

# Natural order: digit runs compare numerically, so "claude-opus-4-9" < "claude-opus-4-10".
_natural_chunks(s::AbstractString) =
    [(isdigit(first(m.match)), lowercase(m.match)) for m in eachmatch(r"\d+|\D+", s)]

function _natural_less(a::AbstractString, b::AbstractString)
    ca, cb = _natural_chunks(a), _natural_chunks(b)
    for ((xnum, x), (ynum, y)) in zip(ca, cb)
        x == y && continue
        xnum && ynum || return x < y
        # compare digit strings without parsing, so long runs can't overflow
        xs, ys = lstrip(x, '0'), lstrip(y, '0')
        xs == ys && return length(x) < length(y)
        return (length(xs), xs) < (length(ys), ys)
    end
    return length(ca) < length(cb)
end

"""
    list_models(p::AbstractProvider) -> Vector{Model}

Ask the provider's API which models are available, sorted alphabetically by id (ignoring case)
with version numbers in numeric order (`gemini-3.9-flash` before `gemini-3.10-flash`).
Needs network access and, for providers that require one, the API key in the configured ENV var.
Google results are limited to models whose `supportedGenerationMethods` include
`generateContent`.
"""
list_models(p::AbstractProvider) =
    sort!(_list_models(p, (url; query = nothing) -> _get_json(p, url; query));
          by = m -> m.id, lt = _natural_less)
