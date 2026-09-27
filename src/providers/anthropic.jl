"""
    Anthropic(; base_url, api_key_env)

The Anthropic API. Unset fields come from Preferences, then from the defaults
`https://api.anthropic.com` and `ANTHROPIC_API_KEY`.

Only [`list_models`](@ref) is implemented so far; requests will use the Messages API.
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
