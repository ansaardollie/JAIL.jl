function _get_json(p::AbstractProvider, url::AbstractString; query = nothing)
    kwargs = query === nothing ? (;) : (; query)
    resp = HTTP.get(url, _auth_headers(p); status_exception = false, kwargs...)
    body = String(resp.body)
    200 <= resp.status < 300 || throw(_api_error(p, resp.status, body))
    return JSON.parse(body)
end

# Set ENV["JULIA_DEBUG"] = "JAIL" to log request and response bodies (headers, and so keys, never)
# and, inside a session's turn, save each exchange (see _debug_exchange).
function _post_json(p::AbstractProvider, url::AbstractString, body)
    payload = JSON.json(body)
    headers = [_auth_headers(p); "Content-Type" => "application/json"]
    @debug "JAIL request" provider = provider_name(p) url body = payload
    dir = _debug_exchange(url, headers, body)
    resp = HTTP.post(url, headers, payload; status_exception = false)
    text = String(resp.body)
    @debug "JAIL response" provider = provider_name(p) status = resp.status body = text
    _debug_response(dir, resp, _maybe_json(text))
    200 <= resp.status < 300 || throw(_api_error(p, resp.status, text))
    return JSON.parse(text)
end

# Server-sent events: `on_data(data::String)` per event. Error statuses arrive as a normal body.
function _post_sse(on_data, p::AbstractProvider, url::AbstractString, body)
    payload = JSON.json(body)
    headers = [_auth_headers(p); "Content-Type" => "application/json"; "Accept" => "text/event-stream"]
    @debug "JAIL request (stream)" provider = provider_name(p) url body = payload
    dir = _debug_exchange(url, headers, body)
    events = Any[]
    function on_event(ev)
        @debug "JAIL event" ev.event ev.data
        dir === nothing || push!(events, Dict{String,Any}("event" => ev.event, "data" => _maybe_json(ev.data)))
        on_data(ev.data)
    end
    resp = HTTP.post(url, headers, payload; status_exception = false, sse_callback = on_event)
    if !(200 <= resp.status < 300)
        text = String(resp.body)
        @debug "JAIL response" provider = provider_name(p) status = resp.status body = text
        _debug_response(dir, resp, _maybe_json(text))
        throw(_api_error(p, resp.status, text))
    end
    _debug_response(dir, resp, events)
    return nothing
end

# --- Saving exchanges for debugging ------------------------------------------------------------

# The session whose turn is sending requests; set by `_chat!` and `count_tokens`.
const _DEBUG_SESSION = ScopedValue{Any}(nothing)

# Same switch as @debug's JULIA_DEBUG (a comma-separated list; `all` for every module, `!JAIL` off).
function _debug_enabled()
    entries = strip.(split(get(ENV, "JULIA_DEBUG", ""), ','))
    return any(in(("JAIL", "all")), entries) && !("!JAIL" in entries)
end

# Headers that carry credentials (OpenAI and GoogleEnterprise bearer, Anthropic, Google keys).
const _SECRET_HEADERS = ("authorization", "x-api-key", "x-goog-api-key")

function _debug_headers(headers)
    out = JSON.Object{String,Any}()
    for (k, v) in headers
        lowercase(k) in _SECRET_HEADERS && continue
        out[k] = haskey(out, k) ? string(out[k], ", ", v) : v
    end
    return out
end

_maybe_json(text::AbstractString) = try
    JSON.parse(text)
catch
    text
end

function _debug_write(dir, name, d)
    try
        mkpath(dir)
        write(joinpath(dir, name), JSON.json(d; pretty = true))
    catch e
        e isa InterruptException && rethrow()
        @warn "JAIL: could not save the debug $name" exception = e
    end
    return nothing
end

# With debugging on and a session sending, saves the request as
# <storage_dir>/debug/<session id>/<turn id>/request.json (turn id: a UUID v7 per request) and
# returns that folder for the response; otherwise nothing.
function _debug_exchange(url, headers, body)
    _debug_enabled() || return nothing
    s = _DEBUG_SESSION[]
    s === nothing && return nothing
    dir = joinpath(something(s._store.dir, _storage_dir()), "debug", string(s.id), string(uuid7()))
    _debug_write(dir, "request.json", (url = url, headers = _debug_headers(headers), body = body))
    return dir
end

_debug_response(::Nothing, resp, body) = nothing
_debug_response(dir, resp, body) = _debug_write(dir, "response.json",
    (status = resp.status, headers = _debug_headers(resp.headers), body = body))

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
