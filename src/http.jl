function _get_json(p::AbstractProvider, url::AbstractString; query = nothing)
    kwargs = query === nothing ? (;) : (; query)
    resp = HTTP.get(url, _auth_headers(p); status_exception = false, kwargs...)
    body = String(resp.body)
    200 <= resp.status < 300 || throw(_api_error(p, resp.status, body))
    return JSON.parse(body)
end

# Set ENV["JULIA_DEBUG"] = "JAIL" to log request and response bodies (headers, and so keys, never).
function _post_json(p::AbstractProvider, url::AbstractString, body)
    payload = JSON.json(body)
    @debug "JAIL request" provider = provider_name(p) url body = payload
    resp = HTTP.post(url, [_auth_headers(p); "Content-Type" => "application/json"], payload;
                     status_exception = false)
    text = String(resp.body)
    @debug "JAIL response" provider = provider_name(p) status = resp.status body = text
    200 <= resp.status < 300 || throw(_api_error(p, resp.status, text))
    return JSON.parse(text)
end

struct _APIError <: Exception
    status::Int
    msg::String
end
Base.showerror(io::IO, e::_APIError) = print(io, e.msg)

# OpenAI, Anthropic and Google all nest the human-readable message at `error.message`.
function _api_error(p::AbstractProvider, status::Integer, body::AbstractString)
    msg = try
        e = JSON.parse(body)["error"]
        e isa AbstractDict ? string(get(e, "message", JSON.json(e))) : string(e)
    catch
        isempty(body) ? "(empty response body)" : body
    end
    return _APIError(status, "$(provider_name(p)) API error (HTTP $status): $msg")
end

# An error object inside a successful (HTTP 2xx) body, e.g. a failed response or interaction.
_error_message(::Nothing) = "(no error details)"
_error_message(e::AbstractString) = e
_error_message(e) = string(get(e, "message", JSON.json(e)))
