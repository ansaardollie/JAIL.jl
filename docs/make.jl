using Documenter

# Examples write Preferences into docs/LocalPreferences.toml. Start every build from a clean
# slate and block inheritance so the workspace root's JAIL preferences can't leak into output.
const DOCS_PREFS = joinpath(@__DIR__, "LocalPreferences.toml")
write(DOCS_PREFS, """
    [JAIL]
    __clear__ = ["default_model", "providers", "repl_modes", "max_tokens", "store_requests", "system_prompt", "stream", "max_tool_rounds", "confirm_tools"]
    """)

using JAIL

# In a workspace, Preferences are also read from the workspace root, and `__clear__` stops
# masking a key once an example writes it. Put a scratch project first on LOAD_PATH: JAIL is
# only in its [extras], so packages still load from docs/, but Preferences are read from and
# written there, and the workspace root is no longer merged in.
const PREFS_DIR = mktempdir()
write(joinpath(PREFS_DIR, "Project.toml"), "[extras]\nJAIL = \"$(Base.PkgId(JAIL).uuid)\"\n")
pushfirst!(LOAD_PATH, PREFS_DIR)

DocMeta.setdocmeta!(JAIL, :DocTestSetup, :(using JAIL); recursive = true)

makedocs(
    modules = [JAIL],
    sitename = "JAIL.jl",
    authors = "Ansaar Dollie <me@ansaardollie.com>",
    format = Documenter.HTML(; edit_link = "main", assets = String[]),
    pages = [
        "Home" => "index.md",
        "Guide" => [
            "guide/concepts.md",
            "guide/providers.md",
            "guide/models.md",
            "guide/sessions.md",
            "guide/chat.md",
            "guide/tools.md",
            "guide/repl.md",
        ],
        "Reference" => "reference.md",
    ],
)

rm(DOCS_PREFS; force = true)
