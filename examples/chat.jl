# Chat: sending turns on a session
#
# What: `chat!(session, prompt)` sends the session's whole history (plus its `system`
# instructions) to the session's model, appends the prompt and the reply to `session.messages`,
# and returns the reply as an `AssistantMessage`. `chat!(prompt)` does the same on the active
# session. Messages are provider-agnostic (`UserMessage`, `AssistantMessage`, made of
# `TextPart`s), so a session can switch provider mid-conversation. In the REPL, press `}` for
# the chat mode: each line is `chat!` on the active session (section 5).
#
# Providers: OpenAI (Responses), OpenAICompatible (Responses, or Chat Completions with
# `api = :chat_completions`), Anthropic (Messages), Google (Interactions). Text only.
#
# Preferences (in [JAIL] of LocalPreferences.toml):
#   max_tokens = 2048        # default reply cap for every provider (else Anthropic: model max, others: unset)
#   store_requests = false   # OpenAI/Google: send store=false and the full history (default true)
#   stream = true            # stream replies in the `}` REPL mode (default false)
#
# Open / tentative:
# - No images or reasoning yet (tools: examples/tools.jl). Reasoning/thought output (OpenAI reasoning
#   items, Google thought steps and their signatures) is dropped, not replayed.
# - OpenAI and Google continue from the last stored reply (`previous_response_id` /
#   `previous_interaction_id` = `reply.id`) and send only the new turn; the full history is sent
#   when it was edited, the provider changed, or the stored reply expired. Anthropic and
#   OpenAI-compatible servers always get the full history.
# - Seeding a history (few-shot) is done by pushing onto `session.messages` directly.
# - Troubleshooting: `ENV["JULIA_DEBUG"] = "JAIL"` logs each request and response body.

using JAIL

LIVE = false    # set to true to make real API calls (needs the provider's API key in ENV)

# --- 1. Messages (offline) -----------------------------------------------------------------

u = UserMessage("What is 2 + 2?")
a = AssistantMessage("4")                    # hand-written: no model, stop_reason or usage
@show u a
@show string(a)                              # the text
@show u.content                              # always a Vector of content parts

# --- 2. A session with a seeded (few-shot) history ------------------------------------------

s = Session("openai/gpt-6-luna"; name = "chat-demo", system = "Answer with one word.")
push!(s.messages, UserMessage("Colour of the sky?"), AssistantMessage("Blue"))
@show s.messages

# --- 3. Sending turns (live) -----------------------------------------------------------------

if LIVE
    reply = chat!(s, "Colour of grass?")
    show(stdout, MIME"text/plain"(), reply); println()
    @show reply.stop_reason reply.usage reply.model reply.id   # id: what the next turn chains from

    # Cap the reply length for one call:
    reply = chat!(s, "Now describe a forest in detail."; max_tokens = 20)
    @show reply.stop_reason                  # likely :max_tokens

    # Stream: prints the text as it arrives, still returns the full reply
    reply = chat!(s, "Name three trees, one per line."; stream = true)
    @show reply.usage

    # Switch provider, keep the history:
    set_model!(s, "anthropic/claude-opus-5-5")
    @show chat!(s, "Colour of snow?")
    @show s.messages

    # The active session (what the REPL modes use):
    use_session!(s)
    @show chat!("Colour of coal?")

    # See the raw request/response bodies:
    #   ENV["JULIA_DEBUG"] = "JAIL"; chat!(s, "hi"); ENV["JULIA_DEBUG"] = ""
end

# --- 4. Misuse ---------------------------------------------------------------------------------

function show_error(f)
    try
        f()
    catch e
        println("  ", sprint(showerror, e))
    end
end

println("\nErrors:")
n = length(s.messages)
show_error(() -> chat!(s, "   "))                                # empty prompt
show_error(() -> chat!(s, "hi"; max_tokens = 0))                 # bad cap
show_error(() -> AssistantMessage("x"; stop_reason = :stop))     # unknown stop reason
@show length(s.messages) == n                                    # failed calls leave history alone

use_session!("default")
delete_session!(s)

# --- 5. The `}` chat REPL mode (interactive only) ---------------------------------------------
#
# Press `}` at an empty julia> prompt; backspace on an empty line returns. Replies render as
# Markdown (with Preference `stream = true` they stream on the alternate screen first); a line follows only if the reply didn't end normally. Enter sends; Ctrl+J (any
# terminal), Alt+Enter, or Shift/Ctrl/Cmd+Enter (where the terminal reports them; VS Code needs
# the keybindings in docs/src/guide/repl.md) starts a new line.
#
#   chat> Explain this error:
#         ERROR: MethodError: no method matching +(::String, ::Int64)
#     You're adding a String and an Int; ...
#   chat> Tell me a long story
#     Once upon
#   [stop reason: max_tokens]
#   chat> /clear
#   Cleared 4 messages from session "default"
#
# The same from code:
#   chat!("How do I append to a vector?")     # active session
#   empty!(active_session())                  # /clear
