# Model ids seen in this process, for REPL tab completion; never fetched on demand.
const _MODEL_ID_CACHE = Dict{String,Vector{String}}()

function _fetch_models(p::AbstractProvider)
    models = list_models(p)
    _MODEL_ID_CACHE[provider_name(p)] = [m.id for m in models]
    return models
end

function _key_note(p::AbstractProvider)
    env = p.api_key_env
    (env === nothing || !isempty(get(ENV, env, ""))) && return ""
    return "ENV[\"$env\"] not set"
end

# No ENV-var API key to check; GoogleEnterprise authenticates with an OAuth2 access token.
_key_note(::GoogleEnterprise) = ""

_endpoint(p::AbstractProvider) = p.base_url
_endpoint(p::GoogleEnterprise) = _gcp_location_url(p.location)

function _provider_labels(ps)
    width = maximum(p -> length(provider_name(p)), ps)
    return map(ps) do p
        note = _key_note(p)
        string(rpad(provider_name(p), width), "  ", _endpoint(p), isempty(note) ? "" : "  ($note)")
    end
end

function _print_error(e)
    printstyled(stderr, "ERROR: "; color = :red, bold = true)
    println(stderr, e isa ArgumentError ? e.msg : sprint(showerror, e))
end

function _pick(term, title::AbstractString, labels::Vector{String}; cursor::Int = 1)
    menu = RadioMenu(labels; pagesize = min(length(labels), 15))
    i = request(term, title, menu; cursor)
    return i == -1 ? nothing : i
end

"""
    select_model!()
    select_model!(provider::AbstractProvider)
    select_model!(session::Session)
    select_model!(session::Session, provider::AbstractProvider)

Choose a model from terminal menus: first a provider (skipped when one is given), then one of
its models, fetched live with [`list_models`](@ref).

Without a session, the [`active_session`](@ref) changes. The saved default model is not
touched; use [`set_default_model!`](@ref) for that. Returns the `Model`, or `nothing` if the
menu is cancelled or the models can't be listed (the error is printed).
"""
select_model!() = select_model!(active_session())
select_model!(p::AbstractProvider) = select_model!(active_session(), p)
select_model!(s::Session) = _select_for!(s, _choose_model(_menu_terminal(), _model_string(s)))
select_model!(s::Session, p::AbstractProvider) =
    _select_for!(s, _choose_model(p, _menu_terminal(), _model_string(s)))

function _select_for!(s::Session, m)
    m === nothing && return nothing
    set_model!(s, m)
    println("Session \"", s.name, "\" now uses ", m)
    return m
end

# Julia ≥ 1.11 replaced the `TerminalMenus.terminal` global with `default_terminal()`
_menu_terminal() = isdefined(TerminalMenus, :default_terminal) ?
    TerminalMenus.default_terminal() : TerminalMenus.terminal

function _choose_model(term, current)
    ps = providers()
    i = _pick(term, "Select a provider:", _provider_labels(ps))
    return i === nothing ? nothing : _choose_model(ps[i], term, current)
end

function _choose_model(p::AbstractProvider, term, current)
    models = try
        _fetch_models(p)
    catch e
        e isa InterruptException && rethrow()
        _print_error(e)
        return nothing
    end
    if isempty(models)
        println("$(provider_name(p)) returned no models.")
        return nothing
    end
    labels = [(string(m) == current ? "* " : "  ") * m.id for m in models]
    cursor = something(findfirst(m -> string(m) == current, models), 1)
    i = _pick(term, "Select a $(provider_name(p)) model:", labels; cursor)
    return i === nothing ? nothing : models[i]
end
