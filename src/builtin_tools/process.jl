# Built-in process tools: run_shell, run_tests, pkg_add ("execute"), git_changes ("read"),
# pkg_status ("inspect"). Child processes run in the workspace root without secret ENV variables.

using Pkg: Pkg

function _process_report(out; timeout = nothing)
    text = isempty(out.output) ? "(no output)\n" : out.output
    endswith(text, '\n') || (text *= "\n")
    out.timed_out && return string(text, "[killed after ", timeout, " s]")
    out.signal != 0 && return string(text, "[killed by signal ", out.signal, "]")
    return string(text, "[exit code ", out.exitcode, "]")
end

"""
    run_shell(command, timeout_seconds = nothing)

Run a shell command (`sh -c` on macOS/Linux, `cmd /c` on Windows) in the workspace folder and
return its combined output and exit code. It gets no input, so interactive commands fail
rather than wait. Environment variables holding keys and credentials are removed.

# Arguments
- `command`: the command line
- `timeout_seconds`: kill the command after this many seconds; omit to wait until it ends
"""
function run_shell(command::String, timeout_seconds::Union{Nothing,Int} = nothing)
    isempty(strip(command)) && throw(ArgumentError("the command is empty"))
    cmd = Sys.iswindows() ? `cmd /c $command` : `sh -c $command`
    return _process_report(_run_cmd(cmd; timeout = timeout_seconds); timeout = timeout_seconds)
end

"""
    run_tests()

Run the test suite of the Julia project in the workspace folder (`Pkg.test()` in a new Julia
process) and return its output.
"""
function run_tests()
    isfile(joinpath(_workspace_root(), "Project.toml")) ||
        throw(ArgumentError("the workspace folder has no Project.toml"))
    cmd = `$(Base.julia_cmd()) --project=$(_workspace_root()) -e "using Pkg; Pkg.test()"`
    return _process_report(_run_cmd(cmd))
end

function _git(args::Cmd)
    git = Sys.which("git")
    git === nothing && throw(ArgumentError("`git` was not found on the PATH"))
    out = _run_cmd(`$git $args`; timeout = 60)
    out.exitcode == 0 || throw(ArgumentError(strip(out.output)))
    return out.output
end

"""
    git_changes(diff = true)

Show the git status of the workspace folder (changed, added, deleted and untracked files) and,
unless `diff` is false, the changes themselves: staged first, then unstaged.

# Arguments
- `diff`: include the line-by-line changes, not only the list of files
"""
function git_changes(diff::Bool = true)
    status = _git(`status --porcelain=v1`)
    isempty(status) && return "No changes."
    out = "Status:\n" * status
    if diff
        # --no-ext-diff/--no-textconv: repository settings must not run other programs.
        staged = _git(`--no-pager diff --cached --no-ext-diff --no-textconv`)
        unstaged = _git(`--no-pager diff --no-ext-diff --no-textconv`)
        isempty(staged) || (out *= "\nStaged changes:\n" * staged)
        isempty(unstaged) || (out *= "\nUnstaged changes:\n" * unstaged)
    end
    return out
end

"""
    pkg_status()

List the packages of the active Julia project (`Pkg.status()`), with their versions.
"""
function pkg_status()
    io = IOBuffer()
    Pkg.status(; io)
    return String(take!(io))
end

"""
    pkg_add(packages)

Add registered packages to the active Julia project (`Pkg.add`), so they can be loaded with
`using`. Returns Pkg's output.

# Arguments
- `packages`: package names, e.g. `["DataFrames", "CSV"]`
"""
function pkg_add(packages::Vector{String})
    isempty(packages) && throw(ArgumentError("no packages given"))
    io = IOBuffer()
    Pkg.add(packages; io)
    return String(take!(io))
end

_builtin!(run_shell; group = "execute", label = "Shell command", security = :high, preview = "command")
_builtin!(run_tests; group = "execute", label = "Run tests", security = :high)
_builtin!(pkg_add; group = "execute", label = "Add packages", security = :high, preview = "packages")
_builtin!(git_changes; group = "read", label = "Git changes", security = :low)
_builtin!(pkg_status; group = "inspect", label = "Package status", security = :low)
