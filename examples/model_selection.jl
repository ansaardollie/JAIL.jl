# Interactive model selection
#
# What: choose a model from terminal menus (`select_model!`) or from the model REPL mode (press
# `|` at an empty `julia>` prompt). Both list models live from the provider. Without a session
# argument, selection changes the active session; the saved default model (what new sessions
# start with) only changes via `set_default_model!` or the `default` command.
#
# Providers: OpenAI, Anthropic, Google, and registered OpenAI-compatible servers.
#
# Open / tentative:
# - Menus show every model the provider lists; OpenAI includes non-chat models (no filtering).
# - The REPL modes install automatically in an interactive REPL; opt out with the Preference
#   `repl_modes = false` in the `[JAIL]` table of LocalPreferences.toml.

using JAIL

const INTERACTIVE = false   # set to true to open the menus (needs a terminal and API keys)

# --- 1. Menus ------------------------------------------------------------------------------

if INTERACTIVE
    # Provider menu, then that provider's models (arrow keys, Enter; q cancels):
    m = select_model!()
    @show m active_session().model   # a Model, or nothing if cancelled

    # Skip the provider menu:
    m = select_model!(Anthropic())

    # A specific session:
    s = Session("anthropic/claude-sonnet-4-5"; name = "review")
    select_model!(s)
    @show s.model active_session().model default_model()
end

# --- 2. The model REPL mode ----------------------------------------------------------------
#
# Press `|` at an empty julia> prompt; backspace on an empty line returns to julia>.
# The prompt shows the active session and its model:
#
#   (default: anthropic/claude-sonnet-4-5) model> help
#   (default: anthropic/claude-sonnet-4-5) model> providers          # + missing-key notes
#   (default: anthropic/claude-sonnet-4-5) model> models              # current provider's models
#   (default: anthropic/claude-sonnet-4-5) model> models google
#   (default: anthropic/claude-sonnet-4-5) model> select              # menus, active session
#   (default: anthropic/claude-sonnet-4-5) model> select openai
#   (default: anthropic/claude-sonnet-4-5) model> use openai/gpt-5    # set directly
#   (default: openai/gpt-5) model> use anthropic                      # anthropic's own default
#   (default: anthropic/claude-sonnet-4-5) model> default anthropic   # show that provider's default
#   (default: anthropic/claude-sonnet-4-5) model> default anthropic claude-opus-4-5   # ...or save one
#   (default: anthropic/claude-sonnet-4-5) model> default openai/gpt-5  # save the global default
#   (default: openai/gpt-5) model> st
#
# Sessions (see examples/sessions.jl): `sessions`, `session new|use|rm`.
# Tab completes commands, provider names and session names; after `use provider/` it completes
# model ids once that provider's models have been listed in this Julia process.

# --- 3. Misuse -----------------------------------------------------------------------------

# A provider whose key is missing: the error is printed and nothing is selected.
@show select_model!(Google(api_key_env = "JAIL_EXAMPLE_UNSET_VAR"))

# `use provider` / `use_provider!` need that provider's own default model saved first
# (`set_default_model!(p, "model-id")`, or `default provider model-id` in the REPL mode):
function show_error(f)
    try
        f()
    catch e
        println("  ", sprint(showerror, e))
    end
end
register_provider!(OpenAICompatible("jail-example-misuse", "http://localhost:1234/v1"))
show_error(() -> use_provider!(OpenAICompatible("jail-example-misuse")))
