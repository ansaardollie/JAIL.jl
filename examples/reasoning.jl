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
#
# Open / tentative:
# - JAIL doesn't ask for reasoning summaries (Anthropic `display`, OpenAI `reasoning.summary`,
#   Google `thinking_summaries`), so `text` is usually empty, and the REPL doesn't show it.
# - `format` and `data` are provider details exposed on a public type; treat them as read-only.

using JAIL

LIVE = false    # set to true to make real API calls (needs ANTHROPIC_API_KEY in ENV)

# --- 1. A ReasoningPart -------------------------------------------------------------------

r = ReasoningPart("Check the tool first.", :anthropic,
                  Dict("type" => "thinking", "thinking" => "Check the tool first.", "signature" => "EosnCkYI..."))
@show r r.text r.format

# It sits in a reply's content but is not part of the reply's text:
reply = AssistantMessage([r, TextPart("It's 22°C.")])
@show reply.content string(reply)

# A hand-written reply has no model, so its reasoning is never sent anywhere:
@show reply.model

# --- 2. From a live tool round ------------------------------------------------------------

"""
    get_current_temperature(location)

Gets the current temperature for a given location.

# Arguments
- `location`: the city name, e.g. "London"
"""
get_current_temperature(location::String) = "22°C in $location"

if LIVE
    s = Session("anthropic/claude-sonnet-5"; name = "reasoning-demo", tools = [get_current_temperature])
    chat!(s, "What is the temperature in London?")
    for m in s.messages
        m isa AssistantMessage || continue
        @show m.content     # e.g. [ReasoningPart(:anthropic, ""), ToolCall(get_current_temperature(...))]
    end
    # Set ENV["JULIA_DEBUG"] = "JAIL" before chat! to see the `thinking` block sent back with
    # the tool result. After `set_model!(s, "openai/gpt-5-mini")` it is left out.
    delete_session!(s)
end

# --- 3. Misuse ----------------------------------------------------------------------------

# `format` is a Symbol naming the wire format, not a provider name string:
try
    ReasoningPart("", "anthropic", Dict())
catch e
    println(sprint(showerror, e; context = :limit => true)[1:min(end, 120)], "…")
end
