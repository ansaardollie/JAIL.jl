# Built-in file tools: the "read" group (read_file, list_dir, find_files, grep_files) and the
# "edit" group (create_file, create_directory, replace_in_file, replace_in_files, edit_file,
# remove_file). Paths are
# relative to the workspace root (the current directory); see `_resolve` for the security rules.

_is_binary(path::AbstractString) = open(io -> any(iszero, read(io, 8192)), path)

function _text_file(path::AbstractString)
    p = _resolve(path).path
    isdir(p) && throw(ArgumentError("`$path` is a folder; use list_dir"))
    isfile(p) || throw(ArgumentError("no file `$path`"))
    _is_binary(p) && throw(ArgumentError("`$path` is not a text file"))
    return p
end

"""
    read_file(path, start_line = 1, end_line = nothing)

Read a text file. Returns a header line `path (lines a–b of n)` followed by the lines, exactly
as they are in the file. Read the whole file unless it is long; then read the part you need.

# Arguments
- `path`: the file, relative to the workspace folder (e.g. `src/MyPkg.jl`) or absolute
- `start_line`: first line to read, counting from 1
- `end_line`: last line to read (inclusive); omit to read to the end
"""
function read_file(path::String, start_line::Int = 1, end_line::Union{Nothing,Int} = nothing)
    p = _text_file(path)
    lines = readlines(p; keep = true)
    n = length(lines)
    n == 0 && return "$path (empty file)"
    start_line >= 1 || throw(ArgumentError("start_line must be at least 1"))
    start_line <= n || throw(ArgumentError("start_line $start_line is past the end; `$path` has $n lines"))
    stop = end_line === nothing ? n : min(end_line, n)
    stop >= start_line || throw(ArgumentError("end_line must not be before start_line"))
    return string(path, " (lines ", start_line, "–", stop, " of ", n, ")\n", join(lines[start_line:stop]))
end

"""
    list_dir(path = ".")

List a folder: one entry per line, sorted, folders ending in `/` and symbolic links in `@`.

# Arguments
- `path`: the folder, relative to the workspace folder or absolute; `.` is the workspace folder
"""
function list_dir(path::String = ".")
    p = _resolve(path).path
    isdir(p) || throw(ArgumentError(isfile(p) ? "`$path` is a file; use read_file" : "no folder `$path`"))
    entries = map(readdir(p)) do e
        full = joinpath(p, e)
        islink(full) ? e * "@" : isdir(full) ? e * "/" : e
    end
    return isempty(entries) ? "(empty folder)" : join(entries, '\n')
end

function _limited(lines::Vector{String}, max_results::Int, what::AbstractString)
    max_results >= 1 || throw(ArgumentError("max_results must be at least 1"))
    length(lines) <= max_results && return join(lines, '\n')
    return string(join(lines[1:max_results], '\n'), "\n(", length(lines) - max_results,
                  " more $what not shown; raise max_results to see them)")
end

"""
    find_files(pattern, max_results = 200)

Find files in the workspace folder by glob pattern; returns their paths relative to the
workspace folder, one per line. Files ignored by git are skipped.

A pattern without `/` matches file names in any folder (`*.jl`, `Project.toml`); a pattern with
`/` matches the whole relative path (`src/**/*.jl`, `test/*.jl`). `*` and `?` match within one
folder name, `**` across folders, `[abc]` one of the characters, `{jl,md}` either alternative.

# Arguments
- `pattern`: the glob pattern
- `max_results`: how many paths to return at most
"""
function find_files(pattern::String, max_results::Int = 200)
    match = _glob_matcher(pattern)
    hits = filter(match, _workspace_files())
    isempty(hits) && return "No files match `$pattern`."
    return _limited(hits, max_results, "files")
end

