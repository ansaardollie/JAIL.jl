# Sessions
#
# What: a `Session` holds one conversation: a name, the active model, optional system
# instructions, and the typed message history. JAIL starts a session named "default" (model from
# the saved default, or none) and makes it active; the REPL modes always use the active session.
# Every session is registered, so the REPL can list and switch to sessions created in code.
#
# Providers: all (history is provider-agnostic, so a session can switch provider mid-conversation).
#
# Open / tentative:
# - Messages are added by `chat!` (see examples/chat.jl); this script keeps history empty.
# - Built-in system instructions: their environment line is captured at session creation, so the
#   "default" session (created by `using JAIL`) lists only packages loaded before JAIL.
# - Sessions offer every registered tool unless restricted (see examples/tools.jl).
# - Sessions stay registered (and in memory) until `delete_session!`.
# - Saving to disk and restoring: see examples/session_persistence.jl.

using JAIL

# --- 1. The default session ----------------------------------------------------------------

@show active_session()          # "default", created when JAIL loaded
@show sessions()

# --- 2. Creating sessions (each is registered) ---------------------------------------------

s = Session("anthropic/claude-sonnet-4-5"; name = "review", system = "Be terse.")
show(stdout, MIME"text/plain"(), s); println()

g = Session(Model(Google(), "gemini-3.8-flash"))          # unnamed → "session"
@show g
r2 = Session("anthropic/claude-sonnet-4-5"; name = "review")   # names may repeat; ids differ
@show r2 r2.id != s.id

# Without a model, the saved default is used (and is what new sessions start with):
set_default_model!("openai/gpt-5")
@show Session()

# --- 3. Switching models (history is kept) -------------------------------------------------

@show set_model!(s, "google/gemini-3.8-flash")
@show s.model s.system length(s.messages)
@show default_model()           # unchanged: set_model! only touches the session

empty!(s)                       # clear history, keep model and system

# --- System instructions -------------------------------------------------------------------

# Without `system`, sessions get JAIL's REPL instructions plus an environment line:
println(active_session().system)
@show Session("openai/gpt-5"; name = "no-system", system = "").system   # opt out
delete_session!("no-system")
# Preference `system_prompt = "..."` replaces the instructions for new sessions ("" = none).

# Menus for one session (needs a terminal and API keys):
#   select_model!(s)
#   select_model!()             # the active session

# --- 4. The active session -----------------------------------------------------------------

w = new_session!("work"; model = "anthropic/claude-sonnet-4-5")   # create + activate
@show active_session() === w
@show set_model!("openai/gpt-5")          # no session: the active one ("work")
@show w.model

use_session!(s)                 # a Session, its id, or a name (a menu picks if the name is shared)
@show active_session().name

delete_session!(r2.id)          # by id: a UUID or its string
@show [x.name for x in sessions()]

use_session!("default")

# The same from the `|` REPL mode:
#   (default: openai/gpt-5) model> sessions
#   (default: openai/gpt-5) model> session new work anthropic/claude-sonnet-4-5
#   (work: anthropic/claude-sonnet-4-5) model> session use review
#   (review: google/gemini-3.8-flash) model> use openai/gpt-5      # active session only
#   (review: openai/gpt-5) model> default anthropic/claude-sonnet-4-5  # new sessions' model
#   (review: openai/gpt-5) model> session rm work

# --- 5. Misuse -----------------------------------------------------------------------------

function show_error(f)
    try
        f()
    catch e
        println("  ", sprint(showerror, e))
    end
end

println("\nErrors:")
show_error(() -> Session("claude-sonnet-4-5"))              # no provider prefix
show_error(() -> Session("openai/gpt-5"; name = "my work")) # names are single words
show_error(() -> set_model!(s, "mistral/large"))            # unknown provider
show_error(() -> delete_session!(active_session()))         # can't delete the active one
show_error(() -> use_session!("nope"))                      # unknown session
show_error(() -> Session("openai/gpt-5"; name = string(r2.id)))   # a name can't be a UUID
show_error(() -> (s.messages = AbstractMessage[]))          # history can be emptied, not replaced
