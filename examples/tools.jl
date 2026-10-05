# Tools: definitions, sessions, and letting a model call them
#
# What: turn ordinary Julia functions into tools a model may call. `register_tool!(f)` reflects
# on `f` (name, positional argument types, docstring) and stores a `ToolSpec` in JAIL's tool
# registry; `@tool f g h` does the same for several functions at once. Every session offers all
# registered tools unless restricted with `set_tools!`. When the model calls a tool, `chat!`
# runs it, sends the result back and asks again, until the model answers.
#
# Providers: all. OpenAI (Responses `function_call` / `function_call_output`), Anthropic
# (`tool_use` / `tool_result`), Google (Interactions `function_call` / `function_result`),
# OpenAI-compatible (Responses, or Chat Completions `tool_calls` / `role: tool`). Streaming too.
#
# Preferences (in [JAIL] of LocalPreferences.toml):
#   max_tool_rounds = 10     # tool rounds per chat! call before calls are answered "not run"
#   confirm_tools = true     # ask [y/N] on the terminal before every tool call (default false)
#
# REPL: in the `|` mode, `tools` lists tools (* = used by the active session), `tools show
# <name>`, `tools use/add/drop <name>...`, `tools all`, `tools none`. The `}` mode runs tools
# and shows each call (→) and result (←).
#
# Open / tentative:
# - Descriptions come from the standard docstring above the function (not one inside the body).
# - No `name =` override: functions whose names aren't valid tool names must be renamed.
# - Calls run one after another; no `tool_choice` (forcing a tool) yet.
# - Thinking models' reasoning is kept on replies as `ReasoningPart`s and resent with the tool
#   results; see examples/reasoning.jl.

using JAIL

LIVE = false    # set to true to make real API calls (needs the provider's API key in ENV)

# --- 1. A documented function becomes a tool ---------------------------------------------

"""
    get_weather(city, days = 3)

Get the weather forecast for a city.

# Arguments
- `city`: the city name, e.g. "Cape Town"
- `days`: how many days to forecast
"""
get_weather(city::String, days::Int = 3) = "Sunny for $days days in $city"

spec = register_tool!(get_weather)
show(stdout, MIME"text/plain"(), spec); println()     # `days` has a default → optional

# --- 2. Several at once with @tool --------------------------------------------------------

@enum Priority low medium high

"Add an item to the to-do list."
add_todo!(title::String, priority::Priority, tags::Vector{String} = String[]) = "added $title ($priority)"

"Return whatever value the model sends (untyped arguments accept any JSON value)."
echo(value) = value

@show @tool add_todo! echo                            # `add_todo!` is exposed as "add_todo_bang"
@show tools()

# --- 3. Which tools a session offers -----------------------------------------------------

s = Session("anthropic/claude-sonnet-4-5"; name = "tools-demo")
@show tools(s)                                        # every registered tool (the default)
@show set_tools!(s, [get_weather, "echo"])            # restrict by function or name
@show set_tools!(s, [])                               # none
@show set_tools!(s, nothing)                          # back to all, incl. tools registered later
show(stdout, MIME"text/plain"(), s); println()

r = Session("openai/gpt-6-luna"; name = "weather-only", tools = [get_weather])
@show tools(r)

# --- 4. Tool calls and results are messages ------------------------------------------------

call = ToolCall("call_1", "get_weather", Dict("city" => "Paris"))
reply = AssistantMessage([call]; stop_reason = :tool_use)
results = ToolResultMessage([ToolResult("call_1", "get_weather", "Sunny for 3 days in Paris")])
show(stdout, MIME"text/plain"(), reply); println()
show(stdout, MIME"text/plain"(), results); println()

# --- 5. Letting the model call tools (live) ------------------------------------------------

if LIVE
    reply = chat!(r, "Should I pack an umbrella for Paris this weekend?")
    show(stdout, MIME"text/plain"(), reply); println()
    foreach(m -> (show(stdout, MIME"text/plain"(), m); println()), r.messages)   # prompt, calls, results, answer

    # Streaming prints each call (→) and result (←) between the text:
    chat!(r, "And Rome for five days?"; stream = true)

    # Cap the rounds for one call; extra calls are answered "not run" and the reply is returned:
    reply = chat!(r, "Compare the weather in ten European capitals."; max_tool_rounds = 1)
    @show reply.stop_reason
end

# --- 6. Registry housekeeping and misuse ------------------------------------------------

register_tool!(get_weather)                           # registering again replaces, no duplicate
@show unregister_tool!("echo") unregister_tool!(add_todo!)
@show tools(s)                                        # unregistered tools drop out of sessions

"Search with options."
search(query::String; limit::Int = 10) = query
register_tool!(search)                                # warns: `limit` is not exposed

area(r::Float64) = π * r^2
area(w::Float64, h::Float64, unit::String) = w * h    # not a prefix of area(r) → error
for f in (area, (io::IO) -> nothing)
    try
        register_tool!(f)
    catch e
        println("ArgumentError: ", e.msg)
    end
end

try
    set_tools!(s, ["get_forecast"])
catch e
    println("ArgumentError: ", e.msg)
end
