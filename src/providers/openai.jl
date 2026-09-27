"""
    OpenAI(; base_url, api_key_env)

The OpenAI API (Responses API only). Unset fields come from Preferences, then from the defaults
`https://api.openai.com/v1` and `OPENAI_API_KEY`.
"""
struct OpenAI <: AbstractOpenAIProvider
    base_url::String
    api_key_env::String
    OpenAI(base_url::AbstractString, api_key_env::AbstractString) =
        new(_normalize_url(base_url), _check_env_name(api_key_env))
end
OpenAI(; base_url = nothing, api_key_env = nothing) =
    OpenAI(_resolve_first_party(OpenAI, base_url, api_key_env)...)

# openapi/api_spec.yaml#L14-L15
provider_name(::Type{OpenAI}) = "openai"
default_base_url(::Type{OpenAI}) = "https://api.openai.com/v1"
default_api_key_env(::Type{OpenAI}) = "OPENAI_API_KEY"

# Shared by OpenAI and OpenAICompatible. openapi/api_spec.yaml#L110188-L110191 (bearer)
function _auth_headers(p::AbstractOpenAIProvider)
    key = _api_key(p)
    return key === nothing ? Pair{String,String}[] : ["Authorization" => "Bearer $key"]
end

# GET /models, no pagination. openapi/api_spec.yaml#L10097-L10115, #L52219-L52233
function _list_models(p::AbstractOpenAIProvider, fetch)
    return [Model(p, String(m["id"])) for m in fetch(p.base_url * "/models")["data"]]
end
