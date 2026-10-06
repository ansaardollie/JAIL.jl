# Tool security levels, approval modes and argument previews
#
# What: every tool has a security level, :low, :medium (default) or :high, fixed or computed from
# the call's arguments. The Preference `tool_approval` decides which levels are confirmed with
# [y/N] on the terminal before the call runs:
#
#   confirm first?   "all"  "auto" (default)  "none"  "yolo"
#   :low              yes     no               no      no
#   :medium           yes     yes              no      no
#   :high             yes     yes              yes     no
#
# `preview` chooses what the prompt and the streamed `→ label` line show for a call: one
# argument's raw text (code, a shell command), a few arguments as `name = value`, or the text a
# function returns. When streaming already showed the preview, the prompt doesn't repeat it.
#
# Helpers: tool_approval() / set_tool_approval!(mode) read and save the Preference;
# security_level(call), needs_confirmation(call; approval) and tool_preview(call) answer "what
# would the tool loop do with this ToolCall?".
#
# Auto-approvals: the Preference `tool_auto_approvals` overrides all of the above per tool or per
# group: true never asks, false always asks (even in "yolo"). Set it with
# set_tool_auto_approval!(tool, true/false/nothing), by answering `a` at a prompt, or with
# `tools approve` / `tools unapprove` in the `|` REPL mode.
#
# Providers: all (approval happens in JAIL, not at the provider). Section 3 runs offline against
# a scripted stand-in model: a tiny local server speaking the OpenAI Responses format, used through
# `OpenAICompatible`. It is not a real model: it answers exactly the six prompts in SCRIPT, each
# with one fixed tool call, and replies to anything else with that list of prompts.
#
# Running it: section 3 asks [y/N/a] for the calls the chosen MODE confirms, so run it in a
# terminal REPL. Change MODE to see the others. The previous tool_approval and the "demo" group's
# auto-approvals (including any `a` answers) are restored afterwards.
#
# Open / tentative:
# - Security and preview functions get every parameter of the tool; optional ones the model left
#   out are `nothing` (the tool itself still gets its defaults).
# - Restoring a Preference that was unset but equal to "auto" can't be told apart from an
#   explicit "auto"; the example removes it in that case.
# - No public way to replace the whole tool_auto_approvals table; restoring goes entry by entry.
# - The file tools here only pretend; `run_julia` really evaluates code (in a fresh module).

using JAIL
using Dates: now
using HTTP: HTTP
using JSON: JSON

MODE = "auto"     # "all", "auto", "none" or "yolo" for section 3

# --- 1. Tools with levels and previews ---------------------------------------------------

"Return the current date and time."
current_time() = string(now())

"""
    save_note(title, text)

Save a short note.

# Arguments
- `title`: a few words naming the note
- `text`: the note itself
"""
save_note(title::String, text::String) = "saved \"$title\" ($(length(text)) characters)"

"""
    run_julia(code)

Evaluate Julia code in a fresh module and return the value of its last expression.
"""
run_julia(code::String) = repr(include_string(Module(:Sandbox), code))

"""
    shell(cmd)

Run a shell command (demo: only reports what it would run).
"""
shell(cmd::String) = "(demo) would run: $cmd"

"""
    copy_file(src, dst, overwrite = false)

Copy a file (demo: only reports what it would copy).
"""
copy_file(src::String, dst::String, overwrite::Bool = false) =
    "(demo) would copy $src to $dst" * (overwrite ? ", overwriting" : "")

# Read-only commands with plain arguments are low; anything else (pipes, `;`, rm, ...) is high.
const READ_ONLY = r"^(ls|pwd|date|whoami)(\s+[\w./-]+)*$"

@tool group=demo security=low current_time                      # never asked unless "all"
@tool group=demo preview=[title] save_note                       # :medium by default
@tool group=demo security=high preview=code label="Julia code" run_julia
@tool group=demo preview=cmd security=(cmd -> occursin(READ_ONLY, cmd) ? :low : :high) shell
# `overwrite` is `nothing` here when the model leaves it out.
register_tool!(
  copy_file; 
  group = "demo", 
  label = "Copy file",
  security = (src, dst, overwrite) -> overwrite !== true && startswith(normpath(dst), "backup/") ? :medium : :high,
  preview = (src, dst, overwrite) -> "$src → $dst" * (overwrite === true ? " (overwrite)" : "")
)


foreach(t -> (show(stdout, MIME"text/plain"(), t); println("\n")), tools("demo"))

# --- 2. What the tool loop would do with a call -------------------------------------------

calls = [ToolCall("1", "current_time", Dict()),
         ToolCall("2", "save_note", Dict("title" => "Groceries", "text" => "eggs")),
         ToolCall("3", "run_julia", Dict("code" => "sum(1:10)")),
         ToolCall("4", "shell", Dict("cmd" => "ls -la")),
         ToolCall("5", "shell", Dict("cmd" => "ls; rm -rf ~")),
         ToolCall("6", "copy_file", Dict("src" => "a.txt", "dst" => "backup/a.txt")),
         ToolCall("7", "copy_file", Dict("src" => "a.txt", "dst" => "backup/a.txt", "overwrite" => true)),
         ToolCall("8", "copy_file", Dict("src" => "a.txt", "dst" => "/etc/a.txt"))]

