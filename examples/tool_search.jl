# Tool search: register many tools, load only a few
#
# What: a session's tools are either *loaded* (the model gets their full definitions on every
# request) or just *registered* (the model finds them with tool search when a task needs them).
# Every built-in tool is registered at load and none is loaded, so a fresh session sends almost
# no tool definitions. A tool's status in a session is :unregistered, :registered or :loaded.
#
# Providers:
# - OpenAI, Anthropic: hosted search. Registered tools go out with `defer_loading: true` plus the
#   provider's search tool (OpenAI `tool_search`, Anthropic `tool_search_tool_bm25_20251119`);
#   the search steps come back as ToolSearchPart entries in the reply. Needs gpt-5.4+ / Claude 4.5+;
#   Preference `providers.<name>.tool_search = "client"` switches to JAIL's tools for older models.
# - Google, GoogleEnterprise, OpenAI-compatible: JAIL's own `tool_search(keywords)` and
#   `tool_load(names)` tools; `tool_load` loads tools in the calling session only.
#
# Preferences: `registered_tools` (built-ins registered at load, default all), `loaded_tools`
# (what new sessions load, default none).
#
# Runs offline: a local stand-in server plays Anthropic and Google, scripted with fixed replies,
# and prints the tools each request carried.
#
# Open / tentative:
# - `register_tool!(f; load = true)` loads in the *active* session only; a Session created
#   afterwards doesn't get it (use `loaded_tools = [...]` or the Preference).
# - tool_search matches a tool's name as well as its description.

using JAIL
using HTTP: HTTP
using JSON: JSON

"""
    get_weather(city)

Get the weather forecast for a city.
"""
get_weather(city::String) = "Sunny in $(city)"
register_tool!(get_weather; security = :low)

# --- 1. Status per session ------------------------------------------------------------------

s = Session("anthropic/claude-sonnet-4-5"; name = "search_demo", loaded_tools = ["read_file"])
@show length(tools(s))
@show tool_status(s, "read_file") tool_status(s, get_weather) tool_status(s, "no_such_tool")

load_tools!(s, get_weather, "memory")          # a function and a whole group
@show [t.name for t in load_tools!(s, "grep_files")]
unload_tools!(s, "memory")
@show s.loaded_tools

try
    load_tools!(s, "no_such_tool")
catch e
    println("misuse: ", sprint(showerror, e))
end

# --- 2. What each provider is sent (scripted stand-in server) --------------------------------

replies = Any[
    # Anthropic: a hosted search, then the answer.
    Dict("id" => "msg_1", "type" => "message", "role" => "assistant", "stop_reason" => "end_turn",
         "usage" => Dict("input_tokens" => 10, "output_tokens" => 5),
         "content" => [
             Dict("type" => "server_tool_use", "id" => "srvtoolu_1", "name" => "tool_search_tool_bm25",
                  "input" => Dict("query" => "list files in a folder")),
             Dict("type" => "tool_search_tool_result", "tool_use_id" => "srvtoolu_1",
                  "content" => Dict("type" => "tool_search_tool_search_result",
                                    "tool_references" => [Dict("type" => "tool_reference", "tool_name" => "list_dir")])),
             Dict("type" => "text", "text" => "I found `list_dir`.")]),
    # Google: tool_search, tool_load, then the answer.
    Dict("id" => "i1", "status" => "requires_action", "steps" => [Dict("type" => "function_call",
         "id" => "c1", "name" => "tool_search", "arguments" => Dict("keywords" => ["weather"]))]),
    Dict("id" => "i2", "status" => "requires_action", "steps" => [Dict("type" => "function_call",
         "id" => "c2", "name" => "tool_load", "arguments" => Dict("names" => ["get_weather"]))]),
    Dict("id" => "i3", "status" => "completed", "steps" => [Dict("type" => "model_output",
         "content" => [Dict("type" => "text", "text" => "get_weather is loaded now.")])]),
]
sent = []
port = 8977
server = HTTP.serve!("127.0.0.1", port) do req
    push!(sent, JSON.parse(String(req.body)))
    HTTP.Response(200, ["Content-Type" => "application/json"], JSON.json(popfirst!(replies)))
end
ENV["DEMO_DUMMY_KEY"] = "not-a-real-key"
local_url = "http://127.0.0.1:$(port)"

describe(t) = haskey(t, "type") && !haskey(t, "input_schema") && !haskey(t, "parameters") ?
    t["type"] : string(t["name"], get(t, "defer_loading", false) ? " (deferred)" : "")

try
    a = Session(Model(Anthropic(; base_url = local_url, api_key_env = "DEMO_DUMMY_KEY"), "claude-sonnet-4-5");
                name = "anthropic_demo", loaded_tools = ["read_file"])
    reply = chat!(a, "What tool lists a folder?")
    tools_sent = sent[end]["tools"]
    println("\nAnthropic request: ", length(tools_sent), " tools, e.g. ", join(describe.(tools_sent[1:3]), ", "))
    @show reply.content
    println(string(reply))

    g = Session(Model(Google(; base_url = local_url, api_key_env = "DEMO_DUMMY_KEY"), "gemini-3-flash");
                name = "google_demo")
    reply = chat!(g, "What's the weather in Cape Town?")
    for (i, b) in enumerate(sent[2:end])
        println("Google request $(i): tools ", [t["name"] for t in b["tools"]])
    end
    for m in g.messages
        m isa ToolResultMessage && foreach(r -> println("← ", r.name, ": ", r.content), m.content)
    end
    @show tool_status(g, get_weather)
    println(string(reply))
    global demo_sessions = (a, g)
finally
    close(server)
end

# --- 3. Clean up ----------------------------------------------------------------------------

foreach(x -> delete_session!(x; files = true), (s, demo_sessions...))
unregister_tool!(get_weather)
