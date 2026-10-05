# Session persistence
#
# What: every session is saved to disk from its first message on, and `restore_session!` brings
# one back (in this or a later Julia process) and makes it active.
#   <storage_dir>/sessions/<id>.json    name, id, created, model, system, tools
#   <storage_dir>/messages/<id>.jsonl   one message per line, appended as the chat grows
#   <storage_dir>/tools/<id>/<pair id>.json   one file per tool call + result (see examples/tools.jl)
# `storage_dir` is a Preference (default ".jail" in the working directory);
# `persist_sessions = false` turns saving off.
#
# Providers: all. Models are saved as "provider/model" and resolved through the Preferences when
# restored, so a session made with a one-off provider instance (custom base_url) comes back on the
# configured provider of that name.
#
# Open / tentative:
# - Section 2 needs a live provider (default model + API key); sections 1 and 4 run offline.
# - The first turn after a restore resends the full history (server-side chaining state is not saved).
# - In-place edits of `s.messages` (other than shrinking it) are not written to disk.

using JAIL

# --- 1. Ids and creation times ---------------------------------------------------------------

s = Session(; name = "persist-demo")
@show s.id                     # UUID v7: sorts by creation time
@show s.created                # DateTime, UTC (same instant as the id's timestamp)
show(stdout, MIME"text/plain"(), s); println()
# Nothing is on disk yet: a session without messages is not saved.

# --- 2. Chat: each message is appended to the session's .jsonl file (live call) ---------------

reply = chat!(s, "Name one Julia package for plotting, in one word.")
@show string(reply)
id = s.id

# Delete it from memory; the files stay, so it can come back.
delete_session!(s)
@show [x.name for x in sessions()]

# --- 3. Restore ----------------------------------------------------------------------------

r = restore_session!(id)                 # by id (a UUID or its string)
@show r.name length(r.messages) active_session() === r
@show restore_session!(string(id)) === r # already loaded: just activated

# From a menu (needs a terminal): newest first, "name  created  first prompt…"
#   restore_session!()
# The same from the `|` REPL mode:
#   (default: anthropic/claude-sonnet-4-5) model> session restore

empty!(r)                                # the .jsonl file is emptied too

use_session!("default")
delete_session!(r; files = true)         # also removes its files (session, messages, tool calls)
#   (default: anthropic/claude-sonnet-4-5) model> session rm persist-demo --files

# --- 4. Misuse -----------------------------------------------------------------------------

function show_error(f)
    try
        f()
    catch e
        println("  ", sprint(showerror, e))
    end
end

println("\nErrors:")
show_error(() -> restore_session!("not-a-uuid"))
show_error(() -> restore_session!("01a10445-42d7-7b5a-85f7-ceafc2db4931"))   # not saved here
