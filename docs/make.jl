using Documenter

# Examples write Preferences into docs/LocalPreferences.toml. Start every build from a clean
# slate and block inheritance so the workspace root's JAIL preferences can't leak into output.
const DOCS_PREFS = joinpath(@__DIR__, "LocalPreferences.toml")
write(DOCS_PREFS, """
    [JAIL]
    __clear__ = ["default_model", "providers", "repl_modes", "max_tokens", "store_requests", "system_prompt"]
    """)

using JAIL

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
            "guide/repl.md",
        ],
        "Reference" => "reference.md",
    ],
)

rm(DOCS_PREFS; force = true)
