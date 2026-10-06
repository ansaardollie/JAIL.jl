# Parallel tool calls
#
# What: a model may call several tools in one reply. With the Preference `parallel_tool_calls`
# on (the default), JAIL confirms the calls that need it one by one, runs the calls of tools
# registered with `concurrent = false` one after another, then runs the rest at the same time
# (threads when Julia has more than one, else tasks). Results go back in call order.
# `parallel_tool_calls = false` asks the provider for at most one call per reply and runs calls
# one by one. `providers.<name>.parallel_tool_calls` overrides the top-level value per provider.
#
# Providers: OpenAI (`parallel_tool_calls`), OpenAI-compatible (same field, Responses and Chat
# Completions) and Anthropic (`tool_choice.disable_parallel_tool_use`) honour `false`. Google has
# no such field: Gemini may still call several tools, which JAIL then runs one by one.
#
# Runs offline against a scripted stand-in model (a local server speaking the OpenAI Responses
# format, used through `OpenAICompatible`): it calls all three tools in one reply, unless the
# request says `parallel_tool_calls: false`, in which case it calls them one per reply, as a real
# provider would.
#
# Open / tentative:
# - No public setter for `parallel_tool_calls` (nor an `agent!` keyword); this script uses
#   Preferences.jl directly and restores the previous value.
# - The ToolSpec field and keyword are named `concurrent`.
# - Calls that run alone go before the concurrent batch, not in the model's order.

using JAIL
using HTTP: HTTP
using JSON: JSON
using Preferences: Preferences

# --- 1. Tools: two slow lookups that can overlap, and one that must run alone --------------

const T0 = Ref(time())
const QUIET = Ref(false)
const PRINTING = ReentrantLock()   # the weather calls print from different threads
stamp(what) = QUIET[] || lock(PRINTING) do
    println("    ", rpad(what, 22), round(time() - T0[]; digits = 1), " s")
end

"""
    weather(city)

The weather in a city.
"""
weather(city::String) = (stamp("weather($city) start"); sleep(1); stamp("weather($city) end"); "Sunny in $city")

"""
    append_log(text)

Append a line to the trip log.
"""
append_log(text::String) = (stamp("append_log start"); sleep(0.3); stamp("append_log end"); "logged")

register_tool!(weather; group = "trip", security = :low, preview = :city)
@tool group=trip security=low concurrent=false append_log
show(stdout, MIME"text/plain"(), only(filter(t -> t.name == "append_log", tools("trip"))))
println("\n")

# --- 2. A scripted model ---------------------------------------------------------------------

CALLS = [("weather", Dict("city" => "Paris")), ("weather", Dict("city" => "Rome")),
         ("append_log", Dict("text" => "checked the weather"))]

message(text) = Dict("type" => "message", "role" => "assistant",
                     "content" => [Dict("type" => "output_text", "text" => text)])
call(i) = Dict("type" => "function_call", "call_id" => "call_$i", "name" => CALLS[i][1],
               "arguments" => JSON.json(CALLS[i][2]))

function scripted_reply(body)
    done = count(x -> get(x, "type", nothing) == "function_call_output", body["input"])
    output = if done == length(CALLS)
        [message("Paris and Rome are sunny; logged.")]
    elseif get(body, "parallel_tool_calls", true)
        [call(i) for i in 1:length(CALLS)]
    else
        [call(done + 1)]
    end
    return Dict("id" => "resp_$(rand(UInt32))", "status" => "completed", "output" => output,
                "usage" => Dict("input_tokens" => 0, "output_tokens" => 0))
end

server = HTTP.serve!("127.0.0.1", 0) do req
    body = JSON.parse(String(req.body))
    reply = scripted_reply(body)
    get(body, "stream", false) || return HTTP.Response(200, ["Content-Type" => "application/json"], JSON.json(reply))
    text = join((c["text"] for o in reply["output"] if o["type"] == "message" for c in o["content"]), "")
    events = [Dict("type" => "response.output_text.delta", "delta" => text),
              Dict("type" => "response.completed", "response" => reply)]
    HTTP.Response(200, ["Content-Type" => "text/event-stream"], join(("data: $(JSON.json(e))\n\n" for e in events)))
end
scripted = OpenAICompatible("scripted", "http://127.0.0.1:$(HTTP.port(server))/v1")

# --- 3. Parallel (default) vs one call per reply ---------------------------------------------

previous = Preferences.load_preference(JAIL, "parallel_tool_calls")
set_tool_auto_approval!("group:trip", true)    # no [y/N] prompts for this demo
println("Julia threads: ", Threads.nthreads())
try
    for parallel in (true, false)
        Preferences.set_preferences!(JAIL, "parallel_tool_calls" => parallel; force = true)
        local s = Session(Model(scripted, "demo"); name = "parallel-demo-$parallel", tools = tools("trip"))
        load_tools!(s, "weather", "append_log")
        println("\nparallel_tool_calls = $parallel")
        T0[] = time()
        reply = agent!(s, "Weather in Paris and Rome? Log it.")
        println("    took ", round(time() - T0[]; digits = 1), " s, ",
                count(m -> m isa AssistantMessage, s.messages), " model replies: ", string(reply))
    end

    # Streaming: the run-alone call gets its own `→` line, the calls that ran together share
    # one (`→ weather (Paris) | weather (Rome)`), and no `←` result lines are printed (the Tool
    # calls box lists the results).
    Preferences.set_preferences!(JAIL, "parallel_tool_calls" => true; force = true)
    QUIET[] = true
    println("\nstream = true")
    local st = Session(Model(scripted, "demo"); name = "parallel-demo-stream", tools = tools("trip"))
    load_tools!(st, "weather", "append_log")
    agent!(st, "Weather in Paris and Rome? Log it."; stream = true)
finally
    QUIET[] = false
    previous === nothing ? Preferences.delete_preferences!(JAIL, "parallel_tool_calls"; force = true) :
        Preferences.set_preferences!(JAIL, "parallel_tool_calls" => previous; force = true)
    set_tool_auto_approval!("group:trip", nothing)
end

# --- 4. Misuse --------------------------------------------------------------------------------

try
    @eval @tool concurrent=maybe weather
catch e
    println("\n", sprint(showerror, e isa LoadError ? e.error : e))
end
Preferences.set_preferences!(JAIL, "parallel_tool_calls" => "yes"; force = true)
try
    agent!(Session(Model(scripted, "demo"); tools = tools("trip")), "Weather?")
catch e
    println(sprint(showerror, e))
finally
    previous === nothing ? Preferences.delete_preferences!(JAIL, "parallel_tool_calls"; force = true) :
        Preferences.set_preferences!(JAIL, "parallel_tool_calls" => previous; force = true)
end

close(server)
foreach(unregister_tool!, ["weather", "append_log"])
