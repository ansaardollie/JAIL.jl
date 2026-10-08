# Built-in memory tools ("memory"), in two scopes, each a Markdown numbered list: session memory at
# <storage_dir>/memory/sessions/<session id>.md and agent memory at <storage_dir>/memory/agents/<agent>.memory.md.
# Numbers stay as given: removing one leaves a gap, so numbers the model has already seen keep pointing at the same memory.

_session_memory_path(dir, id) = joinpath(dir, "memory", "sessions", string(id, ".md"))

function _agent_memory_path(dir, name::AbstractString)
    (isempty(name) || name in (".", "..") || any(c -> c in ('/', '\\', '\0'), name)) &&
        throw(ArgumentError("the agent name \"$name\" can't be a file name"))
    return joinpath(dir, "memory", "agents", string(name, ".memory.md"))
end

# The file of the scope for the calling session: the tool context's session, else the active one.
function _current_memory_path(scope::Symbol)
    s = _calling_session()
    dir = something(s._store.dir, _storage_dir())
    return scope === :session ? _session_memory_path(dir, s.id) : _agent_memory_path(dir, _agent_name(s))
end

# (number, text) for each `N. text` line of the file.
function _read_memories(path::AbstractString)
    isfile(path) || return Tuple{Int,String}[]
    out = Tuple{Int,String}[]
    for l in eachline(path)
        m = match(r"^(\d+)\.\s+(.*)$", l)
        m === nothing || push!(out, (parse(Int, m[1]), String(m[2])))
    end
    return out
end

_write_memories(path, ms) = _write_atomic(path, join(("$n. $t\n" for (n, t) in ms)))

# The text of a memory file, or a note that it has no memories.
function _memory_text(path::AbstractString)
    return isfile(path) && !isempty(_read_memories(path)) ? read(path, String) : "(no memories yet)"
end

function _add_memory!(path::AbstractString, input::AbstractString)
    text = strip(replace(input, r"\s*[\r\n]+\s*" => " "))
    isempty(text) && throw(ArgumentError("the memory is empty"))
    ms = _read_memories(path)
    n = isempty(ms) ? 1 : maximum(first, ms) + 1
    push!(ms, (n, String(text)))
    _write_memories(path, ms)
    return "$n. $text"
end

function _remove_memory!(path::AbstractString, number::Int)
    ms = _read_memories(path)
    i = findfirst(m -> first(m) == number, ms)
    i === nothing && throw(ArgumentError("there is no memory number $number"))
    (n, text) = popat!(ms, i)
    _write_memories(path, ms)
    return "removed: $n. $text"
end

"""
    read_session_memory()

Return this session's memory: a numbered list, one memory per line. Session memory holds directives for the specific task of this session, such as decisions, constraints or details to keep for the work at hand. Other sessions don't see it; for directives useful in every future session with this agent, use `read_agent_memory`.
"""
function read_session_memory()
    return _memory_text(_current_memory_path(:session))
end

"""
    add_session_memory(input)

Save a directive for the specific task of this session, as the next number of its numbered list. Use session memory only for what must be remembered for this session's task. For directives that are, explicitly or implicitly, useful for all future sessions with this agent, use `add_agent_memory`. Returns the line added.

# Arguments
- `input`: the memory, one line of text (line breaks become spaces)
"""
function add_session_memory(input::String)
    return _add_memory!(_current_memory_path(:session), input)
end

"""
    remove_session_memory(number)

Remove the session memory with this number from this session's list. The other memories keep their numbers. Returns the line removed.

# Arguments
- `number`: the memory's number, as shown by `read_session_memory`
"""
function remove_session_memory(number::Int)
    return _remove_memory!(_current_memory_path(:session), number)
end

"""
    read_agent_memory()

Return this agent's memory: a numbered list, one memory per line, shared by every session that uses this agent. Agent memory holds directives about this agent that are, explicitly or implicitly, useful for all future sessions with it, such as the user's standing preferences or conventions for this kind of work. For what only matters to the current task, use `read_session_memory`.
"""
function read_agent_memory()
    return _memory_text(_current_memory_path(:agent))
end

"""
    add_agent_memory(input)

Save a directive for this agent, as the next number of its numbered list. It is kept for all future sessions with this agent, so add it only when the user states it or it is clearly useful in every future session with this agent. For what only matters to the current task, use `add_session_memory`. Returns the line added.

# Arguments
- `input`: the memory, one line of text (line breaks become spaces)
"""
function add_agent_memory(input::String)
    return _add_memory!(_current_memory_path(:agent), input)
end

"""
    remove_agent_memory(number)

Remove the agent memory with this number from this agent's list. The other memories keep their numbers. Returns the line removed.

# Arguments
- `number`: the memory's number, as shown by `read_agent_memory`
"""
function remove_agent_memory(number::Int)
    return _remove_memory!(_current_memory_path(:agent), number)
end

_builtin!(read_session_memory; group = "memory", label = "Read session memory", security = :low)
_builtin!(add_session_memory; group = "memory", label = "Add session memory", security = :low,
          preview = "input", concurrent = false)
_builtin!(remove_session_memory; group = "memory", label = "Remove session memory", security = :low,
          preview = "number", concurrent = false)
_builtin!(read_agent_memory; group = "memory", label = "Read agent memory", security = :low)
_builtin!(add_agent_memory; group = "memory", label = "Add agent memory", security = :low,
          preview = "input", concurrent = false)
_builtin!(remove_agent_memory; group = "memory", label = "Remove agent memory", security = :low,
          preview = "number", concurrent = false)
