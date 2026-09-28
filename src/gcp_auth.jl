module GoogleCloudPlatformAuthentication

using Dates
using JSON
using HTTP

const GOOGLE_CLOUD_PLATFORM_OAUTH_URI = "https://oauth2.googleapis.com/token"
const GOOGLE_CLOUD_PLATFORM_METADATA_SERVER_URI = "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"

mutable struct GoogleCloudPlatformAccessKey
  token::String
  expires::DateTime
end


function get_token_from_application_default_credentials(credential_json_path::String)
  isfile(credential_json_path) || error("Application Default Credentials not found at `$credential_json_path`. Try running `gcloud auth application-default login`")
  creds = JSON.parsefile(credential_json_path)

  body = JSON.json((
    client_id = creds.client_id,
    client_secret = creds.client_secret,
    refresh_token = creds.refresh_token,
    grant_type = "refresh_token"
  ))

  response = HTTP.post(
    GOOGLE_CLOUD_PLATFORM_OAUTH_URI,
    ["Content-Type" => "application/json"],
    body; 
    status_exception=false
  )

  if response.status == 200
    auth_response = JSON.parse(response.body)
    return auth_response.access_token
  else
    error("Failed to fetch access token (HTTP $(response.status)): \n$(String(response.body))")
  end
end

function base64url_encode(data::Union{String, Vector{UInt8}})
    encoded = base64encode(data)
    encoded = replace(encoded, "+" => "-")
    encoded = replace(encoded, "/" => "_")
    return rstrip(encoded, '=') # Strip base64 padding
end

function get_token_from_service_account_credentials(
  credential_json_path::String; 
  scopes::Vector{String}=["https://www.googleapis.com/auth/cloud-platform", "https://www.googleapis.com/auth/cloud-platform"]
)
    isfile(credential_json_path) || error("Service Account Credentials not found at `$credential_json_path`.")
    sa_data = JSON.parsefile(credential_json_path)
    
    client_email = sa_data["client_email"]
    private_key  = sa_data["private_key"]
    token_uri    = get(sa_data, "token_uri", GOOGLE_CLOUD_PLATFORM_OAUTH_URI)

    header = Dict(
        "alg" => "RS256",
        "typ" => "JWT"
    )
    header_b64 = base64url_encode(JSON.json(header))

    now_unix = floor(Int, time()) 
    claims = Dict(
        "iss" => client_email,
        "scope" => join(scopes, " "),
        "aud" => token_uri,
        "exp" => now_unix + 3600, 
        "iat" => now_unix         
    )
    claims_b64 = base64url_encode(JSON.json(claims))

    signature_input = header_b64 * "." * claims_b64

    pk = MbedTLS.PKContext()
    MbedTLS.parse_key!(pk, private_key) 
    
    digest = MbedTLS.digest(MbedTLS.MD_SHA256, signature_input)
    
    rng = Random.default_rng()
    sig = MbedTLS.sign(pk, MbedTLS.MD_SHA256, digest, rng)
    
    sig_b64 = base64url_encode(sig)

    jwt = signature_input * "." * sig_b64

    payload = "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=" * jwt
    headers = ["Content-Type" => "application/x-www-form-urlencoded"]
    
    response = HTTP.post(token_uri, headers, payload; status_exception=false)

    if response.status == 200
        auth_response = JSON.parse(response.body)
        return auth_response.access_token
    else
        error("Failed to fetch access token (HTTP $(response.status)): \n$(String(response.body))")
    end
end

function get_token_from_metadata_server()
  response = HTTP.get(GOOGLE_CLOUD_PLATFORM_METADATA_SERVER_URI, ["Metadata-Flavor" => "Google"], status_exception=false)
  if response.status == 200
    auth_response = JSON.parse(response.body)
    return auth_response.access_token
  else
    error("Failed to fetch access token (HTTP $(response.status)): \n$(String(response.body))")
  end
end

function get_gcp_access_token()
  if haskey(ENV, "GOOGLE_APPLICATION_CREDENTIALS")
    path = ENV["GOOGLE_APPLICATION_CREDENTIALS"]
    if isfile(path)
      return get_token_from_service_account_credentials(path)
    end
  end

  adc_path = joinpath(Sys.iswindows() ? ENV["APPDATA"] : joinpath(homedir(), ".config"), "gcloud", "application_default_credentials.json")
  if isfile(adc_path)
    return get_token_from_application_default_credentials(adc_path)
  end

  return get_token_from_metadata_server()
end


end
