const _REPL_INSTRUCTIONS = """
    You are an assistant inside an interactive Julia REPL session (via the JAIL.jl package).
    Your replies are printed directly in the user's terminal, between their REPL inputs and outputs.

    - Be concise: answer directly, no preamble or closing summary. Expand only when asked.
    - Assume questions are about Julia unless told otherwise.
    - Put any code longer than one line in a fenced block with a language tag, e.g. ```julia."""

# Top-level packages bound in Main (via `using`/`import`), not their dependencies.
function _main_packages()
    names_ = String[]
    for n in names(Main; imported = true, usings = true)
        isdefined(Main, n) || continue
        m = getfield(Main, n)
        m isa Module && parentmodule(m) === m && m ∉ (Base, Core, Main) &&
            Base.PkgId(m).uuid !== nothing && push!(names_, string(nameof(m)))
    end
    return sort!(unique!(names_))
end

function _environment_line()
    project = Base.active_project()
    project = project === nothing ? "none" : replace(project, homedir() => "~")
    pkgs = _main_packages()
    return string("Environment: Julia ", VERSION, " on ", Sys.KERNEL, " ", Sys.ARCH,
                  ", active project ", project,
                  isempty(pkgs) ? "" : ", loaded packages: " * join(pkgs, ", "), ".")
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
