# Built-in tools: file, Julia, shell, web and interaction tools that ship with JAIL
#
# What: 27 ready-made tools in six groups, by what they do:
#   read      read_file, list_dir, find_files, grep_files, check_julia_syntax, git_changes
#   inspect   julia_source_method(s), julia_source_struct, julia_source_module, julia_docs,
#             find_julia_symbols, pkg_status, repl_history, last_result
#   edit      create_file, create_directory, replace_in_file, replace_in_files, edit_file, remove_file
#   execute   execute_julia_code, run_shell, run_tests, pkg_add
#   web       fetch_url
#   interact  ask_user
# None is registered when JAIL loads: opt in with register_builtin_tools!(groups or names...) or
# the Preference `builtin_tools`. (The future `&` agentic mode will attach them itself.)
#
# Security: paths are relative to the workspace folder (pwd()). Anything outside it (absolute
# paths elsewhere, `..` first, symlinks) is :high; writes to protected paths (LocalPreferences.toml,
# Project.toml, .git, storage_dir, Preference `protected_paths`) are :high. Source tools are
# always :low; ask_user never asks for approval. Child processes lose ENV vars ending in _KEY,
# _CREDENTIALS, _CREDENTIAL (plus Preference `scrub_env_vars`).
#
# Providers: all (tools run in JAIL). Section 4 runs offline against a scripted stand-in model:
# a tiny local server speaking the OpenAI Responses format, used through `OpenAICompatible`. It
# answers exactly the prompts in SCRIPT, each with one fixed tool call.
#
# Running it: section 4 asks [y/N/a] for :medium/:high calls under MODE and `ask_user` asks a
# question, so run it in a terminal REPL. It works in a temporary folder inside the current
# directory and removes it, the demo session and the tools it registered at the end.
#
# Open / tentative:
# - The built-in tool functions are not exported; `JAIL.read_file` etc. are callable directly,
#   but the intended use is through a session.
# - `execute_julia_code` runs in Main unless the Preference julia_code_module = "sandbox".

using JAIL
using HTTP: HTTP
using JSON: JSON

MODE = "auto"     # tool_approval for section 4: "all", "auto", "none" or "yolo"

# --- 1. What ships ------------------------------------------------------------------------

for t in sort(builtin_tools(), by=(t -> (t.group, t.name)))
    println(rpad(t.group, 9), rpad(t.name, 22), t.security isa Symbol ? t.security : "by arguments")
end
println("\nregistered before opting in: ", [t.name for t in tools() if t in builtin_tools()])

# --- 2. Opting in -------------------------------------------------------------------------

registered = register_builtin_tools!("read", "inspect", "interact", :execute_julia_code, :create_file,
                                     :replace_in_file, :fetch_url)
println("registered: ", join((t.name for t in registered), ", "))
show(stdout, MIME"text/plain"(), only(filter(t -> t.name == "replace_in_file", tools())))
println("\n")

# --- 3. Security levels: what the tool loop would do with a call -------------------------

calls = [ToolCall("1", "read_file", Dict("path" => "Project.toml")),
         ToolCall("2", "read_file", Dict("path" => "/etc/hosts")),
         ToolCall("3", "read_file", Dict("path" => "../secrets.txt")),
         ToolCall("4", "create_file", Dict("path" => "notes/todo.md", "content" => "- write docs")),
         ToolCall("5", "replace_in_file", Dict("path" => "Project.toml", "old" => "version = \"0.2.0\"", "new" => "version = \"9.9.9\"")),
         ToolCall("6", "julia_source_struct", Dict("name" => "Base.Dict")),
         ToolCall("7", "execute_julia_code", Dict("code" => "sum(1:10)")),
         ToolCall("8", "fetch_url", Dict("url" => "http://localhost:8080/admin")),
         ToolCall("9", "ask_user", Dict("question" => "Which colour?"))]

