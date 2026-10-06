# Built-in memory tools: read_memory, add_memory, remove_memory ("memory"). Each session keeps a
# Markdown numbered list at <storage_dir>/memory/sessions/<session id>.md. Numbers stay as given:
# removing one leaves a gap, so numbers the model has already seen keep pointing at the same memory.

function _memory_path()
    ctx = tool_context()
    s = ctx === nothing ? active_session() : ctx.session
    return _memory_path(something(s._store.dir, _storage_dir()), s.id)
end

_memory_path(dir, id) = joinpath(dir, "memory", "sessions", string(id, ".md"))

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

"""
    read_memory()

Return this session's memories: a numbered list, one memory per line.
"""
function read_memory()
    path = _memory_path()
    return isfile(path) && !isempty(_read_memories(path)) ? read(path, String) : "(no memories yet)"
end

"""
    add_memory(input)

Save a memory for this session, as the next number of its numbered list. Returns the line added.

# Arguments
- `input`: the memory, one line of text (line breaks become spaces)
"""
function add_memory(input::String)
    text = strip(replace(input, r"\s*[\r\n]+\s*" => " "))
    isempty(text) && throw(ArgumentError("the memory is empty"))
    path = _memory_path()
    ms = _read_memories(path)
    n = isempty(ms) ? 1 : maximum(first, ms) + 1
    push!(ms, (n, String(text)))
    _write_memories(path, ms)
    return "$n. $text"
end

"""
    remove_memory(number)

Remove the memory with this number from this session's list. The other memories keep their
numbers. Returns the line removed.

# Arguments
- `number`: the memory's number, as shown by `read_memory`
"""
function remove_memory(number::Int)
    path = _memory_path()
    ms = _read_memories(path)
    i = findfirst(m -> first(m) == number, ms)
    i === nothing && throw(ArgumentError("there is no memory number $number"))
    (n, text) = popat!(ms, i)
    _write_memories(path, ms)
    return "removed: $n. $text"
end

_builtin!(read_memory; group = "memory", label = "Read memory", security = :low)
_builtin!(add_memory; group = "memory", label = "Add memory", security = :low, preview = "input",
          concurrent = false)
_builtin!(remove_memory; group = "memory", label = "Remove memory", security = :low, preview = "number",
          concurrent = false)
