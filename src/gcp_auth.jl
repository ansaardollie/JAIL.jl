# GCP OAuth2 access-token retrieval for GoogleEnterprise (Vertex AI): Application Default
# Credentials, a service-account JSON key, or the GCE/GKE metadata server. Kept provider-agnostic;
# GoogleEnterprise (providers/google.jl) owns the cached-token field and expiry check.

using Dates: Dates
using Base64: Base64
using MbedTLS: MbedTLS
using Random: Random

const _GCP_OAUTH_URL = "https://oauth2.googleapis.com/token"
const _GCP_METADATA_TOKEN_URL = "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
# Real tokens last ~1h; refresh a little early so a long request never starts with a stale one.
const _GCP_TOKEN_LIFETIME = Dates.Minute(55)

mutable struct _GCPAccessKey
    token::String
    expires::Dates.DateTime
end

_is_expired(k::_GCPAccessKey) = Dates.now() >= k.expires

function _gcp_token_from_adc(credential_json_path::AbstractString)
    isfile(credential_json_path) || error(
        "Application Default Credentials not found at \"$credential_json_path\". Try running " *
        "`gcloud auth application-default login`.")
    creds = JSON.parsefile(credential_json_path)
    body = JSON.json(Dict(
        "client_id" => creds["client_id"],
        "client_secret" => creds["client_secret"],
        "refresh_token" => creds["refresh_token"],
        "grant_type" => "refresh_token"))
    resp = HTTP.post(_GCP_OAUTH_URL, ["Content-Type" => "application/json"], body;
                     status_exception = false)
    200 <= resp.status < 300 ||
        error("Failed to fetch access token (HTTP $(resp.status)): $(String(resp.body))")
    return JSON.parse(String(resp.body))["access_token"]
end

function _base64url_encode(data::Union{String,Vector{UInt8}})
    encoded = Base64.base64encode(data)
    encoded = replace(encoded, '+' => '-', '/' => '_')
    return rstrip(encoded, '=')
end

function _gcp_token_from_service_account(credential_json_path::AbstractString;
        scopes::Vector{String} = ["https://www.googleapis.com/auth/cloud-platform"])
    isfile(credential_json_path) ||
        error("Service account credentials not found at \"$credential_json_path\".")
    sa = JSON.parsefile(credential_json_path)
    client_email = sa["client_email"]
    private_key = sa["private_key"]
    token_uri = get(sa, "token_uri", _GCP_OAUTH_URL)

    header_b64 = _base64url_encode(JSON.json(Dict("alg" => "RS256", "typ" => "JWT")))
    now_unix = floor(Int, time())
    claims_b64 = _base64url_encode(JSON.json(Dict(
        "iss" => client_email, "scope" => join(scopes, " "), "aud" => token_uri,
        "exp" => now_unix + 3600, "iat" => now_unix)))
    signature_input = string(header_b64, ".", claims_b64)

    pk = MbedTLS.PKContext()
    MbedTLS.parse_key!(pk, private_key)
    digest = MbedTLS.digest(MbedTLS.MD_SHA256, signature_input)
    sig = MbedTLS.sign(pk, MbedTLS.MD_SHA256, digest, Random.default_rng())
    jwt = string(signature_input, ".", _base64url_encode(sig))

    payload = "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=" * jwt
    resp = HTTP.post(token_uri, ["Content-Type" => "application/x-www-form-urlencoded"], payload;
                     status_exception = false)
    200 <= resp.status < 300 ||
        error("Failed to fetch access token (HTTP $(resp.status)): $(String(resp.body))")
    return JSON.parse(String(resp.body))["access_token"]
end

function _gcp_token_from_metadata_server()
    resp = HTTP.get(_GCP_METADATA_TOKEN_URL, ["Metadata-Flavor" => "Google"];
                    status_exception = false)
    200 <= resp.status < 300 ||
        error("Failed to fetch access token (HTTP $(resp.status)): $(String(resp.body))")
    return JSON.parse(String(resp.body))["access_token"]
end

function _gcp_default_adc_path()
    dir = Sys.iswindows() ? ENV["APPDATA"] : joinpath(homedir(), ".config")
    return joinpath(dir, "gcloud", "application_default_credentials.json")
end

# Priority: an explicit override path, then GOOGLE_APPLICATION_CREDENTIALS (a service-account
# key), then the well-known ADC file left by `gcloud auth application-default login`, then the
# GCE/GKE metadata server.
function _fetch_gcp_access_token(service_account_path::Union{Nothing,AbstractString})
    service_account_path === nothing || return _gcp_token_from_service_account(service_account_path)

    env_path = get(ENV, "GOOGLE_APPLICATION_CREDENTIALS", "")
    if !isempty(env_path)
        isfile(env_path) || error(
            "GOOGLE_APPLICATION_CREDENTIALS is set to \"$env_path\", which does not exist.")
        return _gcp_token_from_service_account(env_path)
    end

    adc_path = _gcp_default_adc_path()
    isfile(adc_path) && return _gcp_token_from_adc(adc_path)

    return _gcp_token_from_metadata_server()
end
