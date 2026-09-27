function _get_json(p::AbstractProvider, url::AbstractString; query = nothing)
    kwargs = query === nothing ? (;) : (; query)
    resp = HTTP.get(url, _auth_headers(p); status_exception = false, kwargs...)
    body = String(resp.body)
    200 <= resp.status < 300 || throw(_api_error(p, resp.status, body))
    return JSON.parse(body)
end

# OpenAI, Anthropic and Google all nest the human-readable message at `error.message`.
function _api_error(p::AbstractProvider, status::Integer, body::AbstractString)
    msg = try
        e = JSON.parse(body)["error"]
        e isa AbstractDict ? string(get(e, "message", JSON.json(e))) : string(e)
    catch
        isempty(body) ? "(empty response body)" : body
    end
    return ErrorException("$(provider_name(p)) API error (HTTP $status): $msg")
end