"""
    grep_files(query, is_regex = false, include = nothing, max_results = 100)

Search the text files of the workspace folder for lines containing `query`, ignoring case.
Returns one `path:line: text` per match. Files ignored by git are skipped.

# Arguments
- `query`: the text to find, or a regular expression (PCRE syntax) when `is_regex` is true
- `is_regex`: whether `query` is a regular expression
- `include`: only search files matching this glob pattern (as in find_files, e.g. `*.jl` or `src/**`)
- `max_results`: how many matching lines to return at most
"""
function grep_files(query::String, is_regex::Bool = false, include::Union{Nothing,String} = nothing,
                    max_results::Int = 100)
    isempty(query) && throw(ArgumentError("the query is empty"))
    matches = is_regex ? (rx = Regex(query, "i"); l -> occursin(rx, l)) :
                         (q = lowercase(query); l -> occursin(q, lowercase(l)))
    files = _workspace_files()
    include === nothing || filter!(_glob_matcher(include), files)
    root, hits = _workspace_root(), String[]
    for rel in files
        abs = joinpath(root, rel)
        _is_binary(abs) && continue
        for (i, line) in enumerate(eachline(abs))
            matches(line) && push!(hits, string(rel, ':', i, ": ", line))
            length(hits) > max_results && break
        end
        length(hits) > max_results && break
    end
    isempty(hits) && return "No matches for `$query`."
    length(hits) > max_results || return join(hits, '\n')
    return string(join(hits[1:max_results], '\n'), "\n(more matches not shown; raise max_results or narrow the search)")
end

# --- edit ------------------------------------------------------------------------------------

"""
    create_file(path, content)

Create a new text file with the given content (folders on the way are created). Fails if the
file already exists; use replace_in_file to change an existing file.

# Arguments
- `path`: the new file, relative to the workspace folder or absolute
- `content`: the whole text of the file
"""
function create_file(path::String, content::String)
    p = _resolve(path).path
    ispath(p) && throw(ArgumentError("`$path` already exists; use replace_in_file to change it"))
    _write_atomic(p, content)
    return "Created `$path` ($(count('\n', content) + !endswith(content, '\n')) lines)."
end

"""
    create_directory(path)

Create a folder, and any missing folders above it.

# Arguments
- `path`: the folder, relative to the workspace folder or absolute
"""
function create_directory(path::String)
    p = _resolve(path).path
    isdir(p) && return "`$path` already exists."
    ispath(p) && throw(ArgumentError("`$path` exists and is not a folder"))
    mkpath(p)
    return "Created `$path`."
end

function _replace_once(text::String, old::String, new::String, where::AbstractString)
    isempty(old) && throw(ArgumentError("$where: `old` is empty"))
    n = count(old, text)
    n == 1 || throw(ArgumentError(n == 0 ?
        "$where: `old` was not found; it must match the file exactly, including whitespace" :
        "$where: `old` occurs $n times; include more surrounding lines so it matches once"))
    return replace(text, old => new; count = 1)
end

"""
    replace_in_file(path, old, new)

Change a text file by replacing one exact piece of text. `old` must occur exactly once in the
file, character for character (whitespace and indentation included); include a few unchanged
lines around the change so it is unique.

# Arguments
- `path`: the file, relative to the workspace folder or absolute
- `old`: the exact text to replace
- `new`: the text to put in its place
"""
function replace_in_file(path::String, old::String, new::String)
    p = _text_file(path)
    _write_atomic(p, _replace_once(read(p, String), old, new, "`$path`"))
    return "Replaced 1 occurrence in `$path`."
end

# One replacement of `replace_in_files`; the model sees it as an object with these fields.
struct FileEdit
    path::String
    old::String
    new::String
end

"""
    replace_in_files(edits)

Make several replacements, in one or more files, as one change: each `old` must occur exactly
once (as in replace_in_file) in its file at the moment it is applied, in the order given. If any
edit fails, no file is changed.

# Arguments
- `edits`: the replacements, each with `path`, `old` and `new`
"""
function replace_in_files(edits::Vector{FileEdit})
    isempty(edits) && throw(ArgumentError("no edits given"))
    texts = Dict{String,String}()
    order = String[]
    for (i, e) in enumerate(edits)
        p = _text_file(e.path)
        haskey(texts, p) || (texts[p] = read(p, String); push!(order, p))
        texts[p] = _replace_once(texts[p], e.old, e.new, "edit $i (`$(e.path)`)")
    end
    foreach(p -> _write_atomic(p, texts[p]), order)
    return "Applied $(length(edits)) edit$(length(edits) == 1 ? "" : "s") to $(length(order)) file$(length(order) == 1 ? "" : "s")."
