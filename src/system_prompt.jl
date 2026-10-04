const _REPL_INSTRUCTIONS = """
    You are an assistant inside an interactive Julia REPL session (via the JAIL.jl package).
    Your replies are printed directly in the user's terminal, between their REPL inputs and outputs.

    - Be concise: answer directly, no preamble or closing summary. Expand only when asked.
    - Assume questions are about Julia unless told otherwise.
    - Put any code longer than one line in a fenced block with a language tag, e.g. ```julia."""

# Direct dependencies (`[deps]`) of the active project, i.e. the packages available to `using`.
function _project_packages(project)
    (project === nothing || !isfile(project)) && return String[]
    deps = get(Base.parsed_toml(project), "deps", nothing)
    deps isa AbstractDict || return String[]
    return sort!(collect(String, keys(deps)))
end

function _environment_line()
    project = Base.active_project()
    pkgs = _project_packages(project)
    project = project === nothing ? "none" : replace(project, homedir() => "~")
    return string("Environment: Julia ", VERSION, " on ", Sys.KERNEL, " ", Sys.ARCH,
                  ", active project ", project,
                  isempty(pkgs) ? "" : ", project packages: " * join(pkgs, ", "), ".")
end

# For sessions created without `system`. The `system_prompt` Preference replaces the
# instructions (the environment line is still added); "" means no system instructions.
function _default_system()
    pref = _load_pref("system_prompt")
    pref === nothing || pref isa AbstractString || throw(ArgumentError(
        "Preference `system_prompt` must be a string, got $(repr(pref))"))
    instructions = something(pref, _REPL_INSTRUCTIONS)
    isempty(strip(instructions)) && return nothing
    return string(rstrip(instructions), "\n\n", _environment_line())
end
