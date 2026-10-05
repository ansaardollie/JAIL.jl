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
#   tool_approval = "auto"   # which security levels are confirmed [y/N] before running:
#                            #   "all" every call, "auto" medium + high (default), "none" high
#                            #   only, "yolo" never. Replaces `confirm_tools` (no longer read).
#
# Security and preview: each tool has a level (:low, :medium default, :high, or a function of
# the call's arguments returning one) and an optional `preview` of its arguments shown in the
# confirmation prompt and under the streamed `→ label` line (one argument's raw text, several
# as `name = value`, or a function's text). examples/tool_security.jl runs them against a
# scripted local model so the prompts and previews can be seen offline.
#
# REPL: in the `|` mode, `tools` lists tools by group (* = used by the active session), `tools
# show <name>`, `tools use/add/drop <name>...` (`group:<group>` = every tool in it), `tools all`,
# `tools none`. The `}` mode streams `→ label` / `← label: result` lines as calls happen; the
# finished turn shows a `Tool calls` block (✓/✗, label, `View` link to the call's JSON via
# OSC 8), then `Response (model; N in; M out):` and the reply text.
#
# Groups and labels: every tool is in a group ("global" unless `group=` is given) and has a
# label for display (default: the function name as written). The model sees neither.
#
# Saved calls: each ToolResult gets an `id` (UUID v7) when chat! runs the call, and the call +
# result pair is written to <storage_dir>/tools/<session id>/<id>.json (unless
# `persist_sessions = false`).
#
# Open / tentative:
# - Security/preview functions get every parameter of the tool; optional ones the model left out
#   are `nothing`.
# - Descriptions come from the standard docstring above the function (not one inside the body).
# - No `name =` override: functions whose names aren't valid tool names must be renamed.
# - Calls run one after another; no `tool_choice` (forcing a tool) yet.
# - No public function returns a call's JSON path; section 5 builds it from the default
#   storage_dir ".jail".
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

# --- 2b. Groups and labels ----------------------------------------------------------------

"List the names in a directory."
list_files(dir::String = ".") = readdir(dir)

"Read a text file."
read_text(path::String) = read(path, String)

@tool group=files list_files read_text                # both in group "files"
register_tool!(list_files; group = "files", label = "List files")   # same, plus a label
show(stdout, MIME"text/plain"(), tools("files")[1]); println()
@show [(t.name, t.group, t.label) for t in tools()]

try
    @eval @tool label="Both" list_files read_text     # a label names one tool
catch e
    println("ArgumentError: ", e.error.msg)
end

# --- 2c. Security levels and argument previews --------------------------------------------

"Evaluate Julia code and return the printed output."
run_julia(code::String) = sprint(io -> show(io, include_string(Module(), code)))

# High: with the default tool_approval = "auto" every call is confirmed, showing only the code.
@tool security=high preview=code label="Julia code" run_julia

# Level from the arguments: low inside the working directory, high anywhere else.
register_tool!(read_text; group = "files",
               security = path -> startswith(abspath(path), pwd() * "/") ? :low : :high,
               preview = [:path])

@tool security=low get_weather                        # never confirmed unless "all"

for t in (tools("global")..., tools("files")...)
    println(rpad(t.name, 15), "security = ", t.security isa Symbol ? t.security : "by arguments",
            ", preview = ", t.preview === nothing ? "none" : t.preview isa Function ? "custom" : t.preview)
end

for bad in (() -> register_tool!(run_julia; security = :critical),
            () -> register_tool!(run_julia; preview = :source))
    try
        bad()
    catch e
        println("ArgumentError: ", e.msg)
    end
end

# --- 3. Which tools a session offers -----------------------------------------------------

s = Session("anthropic/claude-sonnet-4-5"; name = "tools-demo")
@show tools(s)                                        # every registered tool (the default)
@show set_tools!(s, [get_weather, "echo"])            # restrict by function or name
@show set_tools!(s, [])                               # none
@show set_tools!(s, nothing)                          # back to all, incl. tools registered later
show(stdout, MIME"text/plain"(), s); println()

r = Session("openai/gpt-6-luna"; name = "weather-only", tools = [get_weather])
@show tools(r)
@show set_tools!(s, tools("files"))                   # just one group
set_tools!(s, nothing)

# --- 4. Tool calls and results are messages ------------------------------------------------

call = ToolCall("call_1", "get_weather", Dict("city" => "Paris"))
reply = AssistantMessage([call]; stop_reason = :tool_use)
results = ToolResultMessage([ToolResult("call_1", "get_weather", "Sunny for 3 days in Paris")])
show(stdout, MIME"text/plain"(), reply); println()
show(stdout, MIME"text/plain"(), results); println()
@show results.content[1].id                           # nothing: chat! sets it when it runs a call

# --- 5. Letting the model call tools (live) ------------------------------------------------

if LIVE
    reply = chat!(r, "Should I pack an umbrella for Paris this weekend?")
    show(stdout, MIME"text/plain"(), reply); println()
    foreach(m -> (show(stdout, MIME"text/plain"(), m); println()), r.messages)   # prompt, calls, results, answer

    # Each call + result pair has an id and its own JSON file:
    result = r.messages[3].content[1]
    @show result.id
    println(read(joinpath(".jail", "tools", string(r.id), string(result.id, ".json")), String))

    # Streaming prints → get_weather / ← get_weather: … lines between the text:
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

try
    tools("shell")                                    # no such group
catch e
    println("ArgumentError: ", e.msg)
end