modes = ("all", "auto", "none", "yolo")
println(rpad("call", 70), rpad("level", 8), join((rpad(m, 6) for m in modes)))
for c in calls
    asks = (needs_confirmation(c; approval = m) ? "ask" : "-" for m in modes)
    println(rpad(first(sprint(show, c), 68), 70), rpad(security_level(c), 8), join((rpad(a, 6) for a in asks)))
end
println("\npreview of call 5:\n", tool_preview(calls[5]))

# --- 4. Watch a (scripted) model use them -------------------------------------------------

demo = relpath(mktempdir(pwd(); prefix = "builtin_tools_demo_"), pwd())
write(joinpath(demo, "greet.jl"), "greet(name) = \"Hello, \$name\"\n")

"Return the name of the session that called this tool."
calling_session() = tool_context().session.name
register_tool!(calling_session; security = :low)

const SCRIPT = [
    "Which Julia files are in the demo folder?" => ("find_files", Dict("pattern" => "$demo/*.jl")),
    "Show me greet.jl"                         => ("read_file", Dict("path" => "$demo/greet.jl")),
    "Make greet more excited"                  => ("replace_in_file", Dict("path" => "$demo/greet.jl", "old" => "Hello, \$name\"", "new" => "Hello, \$(name)!\"")),
    "Add a README to the demo folder"          => ("create_file", Dict("path" => "$demo/README.md", "content" => "# Demo\n\nSays hello.\n")),
    "Try greet"                                => ("execute_julia_code", Dict("code" => "include(\"$demo/greet.jl\")\nprintln(greet(\"JAIL\"))\nlength(greet(\"JAIL\"))")),
    "How is ToolSpec defined?"                 => ("julia_source_struct", Dict("name" => "JAIL.ToolSpec")),
    "What does register_builtin_tools! do?"    => ("julia_docs", Dict("name" => "register_builtin_tools!")),
    "Any syntax errors in greet.jl?"           => ("check_julia_syntax", Dict("path" => "$demo/greet.jl")),
    "Ask me for a colour"                      => ("ask_user", Dict("question" => "Which colour should the logo be?", "options" => ["red", "green", "blue"])),
    "Which session is this?"                   => ("calling_session", Dict()),
    "Fetch the local admin page"               => ("fetch_url", Dict("url" => "http://127.0.0.1:1/admin")),
]

message(text) = Dict("type" => "message", "role" => "assistant",
                     "content" => [Dict("type" => "output_text", "text" => text)])

function scripted_reply(body)
    last = body["input"][end]
    output = if get(last, "type", nothing) == "function_call_output"
        [message("The tool said:\n" * first(last["output"], 600))]
    else
        i = findfirst(p -> p.first == get(last, "content", ""), SCRIPT)
        i === nothing ? [message("I only know these prompts:\n" * join(("- " * p.first for p in SCRIPT), "\n"))] :
            [Dict("type" => "function_call", "call_id" => "call_$i", "name" => SCRIPT[i].second[1],
                  "arguments" => JSON.json(SCRIPT[i].second[2]))]
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
s = Session(Model(scripted, "demo"); name = "builtin-tools-demo")

previous = tool_approval()
set_tool_approval!(MODE)
try
    for (prompt, _) in SCRIPT
        printstyled("\nYou: ", prompt, "\n"; bold = true)
        chat!(s, prompt; stream = true)   # → label, preview, [y/N/a] prompts, ← result, reply text
    end
finally
    set_tool_approval!(previous == "auto" ? nothing : previous)
    close(server)
end

# --- 5. Misuse ----------------------------------------------------------------------------

for bad in (() -> register_builtin_tools!(), () -> register_builtin_tools!("files"))
    try
        bad()
    catch e
        println("ArgumentError: ", e.msg)
    end
end

# --- Clean up -----------------------------------------------------------------------------

foreach(t -> unregister_tool!(t.name), registered)
unregister_tool!(calling_session)
delete_session!(s; files = true)
rm(demo; recursive = true)
