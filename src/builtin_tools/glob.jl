# Glob patterns for `find_files` / `grep_files`, and the list of files they search.

# `*` and `?` stay within one folder, `**` crosses folders, `[abc]` / `[!abc]` match one
# character, `{a,b}` either alternative. Anchored at both ends.
function _glob_regex(pattern::AbstractString)
    io = IOBuffer()
    print(io, '^')
    _glob_body!(io, pattern)
    print(io, '$')
    return Regex(String(take!(io)))
end

function _glob_body!(io::IO, pattern::AbstractString)
    cs = collect(pattern)
    i, n = 1, length(cs)
    while i <= n
        c = cs[i]
        if c == '*'
            if i < n && cs[i+1] == '*'
                if i + 2 <= n && cs[i+2] == '/'
                    print(io, "(?:.*/)?")
                    i += 3
                else
                    print(io, ".*")
                    i += 2
                end
                continue
            end
            print(io, "[^/]*")
        elseif c == '?'
            print(io, "[^/]")
        elseif c == '['
            j = findnext(==(']'), cs, i + 2)
            if j === nothing
                print(io, "\\[")
            else
                body = String(cs[i+1:j-1])
                body = startswith(body, '!') ? "^" * body[2:end] : body
                print(io, '[', replace(body, "\\" => "\\\\"), ']')
                i = j
            end
        elseif c == '{'
            j = findnext(==('}'), cs, i + 1)
            if j === nothing
                print(io, "\\{")
            else
                alts = split(String(cs[i+1:j-1]), ',')
                print(io, "(?:")
                for (k, a) in enumerate(alts)
                    k > 1 && print(io, '|')
                    _glob_body!(io, a)
                end
                print(io, ')')
                i = j
            end
        else
            c in raw"\.^$+()|" && print(io, '\\')
            print(io, c)
        end
        i += 1
    end
end

# Patterns without `/` match a file name in any folder (`*.jl`); others match the whole path
# relative to the root (`src/**/*.jl`).
function _glob_matcher(pattern::AbstractString)
    p = strip(pattern)
    p = startswith(p, "./") ? p[3:end] : p
    isempty(p) && throw(ArgumentError("the pattern is empty"))
    rx = _glob_regex(p)
    return occursin('/', p) ? (rel -> occursin(rx, rel)) : (rel -> occursin(rx, basename(rel)))
end

# Root-relative paths ('/'-separated) of the files the search tools look at: `git ls-files`
# (honouring .gitignore) inside a git work tree, else every file below the root. Symlinks, `.git`
# and JAIL's storage folder are skipped.
function _workspace_files(root::AbstractString = _workspace_root())
    storage = _storage_dir()
    skip(rel) = (abs = joinpath(root, rel); islink(abs) || !isfile(abs) || _under(abs, storage))
    files = _git_files(root)
    if files === nothing
        files = String[]
        for (dir, dirs, fs) in walkdir(root; follow_symlinks = false)
            filter!(d -> d != ".git" && !islink(joinpath(dir, d)) && !_under(joinpath(dir, d), storage), dirs)
            for f in fs
                push!(files, relpath(joinpath(dir, f), root))
            end
        end
    end
    files = [replace(f, '\\' => '/') for f in files if !skip(f)]
    return sort!(unique!(files))
end

function _git_files(root::AbstractString)
    git = Sys.which("git")
    git === nothing && return nothing
    out = _run_cmd(`$git ls-files --cached --others --exclude-standard -z`; dir = root, timeout = 60)
    out.exitcode == 0 && !out.timed_out || return nothing
    return String[f for f in split(out.output, '\0') if !isempty(f)]
end
