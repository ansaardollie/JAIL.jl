# Token counting: how many input tokens a session's context takes up
#
# What: `count_tokens(session[, prompt]; model)` asks the model's provider how many input tokens
# the session's system instructions, tool definitions and message history take up, as a
# full-history turn would send them. It returns a `TokenCount` (`total`, `system`, `tools`,
# `messages`). A `prompt` is counted as the next turn without being sent or added; `model`
# counts the same context for another model. Nothing is generated, so it costs no output tokens.
# The `|` REPL mode has the same thing as `tokens [provider/model]`.
#
# Providers (each one's own counting endpoint):
#   OpenAI, OpenAICompatible   POST /responses/input_tokens
#   Anthropic                  POST /v1/messages/count_tokens
#   Google                     POST /v1beta/models/{model}:countTokens (generateContentRequest)
#   GoogleEnterprise           POST .../publishers/google/models/{model}:countTokens
#
# Open / tentative:
# - The breakdown takes up to three requests (messages, + system, + tools) and is approximate:
#   framing tokens land in `messages`. Only `total` is what the provider reports for the full
#   request.
# - Many OpenAI-compatible servers have no /responses/input_tokens; count_tokens throws there.
# - Google's endpoint takes the generateContent format, so Interactions reasoning isn't counted.

using JAIL

LIVE = false    # set to true to make real (free) counting calls; needs the providers' API keys

# --- 1. Nothing to count: no requests are made --------------------------------------------

s = Session("anthropic/claude-sonnet-4-5"; name = "tokens-demo", system = "", tools = [])
@show count_tokens(s)

# --- 2. Misuse ----------------------------------------------------------------------------

try
    count_tokens(s, "   ")
catch e
    showerror(stdout, e); println()
end

try
    count_tokens(s; model = "claude-sonnet-4-5")    # missing the provider
catch e
    showerror(stdout, e); println()
end

delete_session!(s)

# --- 3. Live counts -----------------------------------------------------------------------

"""
    get_weather(city)

Get the current weather for a city.

# Arguments
- `city`: the city name, e.g. "Paris"
"""
get_weather(city::String) = "sunny in $city"

if LIVE
    register_tool!(get_weather)
    s = Session("anthropic/claude-sonnet-4-5"; name = "tokens-demo", tools = [get_weather])

    # JAIL's default REPL system prompt plus one tool, no messages yet:
    c = count_tokens(s)
    show(stdout, MIME"text/plain"(), c); println()

    # What the next turn would send, without sending it:
    @show count_tokens(s, "What's the weather in Paris?").total

    # The same context on other providers' models:
    for m in ("openai/gpt-5-mini", "google/gemini-3-flash")
        @show count_tokens(s; model = m)
    end

    agent!(s, "What's the weather in Paris?")
    @show count_tokens(s)       # now with the prompt, tool call, tool result and reply

    delete_session!(s; files = true)
    unregister_tool!("get_weather")
end
