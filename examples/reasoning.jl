# Reasoning: what thinking models leave on their replies, and where it goes
#
# What: thinking models return their reasoning as opaque, signed records alongside the reply.
# JAIL keeps each one as a `ReasoningPart` in `reply.content` (readable `text`, often empty, plus
# the provider's opaque `data` in a wire `format`). It is not part of `string(reply)`. When the
# full history is sent again (Anthropic always; OpenAI/Google when the history can't continue
# from a stored reply, or with `store_requests = false`; GoogleEnterprise with
# `api = :generate_content`), the parts go back unchanged, which providers require for tool
# calls. They go back only to the provider type and wire format that produced them.
#
# Providers and formats:
#   :anthropic                Anthropic `thinking` / `redacted_thinking` blocks
#   :openai_responses         OpenAI (and compatible) Responses `reasoning` items
#   :google_interactions      Google / GoogleEnterprise Interactions `thought` steps
#   :google_generate_content  GoogleEnterprise generateContent `thoughtSignature` (on any part)
#   :chat_completions         reasoning text from compatible Chat Completions servers (never sent back)
#
# Controls (all providers): `thinking_effort` (a Symbol, sent as-is), `temperature` (a number),
# `show_reasoning` (ask for summaries; stream them dimmed; save each trace as a Markdown file with
# YAML front matter under `<storage_dir>/reasoning/<session id>/`). Effort and temperature come from the chat! keyword,
# then the session (`set_thinking_effort!` / `set_temperature!`), then Preferences.
#
# Open / tentative:
# - Levels are not checked or mapped: `:max` on Google or `:minimal` on Anthropic is the API's error.
# - On Anthropic, any effort but `:none` sends adaptive thinking, which extended-thinking-only
#   models (e.g. Haiku 4.5) reject; without an effort no thinking settings are sent, so
#   `show_reasoning` alone gets no summaries there.
# - `format` and `data` are provider details exposed on a public type; treat them as read-only.

using JAIL

LIVE = false    # set to true to make real API calls (needs ANTHROPIC_API_KEY in ENV)

# --- 1. Effort and temperature on a session -----------------------------------------------

s = Session("anthropic/claude-opus-4-8"; name = "effort-demo", thinking_effort = :low)
@show s.thinking_effort s.temperature
set_temperature!(s, 0.3)
set_thinking_effort!(s, :high)
show(stdout, MIME"text/plain"(), s); println()
set_thinking_effort!(s, nothing)   # back to the Preference `thinking_effort`, if set
@show s.thinking_effort

# --- 2. A ReasoningPart -------------------------------------------------------------------

r = ReasoningPart("Check the tool first.", :anthropic,
                  Dict("type" => "thinking", "thinking" => "Check the tool first.", "signature" => "EosnCkYI..."))
@show r r.text r.format

# It sits in a reply's content but is not part of the reply's text:
reply = AssistantMessage([r, TextPart("It's 22°C.")])
@show reply.content string(reply)

# A hand-written reply has no model, so its reasoning is never sent anywhere:
@show reply.model

# --- 3. From a live tool round, with summaries shown -------------------------------------

"""
    get_current_temperature(location)

Gets the current temperature for a given location.

# Arguments
- `location`: the city name, e.g. "London"
"""
get_current_temperature(location::String) = "22°C in $location"

if LIVE
    t = Session("anthropic/claude-sonnet-5"; name = "reasoning-demo", tools = [get_current_temperature])
    # Streams the summaries dimmed, then the boxed turn with a `Reasoning` box linking to the
    # saved summaries.
    reply = chat!(t, "What is the temperature in London?"; stream = true, show_reasoning = true,
                  thinking_effort = :medium)
    for m in t.messages
        m isa AssistantMessage || continue
        @show m.content     # e.g. [ReasoningPart(:anthropic, "The user wants…"), ToolCall(get_current_temperature(...))]
    end
    # Set ENV["JULIA_DEBUG"] = "JAIL" before chat! to see the `thinking` block sent back with
    # the tool result. After `set_model!(t, "openai/gpt-5-mini")` it is left out.
    delete_session!(t)
end

# --- 4. Misuse ----------------------------------------------------------------------------

# `format` is a Symbol naming the wire format, not a provider name string:
try
    ReasoningPart("", "anthropic", Dict())
catch e
    println(sprint(showerror, e; context = :limit => true)[1:min(end, 120)], "…")
end

# Effort is a Symbol and temperature a non-negative number; both are checked before any request:
try
    chat!(s, "Hi"; thinking_effort = 3)
catch e
    showerror(stdout, e); println()
end
try
    set_temperature!(s, -0.5)
catch e
    showerror(stdout, e); println()
end
@show length(s.messages)   # the failed turn left no trace
delete_session!(s)

# `format` is a Symbol naming the wire format, not a provider name string:
try
    ReasoningPart("", "anthropic", Dict())
catch e
    println(sprint(showerror, e; context = :limit => true)[1:min(end, 120)], "…")
end
