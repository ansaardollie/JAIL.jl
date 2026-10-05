# Built-in tools, one at a time: register a tool, then send a prompt that uses it.
# Runs live against the active session's model (the saved default model). Prompts that write
# work in `scratch/` (left behind). Medium/high calls ask [y/N/a] per `tool_approval`;
# `pkg_add` changes the active project, so decline it if you don't want Example added.

using JAIL

register_builtin_tools!(:create_directory)
chat!("Create a folder called scratch."; stream = true)

register_builtin_tools!(:create_file)
chat!("Create scratch/hello.jl containing a function `hello(name)` that returns \"Hello, name\"."; stream = true)

register_builtin_tools!(:read_file)
chat!("Read scratch/hello.jl and tell me what it does."; stream = true)

register_builtin_tools!(:list_dir)
chat!("What is in the src folder?"; stream = true)

register_builtin_tools!(:find_files)
chat!("Find every Julia file under src/builtin_tools."; stream = true)

register_builtin_tools!(:grep_files)
chat!("Which files mention `register_builtin_tools!`?"; stream = true)

register_builtin_tools!(:check_julia_syntax)
chat!("Check scratch/hello.jl for syntax errors."; stream = true)

register_builtin_tools!(:replace_in_file)
chat!("In scratch/hello.jl, make the greeting end with an exclamation mark."; stream = true)

register_builtin_tools!(:replace_in_files)
chat!("In one change, rename `hello` to `greet` in scratch/hello.jl and add a comment line at its top."; stream = true)

register_builtin_tools!(:git_changes)
chat!("Summarise my uncommitted git changes."; stream = true)

register_builtin_tools!(:julia_source_method)
chat!("Show me the source of the method `Base.sum(::Vector{Int})` dispatches to."; stream = true)

register_builtin_tools!(:julia_source_methods)
chat!("Show me every method of `JAIL.register_tool!`."; stream = true)

register_builtin_tools!(:julia_source_struct)
chat!("How is `JAIL.ToolSpec` defined?"; stream = true)

register_builtin_tools!(:julia_source_module)
chat!("Show me the source of the module `JAIL`."; stream = true)

register_builtin_tools!(:julia_docs)
chat!("What does the docstring of `Base.@kwdef` say?"; stream = true)

register_builtin_tools!(:find_julia_symbols)
chat!("Which loaded names contain \"session\"?"; stream = true)

register_builtin_tools!(:pkg_status)
chat!("Which packages does the active project use?"; stream = true)

register_builtin_tools!(:repl_history)
chat!("What were the last 5 things I typed in the REPL?"; stream = true)

register_builtin_tools!(:last_result)
chat!("What is the value of my last REPL result?"; stream = true)

register_builtin_tools!(:execute_julia_code)
chat!("Include scratch/hello.jl and call greet(\"JAIL\")."; stream = true)

register_builtin_tools!(:run_shell)
chat!("Run `ls -la scratch` in the shell."; stream = true)

register_builtin_tools!(:run_tests)
chat!("Run this project's tests and tell me the result."; stream = true)

register_builtin_tools!(:pkg_add)
chat!("Add the package Example to the active project."; stream = true)

register_builtin_tools!(:fetch_url)
chat!("Fetch https://julialang.org and summarise it in two sentences."; stream = true)

register_builtin_tools!(:ask_user)
chat!("Ask me which colour I prefer (red, green or blue), then tell me my answer."; stream = true)


chat!("Please ask me a question with multiple choice options as well as free text input"; stream = true)
chat!("Ask me to pick red, green or blue, and don't accept any other answer."; stream = true)
