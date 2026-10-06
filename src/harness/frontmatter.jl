# YAML front matter of agent and skill files, and the alias table for tool names written in
# other harnesses' formats (decision 46).

# (front matter, body). No leading `---` block: empty front matter and the whole text.
function _frontmatter(text::AbstractString)
    m = match(r"\A\ufeff?---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n|\z)"s, text)
    m === nothing && return Dict{String,Any}(), String(text)
    data = try
        YAML.load(m.captures[1]; dicttype = JSON.Object{Any,Any})
    catch e
        e isa InterruptException && rethrow()
        flat = _flat_frontmatter(m.captures[1])
        flat === nothing && rethrow()
        flat
    end
    data === nothing && (data = Dict{String,Any}())
    data isa AbstractDict || throw(ArgumentError("the front matter is not a YAML mapping"))
    body = lstrip(text[m.offset+length(m.match):end], ['\n', '\r'])
    return _string_keys(data), String(body)
end

_string_keys(d::AbstractDict) = JSON.Object{String,Any}(string(k) => _string_keys(v) for (k, v) in d)
_string_keys(v::AbstractVector) = Any[_string_keys(x) for x in v]
_string_keys(x) = x

# Front matter that isn't valid YAML but is one `key: value` per line (e.g. a description with
# `: ` in it, which other harnesses accept): values as text; nothing for anything else.
function _flat_frontmatter(text::AbstractString)
    out = JSON.Object{Any,Any}()
    for line in split(text, '\n')
        l = rstrip(line)
        (isempty(l) || startswith(l, '#')) && continue
        m = match(r"^([A-Za-z_][A-Za-z0-9_-]*):(?:\s+(.*))?$", l)
        m === nothing && return nothing
        v = something(m.captures[2], "")
        (startswith(v, '[') || startswith(v, '{')) && return nothing
        out[m.captures[1]] = isempty(v) ? nothing : strip(v, ['"', '\''])
    end
    return out
end

# A list of names from front matter: a YAML list or a comma-separated string. In a YAML flow list,
# `group:edit` parses as a one-entry mapping; it is turned back into the text.
function _name_list(v, what::AbstractString)
    v === nothing && return String[]
    v isa AbstractString && return String[strip(x) for x in split(v, ',') if !isempty(strip(x))]
    v isa AbstractVector || throw(ArgumentError("`$what` must be a list or a comma-separated string"))
    out = String[]
    for x in v
        if x isa AbstractDict && length(x) == 1
            k, y = only(x)
            push!(out, string(k, ":", y))
        elseif x isa Union{AbstractString,Symbol,Number}
            push!(out, strip(string(x)))
        else
            throw(ArgumentError("`$what` entries must be names, got $(repr(x))"))
        end
    end
    return filter!(!isempty, out)
end

_fm_string(fm, key, default = nothing) = (v = get(fm, key, nothing); v === nothing ? default : strip(string(v)))

_fm_bool(fm, key, default::Bool) = (v = get(fm, key, nothing);
    v === nothing ? default : v isa Bool ? v : throw(ArgumentError("`$key` must be true or false, got $(repr(v))")))

# Claude Code / VS Code tool names => JAIL tool or `group:<g>`; `nothing` = no equivalent.
const _TOOL_ALIASES = Dict{String,Union{Nothing,String}}(
    "Read" => "read_file", "read" => "read_file", "read/readFile" => "read_file", "readFile" => "read_file",
    "LS" => "list_dir", "listDirectory" => "list_dir",
    "Glob" => "find_files", "fileSearch" => "find_files", "search/fileSearch" => "find_files",
    "Grep" => "grep_files", "textSearch" => "grep_files", "search/textSearch" => "grep_files",
    "search" => "group:read", "codebase" => "group:read", "search/codebase" => "group:read",
    "Write" => "create_file", "createFile" => "create_file", "edit/createFile" => "create_file",
    "Edit" => "replace_in_file", "MultiEdit" => "replace_in_files",
    "edit" => "group:edit", "editFiles" => "group:edit", "edit/editFiles" => "group:edit",
    "Bash" => "run_shell", "runCommands" => "run_shell", "runInTerminal" => "run_shell",
    "execute/runInTerminal" => "run_shell",
    "execute" => "group:execute",
    "runTests" => "run_tests", "execute/runTests" => "run_tests",
    "WebFetch" => "fetch_url", "fetch" => "fetch_url", "web/fetch" => "fetch_url",
    "web" => "group:web",
    "problems" => "check_julia_syntax", "read/problems" => "check_julia_syntax",
    "changes" => "git_changes", "search/changes" => "git_changes",
    "askQuestions" => "ask_user", "vscode/askQuestions" => "ask_user", "AskUserQuestion" => "ask_user",
    "NotebookEdit" => nothing, "TodoWrite" => nothing, "Task" => nothing, "WebSearch" => nothing,
    "todos" => nothing, "agent" => nothing)

const _WARNED_TOOL_REFS = Set{String}()

function _warn_ref_once(name, msg)
    name in _WARNED_TOOL_REFS && return nothing
    push!(_WARNED_TOOL_REFS, name)
    @warn "JAIL: $msg"
    return nothing
end

# JAIL tool names and `group:<g>` entries for names as written in agent/skill files. A tool name
# wins over an alias, and an alias over a group of the same spelling (`read` is `read_file`).
function _resolve_tool_refs(names)
    out = String[]
    for raw in names
        n = String(raw)
        m = match(r"^([^()]+)\((.*)\)$", n)
        if m !== nothing
            _warn_ref_once(n, "the pattern in tool name `$n` is ignored; `$(m.captures[1])` is used")
            n = String(m.captures[1])
        end
        if haskey(_TOOLS, n) || haskey(_builtins(), n) || startswith(n, "group:")
            push!(out, n)
        elseif haskey(_TOOL_ALIASES, n)
            a = _TOOL_ALIASES[n]
            a === nothing ? _warn_ref_once(n, "tool `$n` has no JAIL equivalent and is ignored") : push!(out, a)
        elseif any(t -> t.group == n, values(_TOOLS))
            push!(out, "group:" * n)
        elseif startswith(n, "vscode/") || startswith(n, "github/") || startswith(n, "mcp")
            _warn_ref_once(n, "tool `$n` has no JAIL equivalent and is ignored")
        else
            _warn_ref_once(n, "no tool named `$n`; it is ignored")
        end
    end
    return unique!(out)
end

# Tool names for resolved references, expanding groups over the registered tools.
_ref_names(refs) = _load_names(refs; strict = false)
