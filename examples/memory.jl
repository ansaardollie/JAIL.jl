# Memory tools: session memory (this session's task) and agent memory (kept for an agent)
#
# What: six built-in tools in the `memory` group, each scope a numbered list in `<storage_dir>/memory/`:
# `sessions/<id>.md` for session memory and `agents/<agent name>.memory.md` for agent memory. The model
# calls them in agent turns. Applying an agent with `use_agent!` loads them in the session.
#
# Providers: all (tools as in examples/tools.jl). Agent memory is not in the system prompt; the model
# reads it with `read_agent_memory`.
#
# Runs offline: a local stand-in model (OpenAI Responses format via `OpenAICompatible`) prints what each
# request carried. `storage_dir` points at a temporary folder for the run.
#
# Open / tentative:
# - The memory tools take no session argument: they act on the session of the tool call, or the active
#   session when called directly (see design decisions 49 and 50).
# - Agent memory is shared by every session that uses the agent; two agent files with one name share it.

using JAIL
using HTTP: HTTP
using JSON: JSON
using Preferences: Preferences

# --- 1. A scripted model ---------------------------------------------------------------------

sent = Any[]
script = Ref{Any}(body -> Any[])
text(t) = Dict("type" => "message", "role" => "assistant", "content" => [Dict("type" => "output_text", "text" => t)])
call(id, name, args) = Dict("type" => "function_call", "call_id" => id, "name" => name, "arguments" => JSON.json(args))
after_result(body) = get(last(body["input"]), "type", nothing) == "function_call_output"

server = HTTP.serve!("127.0.0.1", 0) do req
    body = JSON.parse(String(req.body))
    push!(sent, body)
    out = Base.invokelatest(script[], body)
    reply = Dict("id" => "resp_$(rand(UInt32))", "status" => "completed", "output" => out,
                 "usage" => Dict("input_tokens" => 0, "output_tokens" => 0))
    get(body, "stream", false) || return HTTP.Response(200, ["Content-Type" => "application/json"], JSON.json(reply))
    delta = join((c["text"] for o in out if o["type"] == "message" for c in o["content"]), "")
    events = [Dict("type" => "response.output_text.delta", "delta" => delta),
              Dict("type" => "response.completed", "response" => reply)]
    HTTP.Response(200, ["Content-Type" => "text/event-stream"], join(("data: $(JSON.json(e))\n\n" for e in events)))
end
scripted = OpenAICompatible("scripted", "http://127.0.0.1:$(HTTP.port(server))/v1")

previous_storage = Preferences.load_preference(JAIL, "storage_dir")
Preferences.set_preferences!(JAIL, "storage_dir" => mktempdir(); force = true)
previous_editor = get(ENV, "JULIA_EDITOR", nothing)
ENV["JULIA_EDITOR"] = "true"

show_results(s, from) = for m in s.messages[from:end]
    m isa ToolResultMessage && foreach(r -> println("← ", r.name, ":\n", r.content), m.content)
end

try
    # --- 2. An agent to share memory with ----------------------------------------------------

    path = new_agent("reviewer"; description = "Reviews code")
    write(path, """
        ---
        name: reviewer
        description: Reviews code
        ---
        Review carefully. Never edit files.
        """)

    # --- 3. Session memory: directives for this session's task -------------------------------

    s = Session(Model(scripted, "demo"); name = "memory-demo")
    use_agent!(s, "reviewer")
    @show filter(n -> endswith(n, "_memory"), s.loaded_tools)
    script[] = b -> after_result(b) ? Any[text("Noted.")] :
                                      Any[call("c1", "add_session_memory", Dict("input" => "Keep the public API unchanged."))]
    from = length(s.messages) + 1
    agent!(s, "For this task, keep the public API unchanged.")
    show_results(s, from)

    # --- 4. Agent memory: kept for every future session with this agent ----------------------

    script[] = b -> after_result(b) ? Any[text("Saved.")] :
                                      Any[call("c2", "add_agent_memory", Dict("input" => "Use four-space indents."))]
    from = length(s.messages) + 1
    agent!(s, "I always want four-space indents; remember that.")
    show_results(s, from)

    s2 = Session(Model(scripted, "demo"); name = "memory-demo-2")
    use_agent!(s2, "reviewer")
    script[] = b -> after_result(b) ? Any[text("Four-space indents.")] : Any[call("c3", "read_agent_memory", Dict())]
    from = length(s2.messages) + 1
    agent!(s2, "What indents do I want?")
    show_results(s2, from)

    # --- 5. Misuse: a number with no memory -------------------------------------------------

    script[] = b -> after_result(b) ? Any[text("Could not remove it.")] : Any[call("c4", "remove_agent_memory", Dict("number" => 9))]
    from = length(s2.messages) + 1
    agent!(s2, "Remove memory 9.")
    show_results(s2, from)
finally
    close(server)
    previous_storage === nothing ? Preferences.delete_preferences!(JAIL, "storage_dir"; force = true) :
        Preferences.set_preferences!(JAIL, "storage_dir" => previous_storage; force = true)
    previous_editor === nothing ? delete!(ENV, "JULIA_EDITOR") : (ENV["JULIA_EDITOR"] = previous_editor)
end
