"""
    AbstractProvider

An LLM API vendor such as [`OpenAI`](@ref), [`Anthropic`](@ref) or [`Google`](@ref).
Concrete providers carry connection config (base URL, API-key ENV var name). Defaults and other
reference data are functions over `Type{<:AbstractProvider}`.
"""
abstract type AbstractProvider end

"""
    AbstractOpenAIProvider <: AbstractProvider

Parent of [`OpenAI`](@ref) and [`OpenAICompatible`](@ref), which share wire-format code.
"""
abstract type AbstractOpenAIProvider <: AbstractProvider end

# Reference data, one method per concrete provider type.
function provider_name end
function default_base_url end
function default_api_key_env end

provider_name(p::AbstractProvider) = provider_name(typeof(p))

# explicit kwarg, then Preferences, then the type default
function _resolve_first_party(::Type{P}, base_url, api_key_env) where {P<:AbstractProvider}
    t = _provider_prefs(provider_name(P))
    return (something(base_url, get(t, "base_url", nothing), default_base_url(P)),
            something(api_key_env, get(t, "api_key_env", nothing), default_api_key_env(P)))
end

# Provider interface: each provider implements these.
function _auth_headers end
function _list_models end

function _normalize_url(url::AbstractString)
    u = rstrip(strip(url), '/')
    occursin(r"^https?://[^/\s]+", u) ||
        throw(ArgumentError("base_url must start with http:// or https://, got \"$url\""))
    return String(u)
end

function _check_env_name(name::AbstractString)
    occursin(r"^[A-Za-z_][A-Za-z0-9_]*$", name) || throw(ArgumentError(
        "api_key_env is the *name* of an environment variable (e.g. \"ANTHROPIC_API_KEY\"), " *
        "not the key itself; got an invalid name"))
    return String(name)
end

function _api_key(p::AbstractProvider)
    env = p.api_key_env
    env === nothing && return nothing
    key = get(ENV, env, "")
    isempty(key) && error(
        "No API key for $(provider_name(p)): ENV[\"$env\"] is not set. Set it, or point JAIL at " *
        "another variable with `configure_provider!(p; api_key_env = \"MY_VAR\")`.")
    return key
end