end

"""
    remove_file(path)

Delete a file. Folders are not deleted.

# Arguments
- `path`: the file, relative to the workspace folder or absolute
"""
function remove_file(path::String)
    p = _resolve(path).path
    islink(p) || ispath(p) || throw(ArgumentError("no file `$path`"))
    isdir(p) && !islink(p) && throw(ArgumentError("`$path` is a folder; remove_file only deletes files"))
    rm(p)
    return "Deleted `$path`."
end

_marked(prefix, text) = join((prefix * l for l in split(text, '\n')), '\n')
_diff_preview(path, old, new) = string(path, '\n', _marked("- ", old), '\n', _marked("+ ", new))

# One change of `edit_file`; the model sees it as an object with these fields.
struct LineEdit
    action::String
    line::Int
    end_line::Union{Nothing,Int}
    pattern::Union{Nothing,String}
    text::Union{Nothing,String}
end

# The edits checked against a file of `n` lines: which original lines are removed, the
# (regex, text) replacements per original line, and the text added after each line (index k + 1
# for after line k, 1 for before the first).
function _plan_line_edits(lines::Vector{String}, edits::Vector{LineEdit})
    isempty(edits) && throw(ArgumentError("no edits given"))
    n = length(lines)
    removed = falses(n)
    replaces = [Tuple{Regex,String}[] for _ in 1:n]
    adds = [String[] for _ in 0:n]
    for (i, e) in enumerate(edits)
        what = "edit $i ($(e.action) at line $(e.line))"
        action = lowercase(strip(e.action))
        if action == "add"
            0 <= e.line <= n || throw(ArgumentError("$what: line must be from 0 to $n"))
            e.text === nothing && throw(ArgumentError("$what: `text` is required"))
            push!(adds[e.line+1], e.text)
        elseif action in ("remove", "replace")
            stop = something(e.end_line, e.line)
            1 <= e.line <= stop <= n || throw(ArgumentError(
                "$what: lines must be from 1 to $n, with end_line not before line"))
            if action == "remove"
                removed[e.line:stop] .= true
                continue
            end
            (e.pattern === nothing || e.text === nothing) &&
                throw(ArgumentError("$what: `pattern` and `text` are required"))
            rx = try
                Regex(e.pattern)
            catch err
                throw(ArgumentError("$what: invalid regular expression: $(sprint(showerror, err))"))
            end
            any(k -> occursin(rx, chomp(lines[k])), e.line:stop) || throw(ArgumentError(
                "$what: the pattern matches nothing in line$(stop > e.line ? "s $(e.line)–$stop" : " $(e.line)")"))
            foreach(k -> push!(replaces[k], (rx, e.text)), e.line:stop)
        else
            throw(ArgumentError("$what: action must be \"add\", \"remove\" or \"replace\""))
        end
    end
    k = findfirst(k -> removed[k] && !isempty(replaces[k]), 1:n)
    k === nothing || throw(ArgumentError("line $k is both removed and replaced"))
    return removed, replaces, adds
end

# Rebuilds the file line by line over the original numbering, so edits never shift each other.
function _apply_line_edits(lines::Vector{String}, (removed, replaces, adds))
    nl = !isempty(lines) && endswith(lines[1], "\r\n") ? "\r\n" : "\n"
    io = IOBuffer()
    emit_adds(k) = foreach(t -> print(io, t, endswith(t, '\n') ? "" : nl), adds[k+1])
    emit_adds(0)
    for (k, line) in enumerate(lines)
        if !removed[k]
            body = chomp(line)
            ending = line[ncodeunits(body)+1:end]
            for (rx, t) in replaces[k]
                body = replace(body, rx => t)
            end
            print(io, body, isempty(ending) && !isempty(adds[k+1]) ? nl : ending)
        end
        emit_adds(k)
    end
    return String(take!(io))
end