modes = ("all", "auto", "none", "yolo")
println(rpad("call", 76), rpad("level", 8), join((rpad(m, 6) for m in modes)), "preview")
for c in calls
    asks = (needs_confirmation(c; approval = m) ? "ask" : "-" for m in modes)
    println(rpad(sprint(show, c), 76), rpad(security_level(c), 8), join((rpad(a, 6) for a in asks)),
            something(tool_preview(c), ""))
end

println("\ntool_approval() = ", repr(tool_approval()))

try
    security_level(ToolCall("9", "shell", Dict("command" => "ls")))     # wrong argument name
catch e
    println("ArgumentError: ", e.msg)
end

# --- 2b. Per-tool overrides: tool_auto_approvals -----------------------------------------

# Put the "demo" group's entries back as they were, once the example is done.
demo_before = get(tool_auto_approvals(), "demo", nothing)
function restore_demo_approvals()
    set_tool_auto_approval!("group:demo", nothing)
    demo_before isa Bool && set_tool_auto_approval!("group:demo", demo_before)
    demo_before isa AbstractDict && foreach(((n, v),) -> set_tool_auto_approval!(n, v), demo_before)
end

asks_row(c) = join((rpad(needs_confirmation(c; approval = m) ? "ask" : "-", 6) for m in modes))
println("\n", rpad("", 28), join((rpad(m, 6) for m in modes)))
println(rpad("save_note, by level:", 28), asks_row(calls[2]))
set_tool_auto_approval!(save_note, true)               # never ask, even under "all"
println(rpad("save_note, approved:", 28), asks_row(calls[2]))
println(rpad("current_time, by level:", 28), asks_row(calls[1]))
set_tool_auto_approval!(current_time, false)           # always ask, even under "yolo"
println(rpad("current_time, always ask:", 28), asks_row(calls[1]))
@show tool_auto_approvals()                            # demo = {save_note = true, current_time = false}
restore_demo_approvals()

try
    set_tool_auto_approval!("group:global", true)      # global tools are approved one by one
catch e
    println("ArgumentError: ", e.msg)
end

# --- 3. Watch it happen: a scripted model calls each tool --------------------------------

const SCRIPT = [
    "What time is it?"           => ("current_time", Dict()),
    "Save a grocery note"        => ("save_note", Dict("title" => "Groceries", "text" => "eggs, milk, bread")),
    "Sum 1 to 10 in Julia"       => ("run_julia", Dict("code" => "total = sum(1:10)\ntotal * 2")),
    "List the files here"        => ("shell", Dict("cmd" => "ls -la")),
    "Clean up the build folder"  => ("shell", Dict("cmd" => "rm -rf build/")),
    "Back up Project.toml"       => ("copy_file", Dict("src" => "Project.toml", "dst" => "backup/Project.toml")),
]

message(text) = Dict("type" => "message", "role" => "assistant",
                     "content" => [Dict("type" => "output_text", "text" => text)])

# One Responses API reply: the scripted call for a prompt, then a summary of the tool's output.
function scripted_reply(body)
    input = body["input"]
    last = input[end]
    output = if get(last, "type", nothing) == "function_call_output"
        [message("The tool said: " * last["output"])]
    else
        i = findfirst(p -> p.first == get(last, "content", ""), SCRIPT)
        if i === nothing
            [message("I only know these prompts:\n\n" * join(("- " * p.first for p in SCRIPT), "\n"))]
        else
            name, args = SCRIPT[i].second
            [Dict("type" => "function_call", "call_id" => "call_$i", "name" => name,
                  "arguments" => JSON.json(args))]
        end
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
    HTTP.Response(200, ["Content-Type" => "text/event-stream"],
                  join(("data: $(JSON.json(e))\n\n" for e in events)))
end

scripted = OpenAICompatible("scripted", "http://127.0.0.1:$(HTTP.port(server))/v1")
s = Session(Model(scripted, "demo"); name = "tool-security-demo", tools = tools("demo"))

previous = tool_approval()
set_tool_approval!(MODE)
try
    for (prompt, _) in SCRIPT
        printstyled("\nYou: ", prompt, "   (tool_approval = ", repr(MODE), ")\n"; bold = true)
        agent!(s, prompt; stream = true)   # → label, preview lines, [y/N/a] prompts, ← results
    end
finally
    set_tool_approval!(previous == "auto" ? nothing : previous)
    restore_demo_approvals()              # forgets any `a` answers given above
end

# Misuse: unknown levels and preview arguments are rejected at registration.
for bad in (() -> register_tool!(shell; security = :critical),
            () -> register_tool!(shell; preview = :command))
    try
        bad()
    catch e
        println("ArgumentError: ", e.msg)
    end
end

# The same prompts in the `}` REPL mode show the finished turn boxed: a `Tool calls` box
# (✓/✗, label, View link) followed by a `Response (model; N in; M out):` box:
use_session!(s)
#   chat> Clean up the build folder
# close(server) when done.
