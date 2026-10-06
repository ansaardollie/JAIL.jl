# Agents and skills: the agent mode next to the text-only chat mode
#
# What: `chat!` (and the `}` REPL mode) is text only. `agent!` (and the `&` REPL mode) lets the
# model call tools until it is done, shaped by an *agent* (a Markdown file with YAML front
# matter: instructions, `tools` that are loaded and run without asking, `disallowedTools` left
# out) and *skills* (`<name>/SKILL.md`: instructions the model activates with `activate_skill`,
# or that you run with `run_skill!` / `/name` in `&`). Agents and skills are found in
# `.github|.claude|.copilot/{agents,skills}` (current directory), `<storage_dir>/{agents,skills}`
# and `~/.claude`, `~/.agents`, `~/.copilot`. Without an agent, agent turns use the built-in
# `julia` agent.
#
# Providers: all (tools as in examples/tools.jl). Chat turns after agent turns send the tools
# named in the history with `tool_choice` "none" (OpenAI, compatible, Anthropic, Google).
#
# Runs offline: a local stand-in model (OpenAI Responses format via `OpenAICompatible`) prints
# what each request carried. `storage_dir` points at a temporary folder for the run, so the agent
# and skill made here (and the sessions) go there; skills in your home folders are found too.
#
# Open / tentative:
# - `count_tokens` still counts the chat-mode context (decision gate G1 in the plan).
# - `new_agent`/`new_skill` always open the editor; this script sets JULIA_EDITOR to `true` (a
#   no-op command) for the run.
# - Agent names come from front matter `name` or the file name; duplicates ask with a menu.

using JAIL
using HTTP: HTTP
using JSON: JSON
using Preferences: Preferences

# --- 1. A scripted model ---------------------------------------------------------------------

sent = Any[]
script = Ref{Any}(body -> Any[])
text(t) = Dict("type" => "message", "role" => "assistant", "content" => [Dict("type" => "output_text", "text" => t)])
call(id, name, args) = Dict("type" => "function_call", "call_id" => id, "name" => name, "arguments" => JSON.json(args))
results(body) = count(x -> get(x, "type", nothing) == "function_call_output", body["input"])

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

try
    # --- 2. Write an agent and a skill -------------------------------------------------------

    path = new_agent("reviewer"; description = "Reviews code")
    write(path, """
        ---
        name: reviewer
        description: Reviews code
        tools: [Read, grep_files]
        disallowedTools: [run_shell]
        ---
        Review carefully. Never edit files.
        """)
    skill = new_skill("style"; description = "House style for Julia code")
    write(skill, """
        ---
        name: style
        description: House style for Julia code
        when_to_use: when reviewing or writing Julia
        allowed-tools: [read_file]
        ---
        Use four-space indents and `snake_case` names.
        """)
    review = new_skill("review-file"; description = "Review one file")
    write(review, """
        ---
        name: review-file
        description: Review one file
        arguments:
          path: {type: string, description: "File to review"}
          depth: {type: integer, required: false, default: 1}
        argument-hint:
          path: src/chat.jl
        ---
        Review {{path}} to depth {{depth}}.
        """)
    @show [a.name for a in agents()]
    @show filter(n -> n in ("style", "review-file"), [k.name for k in skills()])

    # --- 3. Chat mode: no tools -------------------------------------------------------------

    s = Session(Model(scripted, "demo"); name = "agents-demo")
    script[] = _ -> Any[text("Hello.")]
    chat!(s, "Hi")
    println("chat request tools: ", get(sent[end], "tools", "none"))

    # --- 4. Agent mode with an agent; the model activates a skill -----------------------------

    use_agent!(s, "reviewer")
    @show current_agent(s)
    script[] = b -> results(b) == 0 ? Any[call("c1", "activate_skill", Dict("name" => "style"))] :
                                      Any[text("Looks fine; follows the house style.")]
    reply = agent!(s, "Review src/chat.jl")
    println(string(reply))
    instructions = sent[end]["instructions"]
    println("system prompt has the agent: ", occursin("Review carefully.", instructions),
            ", lists the skill: ", occursin("- `style`", instructions))
    names = [t["name"] for t in sent[end]["tools"] if haskey(t, "name")]
    println("loaded tools include read_file: ", "read_file" in names, ", run_shell sent: ", "run_shell" in names)
    for m in s.messages
        m isa ToolResultMessage && foreach(r -> println("← ", r.name, ": ", first(split(r.content, '\n'))), m.content)
    end

    # --- 5. Chat again: the tools in the history go with tool_choice "none" ------------------

    script[] = _ -> Any[text("You're welcome.")]
    chat!(s, "Thanks")
    println("chat request: tools ", [t["name"] for t in sent[end]["tools"]], ", tool_choice ", sent[end]["tool_choice"])

    # --- 6. Run a skill yourself (what `/review-file src/x.jl` does in the `&` mode) ----------

    script[] = _ -> Any[text("Reviewed.")]
    run_skill!(s, "review-file", "src/x.jl")
    println("prompt sent: ", last(s.messages[end-1].content).text)

    # --- 7. Streaming, as the `&` mode shows it ------------------------------------------------

    use_agent!(s, nothing)
    script[] = _ -> Any[text("Done with **julia**, the built-in agent.")]
    agent!(s, "Anything else?"; stream = true)

    # --- 8. Misuse ---------------------------------------------------------------------------

    for f in (() -> use_agent!(s, "no-such-agent"), () -> new_agent("julia"; description = "x"),
              () -> run_skill!(s, "review-file", "a", "not-a-number"))
        try
            f()
        catch e
            println("misuse: ", sprint(showerror, e))
        end
    end
    delete_session!(s; files = true)
finally
    close(server)
    previous_storage === nothing ? Preferences.delete_preferences!(JAIL, "storage_dir"; force = true) :
        Preferences.set_preferences!(JAIL, "storage_dir" => previous_storage; force = true)
    previous_editor === nothing ? delete!(ENV, "JULIA_EDITOR") : (ENV["JULIA_EDITOR"] = previous_editor)
end