"""
    edit_file(path, edits)

Change a text file by line number. Lines count from 1, and every `line` refers to the file as it
is now, however many lines other edits in the same call add or remove, so read the file first
(read_file's header gives the line range shown) and give all changes in one call. Each edit has
an `action`:

- `remove`: delete lines `line` to `end_line` (just `line` without `end_line`).
- `add`: insert `text` (one or more lines) after line `line`; `line = 0` inserts at the top.
  Several adds after the same line keep their order.
- `replace`: in lines `line` to `end_line`, replace every match of the regular expression
  `pattern` (PCRE syntax) with `text`, taken literally. The pattern must match at least once.

If any edit is invalid, the file is not changed.

# Arguments
- `path`: the file, relative to the workspace folder or absolute
- `edits`: the changes, each with `action` ("remove", "add" or "replace"), `line`, and as needed `end_line`, `pattern`, `text`
"""
function edit_file(path::String, edits::Vector{LineEdit})
    p = _text_file(path)
    lines = readlines(p; keep = true)
    plan = _plan_line_edits(lines, edits)
    new = _apply_line_edits(lines, plan)
    _write_atomic(p, new)
    removed, replaces, adds = plan
    changed = count(k -> !removed[k] && !isempty(replaces[k]), eachindex(lines))
    added = sum(t -> count('\n', chomp(t)) + 1, Iterators.flatten(adds); init = 0)
    return "Edited `$path`: $(count(removed)) line(s) removed, $added added, $changed changed; " *
           "it now has $(length(readlines(IOBuffer(new)))) lines."
end

function _line_edits_preview(path, edits)
    lines = try
        readlines(_resolve(path).path)
    catch
        String[]
    end
    at(k) = 1 <= k <= length(lines) ? lines[k] : ""
    out = String[path]
    for e in edits
        stop = something(e.end_line, e.line)
        action = lowercase(strip(e.action))
        if action == "remove"
            push!(out, "@ $(e.line)$(stop > e.line ? "–$stop" : "")", ("- " * at(k) for k in e.line:stop)...)
        elseif action == "add"
            push!(out, "@ after $(e.line)", _marked("+ ", something(e.text, "")))
        else
            push!(out, "@ $(e.line)$(stop > e.line ? "–$stop" : ""): /$(something(e.pattern, ""))/ → $(repr(something(e.text, "")))")
        end
    end
    return join(out, '\n')
end

_max_level(levels) = isempty(levels) ? :medium : _SECURITY_LEVELS[maximum(l -> findfirst(==(l), _SECURITY_LEVELS), levels)]

_builtin!(read_file; group = "read", label = "Read file", security = _read_level, preview = "path")
_builtin!(list_dir; group = "read", label = "List folder", security = _read_level, preview = "path")
_builtin!(find_files; group = "read", label = "Find files", security = :low, preview = "pattern")
_builtin!(grep_files; group = "read", label = "Search files", security = :low, preview = ["query", "include"])
# Edits run alone: two calls may change the same file.
_builtin!(create_file; group = "edit", label = "Create file", concurrent = false,
          security = (path, _...) -> _write_level(path),
          preview = (path, content) -> string(path, '\n', content))
_builtin!(create_directory; group = "edit", label = "Create folder",
          security = path -> _write_level(path, :low), preview = "path")
_builtin!(replace_in_file; group = "edit", label = "Edit file", concurrent = false,
          security = (path, _...) -> _write_level(path), preview = _diff_preview)
_builtin!(replace_in_files; group = "edit", label = "Edit files", concurrent = false,
          security = edits -> _max_level([_write_level(e.path) for e in edits]),
          preview = edits -> join((_diff_preview(e.path, e.old, e.new) for e in edits), "\n\n"))
_builtin!(edit_file; group = "edit", label = "Edit lines", concurrent = false,
          security = (path, _...) -> _write_level(path), preview = _line_edits_preview)
_builtin!(remove_file; group = "edit", label = "Delete file", concurrent = false,
          security = path -> _write_level(path, :high), preview = "path")

foreach(f -> _PATH_GUARDS[f] = _read_guard, (read_file, list_dir))
foreach(f -> _PATH_GUARDS[f] = _write_guard, (create_file, create_directory, replace_in_file, edit_file, remove_file))
_PATH_GUARDS[replace_in_files] = edits -> any(e -> _write_guard(e.path), edits)
