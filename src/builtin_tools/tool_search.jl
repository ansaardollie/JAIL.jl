# JAIL's own tool search: tool_search and tool_load, for providers without a hosted one (Google,
# GoogleEnterprise, OpenAICompatible, and OpenAI/Anthropic with `tool_search = "client"`). They are
# never registered; the chat loop adds both to a request when the session has tools that are
# registered but not loaded (`_request_tools` in src/chat.jl).

_calling_session() = (ctx = tool_context(); ctx === nothing ? active_session() : ctx.session)

# (tools the session may use, whether one is loaded): the agent turn's when one is running.
function _search_pool(s::Session)
    turn = _AGENT_TURN[]
    turn === nothing && return tools(s), t -> t.name in s.loaded_tools
    return _turn_pool(s, turn), t -> _turn_loaded(s, turn, t)
end

# Case-insensitive regex match, or a plain substring match when `k` isn't a valid regex.
function _keyword_predicate(k::AbstractString)
    r = try
        Regex(k, "i")
    catch
        nothing
    end
    r === nothing || return text -> occursin(r, text)
    lk = lowercase(k)
    return text -> occursin(lk, lowercase(text))
end

"""
    tool_search(keywords = [])

Search the tools you can load but don't have yet. Returns each matching tool's name and
description. A tool matches when any keyword (a case-insensitive regular expression, e.g.
`"file"` or `"read|write"`) occurs in its name or description. With no keywords, every such tool
is listed. To call a tool found here, load it first with `tool_load`.

# Arguments
- `keywords`: words or regular expressions to look for; omit to list every tool
"""
function tool_search(keywords::Vector{String} = String[])
    s = _calling_session()
    pool, isloaded = _search_pool(s)
    found = ToolSpec[t for t in pool if !isloaded(t)]
    ks = [String(strip(k)) for k in keywords if !isempty(strip(k))]
    if !isempty(ks)
        preds = map(_keyword_predicate, ks)
        filter!(t -> any(p -> p(t.name) || p(t.description), preds), found)
    end
    if isempty(found)
        isempty(ks) && return "There are no tools to load."
        return "No tools match $(join(repr.(ks), ", ")). Try other keywords, or none to list every tool."
    end
    io = IOBuffer()
    print(io, length(found), length(found) == 1 ? " tool" : " tools",
          " found. Load the ones you need with `tool_load` before calling them.")
    for t in found
        print(io, "\n\n## ", t.name)
        isempty(t.description) || print(io, "\n", t.description)
    end
    return String(take!(io))
end

"""
    tool_load(names)

Load tools found with `tool_search`, by name, so you can call them from your next step on.

# Arguments
- `names`: the names of the tools to load
"""
function tool_load(names::Vector{String})
    s = _calling_session()
    names = unique!([String(strip(n)) for n in names if !isempty(strip(n))])
    isempty(names) && throw(ArgumentError("give the names of the tools to load"))
    available = Set(t.name for t in first(_search_pool(s)))
    ok = filter(in(available), names)
    bad = setdiff(names, ok)
    isempty(ok) && throw(ArgumentError(
        "no tool named $(join(repr.(bad), ", ")); find the tools you can load with `tool_search`"))
    # Agent-turn tools (skill_<name>) aren't registered, so they are added by name.
    append!(s.loaded_tools, setdiff(ok, s.loaded_tools))
    _sync_meta!(s)
    msg = string("Loaded ", join(ok, ", "), ". You can now call ", length(ok) == 1 ? "it." : "them.")
    isempty(bad) || (msg *= string(" Not found (search with `tool_search`): ", join(bad, ", "), "."))
    return msg
end

const _CLIENT_SEARCH = ToolSpec[]

# Built on first use, like the other built-ins (docstrings are read at run time).
function _client_search_specs()
    isempty(_CLIENT_SEARCH) && append!(_CLIENT_SEARCH, [
        _tool_spec(tool_search; group = "tool_search", label = "Tool search", security = :low, preview = :keywords),
        _tool_spec(tool_load; group = "tool_search", label = "Load tools", security = :low, preview = :names,
                   concurrent = false)])
    return _CLIENT_SEARCH
end
