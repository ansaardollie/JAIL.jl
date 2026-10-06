# Tools

A tool is an ordinary Julia function that a model may ask JAIL to call. Registering a function
reflects on it and stores a [`ToolSpec`](@ref) in JAIL's tool registry. Every session offers
the registered tools to its model in agent mode (in full when the session has loaded them,
otherwise through [tool search](#Tool-search)), and [`agent!`](@ref) (or the `&` REPL mode) runs
the calls the model makes. [`chat!`](@ref) and the `}` mode are text only and offer no tools;
agents and skills shape which tools a turn gets (see [Agents and skills](agents.md)). Tools
can be filed under groups and given a label for display (see [Groups and labels](#Groups-and-labels)).

## Defining a tool

Write a normal, documented function and register it with [`register_tool!`](@ref):

```@example tools
using JAIL

"""
    get_weather(city, days = 3)

Get the weather forecast for a city.

# Arguments
- `city`: the city name, e.g. "Cape Town"
- `days`: how many days to forecast
"""
get_weather(city::String, days::Int = 3) = "Sunny for $days days in $city"

register_tool!(get_weather)
```

What the model sees comes from the function:

| Part | Source |
|------|--------|
| name | the function name; `!` becomes `_bang` (`save!` → `save_bang`) |
| description | the docstring, without its signature line and `# Arguments` section |
| parameters | the positional arguments; ones with default values are optional |
| parameter descriptions | the entries of the docstring's `# Arguments` section |

Keyword arguments are not exposed (JAIL warns). Functions with several unrelated methods,
varargs, or anonymous functions can't be tools.

The description is read from the ordinary docstring *above* the function. A string placed
inside the function body is discarded by Julia when the function is compiled, so JAIL can't
see it.

## Argument types

Argument types become JSON Schema:

| Julia type | JSON Schema |
|------------|-------------|
| `Bool` | `boolean` |
| `Integer` | `integer` |
| `Real` | `number` |
| `AbstractString`, `Symbol` | `string` |
| `@enum` types | `string` with `enum` of the instance names |
| `AbstractVector{T}` | `array` of `T` |
| `AbstractDict{String,V}` | `object` with values of `V` |
| `Union{Nothing,T}` | `T` or `null` |
| concrete structs | `object` with one property per field |
| untyped (`Any`) | any JSON value |

Other types (e.g. `IO`, `Function`) throw an `ArgumentError` naming the argument.

## Several at once

[`@tool`](@ref) registers each named function:

```@example tools
"Add an item to the to-do list."
add_todo!(title::String, tags::Vector{String} = String[]) = "added $title"

"Return whatever value the model sends."
echo(value) = value

@tool add_todo! echo
```

`@tool load=true f` (or `register_tool!(f; load = true)`) also loads the tool in the active
session; see [Tool search](#Tool-search).

## Groups and labels

Every tool belongs to a group, `"global"` unless another is given, and has a label: the text
shown for its calls in the `&` REPL mode and in `agent!(...; stream = true)`. The label defaults
to the function name as written (`add_todo!`). Neither is sent to the model.

```@example tools
"List the names in a directory."
list_files(dir::String = ".") = readdir(dir)

register_tool!(list_files; group = "files", label = "List files")
```

With [`@tool`](@ref), `group=` applies to every function named, and `label=` to a single one:

```julia
@tool group=files list_files read_file
@tool group=files label="List files" list_files
```

`tools("files")` lists a group, so `set_tools!(s, tools("files"))` gives a session just those
tools (the ones in the group at that moment). Group names use letters, digits, `_`, `-` and `.`.

```@example tools
tools("files")
```

## The registry

Tools are keyed by name. Registering a name again replaces the earlier tool.
[`tools`](@ref) lists them and [`unregister_tool!`](@ref) removes one, by name or function.
The registry also holds the [built-in tools](#Built-in-tools), registered when JAIL loads, so
here they are filtered out:

```@example tools
mine() = filter(t -> !(t in builtin_tools()), tools())
mine()
```

```@example tools
unregister_tool!("echo")
unregister_tool!(add_todo!)
mine()
```

## Tools on a session

A session offers every registered tool, including ones registered after it was created.
[`tools(session)`](@ref tools(::Session)) lists them; [`set_tools!`](@ref) restricts the
session to a subset (by function or name), `[]` gives it none, and `nothing` goes back to all:

```@example tools
s = Session("anthropic/claude-sonnet-4-5"; name = "weather")
set_tools!(s, [get_weather])
```

```@example tools
set_tools!(s, nothing)
s
```

`Session(model; tools = [...])` and `new_session!(; tools = [...])` restrict from the start. In
the `|` REPL mode, `tools use`, `tools add`, `tools drop`, `tools all` and `tools none` do the
same for the active session, and `group:<group>` stands for a whole group (see
[REPL modes](repl.md)).

## Tool search

A session's tools are either **loaded** or just **registered**:

| Status | What the model gets |
|---|---|
| `:unregistered` | nothing |
| `:registered` | nothing up front: it finds the tool with tool search when a task needs it |
| `:loaded` | the full definition on every request |

So many tools can be registered without filling the model's context. Loaded tools belong to a
session: [`load_tools!`](@ref) and [`unload_tools!`](@ref) change them (by name, function or
group), [`tool_status`](@ref) reports a tool's status, and `Session(model; loaded_tools = [...])`
sets them from the start. New sessions load the tools named in the Preference `loaded_tools`
(default none), and `register_tool!(f; load = true)` (or `@tool load=true f`) also loads the
tool in the active session. Loaded tools are saved with the session.

```julia
s = Session("anthropic/claude-sonnet-4-5"; loaded_tools = ["read_file"])
load_tools!(s, get_weather, "memory")   # a function and a whole group
tool_status(s, "grep_files")             # :registered
unload_tools!(s, "memory")
```

How the model searches depends on the provider:

- **OpenAI** and **Anthropic** search natively: the registered tools are sent with
  `defer_loading`, together with the provider's search tool (OpenAI `tool_search`, Anthropic
  `tool_search_tool_bm25_20251119`). The search runs on the provider's side and shows up in the
  reply as [`ToolSearchPart`](@ref)s (and as `⌕` lines when streaming). It needs `gpt-5.4` or
  later, or Claude Opus/Sonnet/Haiku 4.5 or later; for older models set the Preference
  `providers.<name>.tool_search = "client"`.
- **Google**, **GoogleEnterprise** and **OpenAI-compatible** servers (and OpenAI/Anthropic with
  `tool_search = "client"`) get two tools of JAIL's instead, never registered and never
  confirmed: `tool_search(keywords)` lists the registered tools whose name or description
  matches any keyword (case-insensitive regular expressions; no keywords lists them all), and
  `tool_load(names)` loads tools in the calling session, so they are sent in full from the next
  request on.

Either way, a session whose tools are all loaded sends them as plain tools, without search. The
built-in system instructions tell the model that tool search is available and to check for a
relevant tool before starting a task. In the `|` REPL mode, `tools load <name>...` and
`tools unload <name>...` change the active session's loaded tools, and `tools` marks them `L`.

## The tool loop

When a reply contains [`ToolCall`](@ref)s (`stop_reason = :tool_use`), `agent!`:

1. runs each call in order, converting the JSON arguments to the parameter types (omitted
   optional arguments use the function's defaults), after asking on the terminal when the call
   needs confirmation (see [Security levels and approval](#Security-levels-and-approval));
2. appends a [`ToolResultMessage`](@ref) with one [`ToolResult`](@ref) per call, each with its
   own `id` (a version 7 UUID), and saves the call and result together as
   `<storage_dir>/tools/<session id>/<id>.json` (see
   [Saving and restoring](sessions.md#Saving-and-restoring));
3. sends the history again, and repeats until a reply calls no tools.

Every step stays in `session.messages` and the last reply is returned. Problems the model can
fix are sent back as error results instead of being thrown: an unknown tool, invalid
arguments, or an exception inside the tool (its message is included). If a request fails, the
whole turn is removed from the history.

A tool's return value becomes text for the model: strings as they are, plain data (numbers,
vectors, dictionaries, structs without a custom `show`) as JSON, anything else as its
`text/plain` display.

```julia
s = Session("anthropic/claude-sonnet-4-5"; tools = [get_weather])
reply = agent!(s, "Should I pack an umbrella for Paris?")
s.messages   # UserMessage, AssistantMessage (get_weather call), ToolResultMessage, AssistantMessage
agent!(s, "And Rome?"; stream = true)   # also prints → label and ← label: result lines
```

## Parallel tool calls

A model may call several tools in one reply ("What's the weather in Paris and Rome?"). With the
Preference `parallel_tool_calls` on (the default), JAIL:

1. confirms the calls that need it, one by one, in the order the model gave them;
2. runs the calls of tools registered with `concurrent = false`, one after another;
3. runs the other calls at the same time: on threads when Julia has more than one
   (`julia -t auto`), otherwise as tasks on one thread, which still overlaps waiting on the
   network, processes or `sleep`.

The results go back in the order of the calls. When streaming, a confirmed call or a call that
runs alone gets its own `→ label` line, the other calls that run together share one line, their
labels (and preview, shortened) separated by `|` (`→ weather (Paris) | weather (Rome)`), and no
`←` result lines are shown; the `Tool calls` box lists every result. Without streaming, the
status line shows the labels the same way (`→ weather | weather…`) while they run. A tool that
runs concurrently may run on another
thread at the same time as other tools, so it must be safe to do so. Register tools that read
the terminal, redirect `stdout`, or change shared state with `concurrent = false`
(`@tool concurrent=false f`). Of the built-in tools, `ask_user`, `execute_julia_code`,
`pkg_add`, `add_memory`, `remove_memory`, `tool_load` and the `edit` tools other than
`create_directory` run alone.

`parallel_tool_calls = false` asks OpenAI, OpenAI-compatible servers and Anthropic for at most
one tool call per reply (`parallel_tool_calls: false`; Anthropic
`tool_choice.disable_parallel_tool_use`), and runs calls one by one. Google has no such setting,
so Gemini may still call several tools; JAIL then runs them one by one. A
`providers.<name>.parallel_tool_calls` entry overrides the top-level one for that provider:

```toml
[JAIL]
parallel_tool_calls = true

[JAIL.providers.lmstudio]
parallel_tool_calls = false   # a local model that mixes up several calls
```

## Security levels and approval

Every tool has a security level: `:low`, `:medium` (the default) or `:high`. The Preference
`tool_approval` (default `"auto"`) decides which levels are confirmed on the terminal before
the call runs:

| Confirm first? | `"all"` | `"auto"` | `"none"` | `"yolo"` |
|---|---|---|---|---|
| `:low` | yes | no | no | no |
| `:medium` | yes | yes | no | no |
| `:high` | yes | yes | yes | no |

So by default every call of a tool registered without `security` is confirmed. A declined call
is reported to the model as an error result. Give tools that run code or shell commands, or that
change files, `security = :high`: then only an explicit choice (`tool_approval = "yolo"`, or an
auto-approval below) runs them without asking.

The level can also depend on the arguments: give a function that takes the same positional
arguments as the tool and returns a level. It always gets every parameter: an optional argument
the model left out is passed as `nothing` (the tool itself still gets its default). A function
that throws or returns anything else makes the call `:high`.

```julia
"Read a text file."
read_text(path::String) = read(path, String)
"Run a shell command and return its output."
run_shell(cmd::String) = read(`sh -c $cmd`, String)

# Low inside the working directory, high anywhere else.
register_tool!(read_text; security = path -> startswith(abspath(path), pwd() * "/") ? :low : :high)
register_tool!(run_shell; security = :high, preview = :cmd)
@tool security=low get_weather
```

## Previewing arguments

`preview` chooses what is shown for a call: in the confirmation prompt and under the streamed
`→ label` line.

| `preview` | Shown |
|---|---|
| `nothing` (default) | nothing on the streamed line; the prompt shows `name(arg = value, …)` |
| `:cmd` | the argument's text as it is (multi-line code or a command, no quotes) |
| `[:path, :mode]` | those arguments as `path = "…", mode = …` |
| a function | the text it returns; it gets the same arguments as a security function |

```text
run_shell [high]
    rm -rf build/
Run it? [y/N/a = always]
```

When the call was just streamed (its preview is already under `→ label`), the prompt is a
single line: `run_shell [high]: run it? [y/N/a = always]`. Answering `a` runs the call and
auto-approves the tool from then on (see below).

`@tool preview=cmd run_shell` takes an argument name, `preview=[path, mode]` several, and
`preview=(path, mode) -> path` a function. A bare name means an argument, so pass a named
function with `register_tool!(f; preview = g)`.

## Auto-approving tools

The Preference `tool_auto_approvals` overrides the rule above for chosen tools or groups,
whatever their security level and `tool_approval` (including `"all"` and `"yolo"`):

- `true`: the tool's calls run without asking;
- `false`: they are always confirmed;
- not listed: the security level and `tool_approval` decide.

Tools of the `"global"` group are keyed by name. Other tools sit under their group, which can
instead be a single `true`/`false` for all of its tools (TOML can't hold both for one group):

```toml
[JAIL.tool_auto_approvals]
get_weather = true          # a "global" tool
files = true                # every tool in the "files" group

[JAIL.tool_auto_approvals.shell]
run_shell = false           # always ask, even with tool_approval = "yolo"
```

[`set_tool_auto_approval!`](@ref) edits one entry (`nothing` removes it) and
[`tool_auto_approvals`](@ref) reads the table; answering `a` at a prompt saves `true` for that
tool. In the `|` REPL mode, `tools approve <name|group:<group>>...` and `tools unapprove ...` do
the same, and `tools` marks tools as `[auto-approved]` or `[always asks]`.

```julia
set_tool_auto_approval!(get_weather, true)
set_tool_auto_approval!("group:shell", false)
set_tool_auto_approval!(get_weather, nothing)
```

## Checking a call

These answer what the tool loop would do with a [`ToolCall`](@ref), converting its JSON
arguments the same way:

```julia
c = ToolCall("c1", "run_shell", Dict("cmd" => "rm -rf build/"))
security_level(c)                         # :high
needs_confirmation(c)                     # under tool_auto_approvals() and tool_approval()
needs_confirmation(c; approval = "yolo")  # false
tool_preview(c)                           # "rm -rf build/"
```

[`tool_approval`](@ref) returns the current mode and [`set_tool_approval!`](@ref) saves a new
one to the Preferences (`nothing` removes it).

## Built-in tools

JAIL ships tools for working in a Julia project: reading, searching and editing files, looking
up Julia source and documentation, running Julia code and shell commands, fetching web pages,
sending HTTP requests, asking the user and keeping per-session memories. [`builtin_tools`](@ref) lists them. All of them are registered when JAIL loads and none is loaded, so the
model finds them through [tool search](#Tool-search). The Preference `registered_tools` chooses
which are registered instead, by group or by name (`[]` for none):

```toml
[JAIL]
registered_tools = ["read", "inspect", "interact"]
```

and [`register_builtin_tools!`](@ref) registers more at any time:

```julia
register_builtin_tools!("read", "inspect")    # returns the ToolSpecs registered
register_builtin_tools!(:execute_julia_code)
unregister_tool!("execute_julia_code")        # as for any tool
```

They are grouped by what they do, so a whole group can be selected
(`set_tools!(s, tools("read"))`) or auto-approved (`tool_auto_approvals.read = true`). An
auto-approval skips the security level entirely, so approving `read` also lets the model read
files outside the workspace without asking.

| Group | Tool | What it does | Security level |
|---|---|---|---|
| `read` | `read_file(path, start_line, end_line)` | lines of a text file | low; high outside the workspace |
| | `list_dir(path)` | a folder's entries | low; high outside |
| | `find_files(pattern, max_results)` | paths matching a glob (`*.jl`, `src/**/*.jl`), skipping git-ignored files | low |
| | `grep_files(query, is_regex, include, max_results)` | `path:line: text` for matching lines | low |
| | `check_julia_syntax(path)` | syntax errors with line and column (JuliaSyntax) | low; high outside |
| | `git_changes(diff)` | `git status` and the staged and unstaged diffs | low |
| `inspect` | `julia_source_method(signature)` | source of the method a call runs, e.g. `"Base.sum(::Vector{Int})"` | low |
| | `julia_source_methods(name)` | source of every method of a function | low |
| | `julia_source_struct(name)` | source of a `struct` / `abstract type` / `primitive type` | low |
| | `julia_source_module(name)` | source of a `module … end` block; finds an installed package (or its submodule) even when it isn't loaded | low |
| | `julia_docs(name)` | a docstring as Markdown | low |
| | `find_julia_symbols(query, max_results)` | public names of loaded modules containing `query` | low |
| | `pkg_status()` | `Pkg.status()` of the active project | low |
| | `repl_history(n)` | the last REPL inputs | medium |
| | `last_result()` | the REPL's `ans` | medium |
| `edit` | `create_file(path, content)` | a new file (fails if it exists) | medium; high outside or protected |
| | `create_directory(path)` | a folder | low; high outside or protected |
| | `replace_in_file(path, old, new)` | replaces text that occurs exactly once | medium; high outside or protected |
| | `replace_in_files(edits)` | several replacements, all or none | the highest of its edits |
| | `edit_file(path, edits)` | line-number edits (`remove` lines, `add` text after a line, `replace` a regex within lines), all numbered as the file was before the call; all or none | medium; high outside or protected |
| | `remove_file(path)` | deletes a file (not a folder) | high; low if allow-listed |
| `execute` | `execute_julia_code(code)` | runs code; returns everything printed and the value | high |
| | `run_shell(command, timeout_seconds)` | runs a shell command; returns output and exit code | high; low if allow-listed |
| | `run_tests()` | `Pkg.test()` of the workspace project, in a new process | high |
| | `pkg_add(packages)` | `Pkg.add` into the active project | high |
| `web` | `fetch_url(url)` | a page's content as served (HTML as HTML) | medium for `https` to a public host; high otherwise |
| | `http_request(url, method, query_params, body, headers)` | sends any GET, HEAD, POST, PUT, PATCH, DELETE or OPTIONS request; returns status, headers and body | high; low if allow-listed |
| `interact` | `ask_user(question, options, allow_free_text)` | asks you in the terminal (a menu for `options`, with an "Other" choice for your own answer unless `allow_free_text = false`) and returns the answer | never asks for approval |
| `memory` | `read_memory()` | the session's memories, a numbered list | low |
| | `add_memory(input)` | adds a memory as the next number | low |
| | `remove_memory(number)` | removes the memory with that number | low |

The model sees each tool's docstring; read it with `@doc JAIL.read_file`. Calls are confirmed
following [Security levels and approval](#Security-levels-and-approval) like any tool, except
`ask_user`, which is never confirmed (it is a question to you already), whatever `tool_approval`
or `tool_auto_approvals` say. Answering `a` (always) works for high-level tools too.

### The workspace and protected paths

Paths are relative to the **workspace folder**, the current directory (`pwd()`). A call that
touches a path **outside** it is always `:high`: an absolute path not under the workspace, a
path whose first part is `..` (after tidying, so `src/../../x` counts), or a path through a
symbolic link inside the workspace. `find_files` and `grep_files` only search the workspace and
don't follow links.

**Protected** paths make *writes* `:high` even inside the workspace (reading them keeps the
normal level): `LocalPreferences.toml`, `Project.toml` and `.git` in the workspace folder,
JAIL's `storage_dir` (`.jail` by default), and the entries of the Preference `protected_paths`.
Entries are relative to the workspace folder: a bare name is a file or folder directly in it, a
folder protects everything inside, and anything deeper needs its path. Without this, a
`:medium` edit could, for example, set `tool_approval = "yolo"` in `LocalPreferences.toml`.

```toml
[JAIL]
protected_paths = ["secrets", "docs/Project.toml"]
```

### Allow-listed paths and commands

The Preference `path_allow_list` makes the `edit` tools (`create_file`, `create_directory`,
`replace_in_file`, `replace_in_files`, `edit_file`, `remove_file`) `:low` for the paths it
lists. Entries are files or folders (a folder covers everything inside), relative to the
workspace folder or absolute, so a folder outside the workspace can be allowed too. Protected
paths stay `:high` even inside an allowed folder. Paths are compared after resolving symbolic
links, so a link can't lead from an allowed folder to somewhere else.

```toml
[JAIL]
path_allow_list = ["scratch", "docs/src", "/tmp/jail-out"]
```

The Preference `command_allow_list` makes `run_shell` `:low` for commands that start with one of
its entries, followed by a space or the end of the command: `"git status"` allows
`git status` and `git status --short` but not `git statusx` or `git stash`. A command
containing a character that chains, substitutes or redirects commands (`;`, `&`, `|`, `` ` ``,
`$`, `<`, `>` or a line break; on Windows `&`, `|`, `<`, `>`, `^`, `%` or a line break) is always
`:high`. Anything after the prefix is allowed, so keep entries narrow: `"git"` would also allow
`git push` and `git -c` options that run other programs.

```toml
[JAIL]
command_allow_list = ["git status", "git diff", "ls"]
```

The source tools (`julia_source_*`) are always `:low`: they take names, not paths, and look
them up without running any code, even when the source lives outside the workspace (Base,
packages in `~/.julia`).

### Running Julia code

`execute_julia_code` is `:high`, so every call is confirmed first unless `tool_approval` is
`"yolo"` or the tool is auto-approved (answering `a` at its prompt saves that). It captures
everything the code prints (`stdout`, `stderr`, log messages and `display`ed values) and adds
`=> ` and the last value as the REPL shows it, long arrays shortened (leave it out by ending
the code with `;`). Relative paths in the code, such as `include("src/x.jl")`, are relative to
the workspace folder. If the code throws, the model gets an error result that still holds the
output, the error and the stack trace of its own code. Ctrl-C stops the code and, as for any
interrupted turn, removes the turn from the history.

The Preference `julia_code_module` chooses where the code runs:

- `"main"` (default): in `Main`, sharing your REPL's variables and definitions;
- `"sandbox"`: in a separate module per session, created on first use and not saved with the
  session. This keeps names apart only: the code can still do anything Julia can (files, shell,
  network, `ENV`), so the tool stays `:high`.

### Child processes and secrets

`run_shell`, `run_tests` and `git_changes` run in the workspace folder with no input (an
interactive command fails instead of waiting), and without the environment variables whose
names end in `_KEY`, `_CREDENTIALS` or `_CREDENTIAL` (ignoring case), nor those listed in the
Preference `scrub_env_vars`:

```toml
[JAIL]
scrub_env_vars = ["GITHUB_TOKEN", "DATABASE_URL"]
```

Code run by `execute_julia_code` is in your Julia process, so it can still read `ENV`.

### Web pages

`fetch_url` returns the content exactly as the server sent it: HTML as HTML, other text
formats as they are (binary content is refused). It is `:medium` for `https` to a public host on the default port and
`:high` for anything that could reach your machine or network: `http`, `localhost`, IP
addresses, other ports, and host names that resolve to private addresses. Redirects are
followed one by one and refused if they lead somewhere riskier than the URL that was approved.

### HTTP requests

`http_request` sends a request with any of GET, HEAD, POST, PUT, PATCH, DELETE or OPTIONS to an
`http` or `https` URL, with optional query parameters (escaped and added to the URL), body and
headers, and returns the status line, the response headers and the body (binary bodies are
described, not returned). It does not follow redirects, retry, or keep cookies; a 3xx response
is returned with its `Location` header. Its confirmation prompt shows the method, the full URL,
the headers and the body.

It can send data anywhere and reach your machine and network, so it is `:high` unless the URL
starts with an entry of the Preference `url_allow_list`, which makes it `:low`. An entry
matches only at a boundary: it ends in `/`, or the URL goes on with `/`, `?`, `#` or ends. So
`"https://api.example.com"` covers `https://api.example.com/v1?x=1` but not
`https://api.example.com.evil.org` or `https://api.example.com@evil.org`. URLs with user info
(`user@`), backslashes, or `.` or `..` path segments (also percent-encoded) are never
allow-listed. The comparison is on the URL text, case-sensitive.

```toml
[JAIL]
url_allow_list = ["https://api.github.com/repos/", "http://localhost:8080/api"]
```

### Memory

The `memory` tools keep notes for a session in a Markdown numbered list at
`<storage_dir>/memory/sessions/<session id>.md`. `read_memory()` returns the whole list,
`add_memory(input)` adds a line with the next number (line breaks in `input` become spaces),
and `remove_memory(number)` removes that line. Numbers are not reused or shifted: after
removing 2 from `1. 2. 3.`, the list is `1. 3.` and the next memory is 4.
`delete_session!(s; files = true)` deletes the memory file with the session's other files. The tools are `:low`: they only
touch the calling session's file (the session of the [`ToolContext`](@ref), or the active
session when called directly).

### Tool context

A tool can find out which session and call it is running for with [`tool_context`](@ref),
which returns a [`ToolContext`](@ref) during a call made by the tool loop and `nothing`
otherwise:

```julia
"Name of the session that called this tool."
session_name() = tool_context().session.name
register_tool!(session_name; security = :low)
```

## Preferences

- `max_tool_rounds` (default 50): tool rounds per `agent!` call. When it is reached, further
  calls are answered with "not run" error results and the last reply is returned with
  `stop_reason = :tool_use`. `agent!(...; max_tool_rounds = n)` overrides it for one call.
- `parallel_tool_calls` (default `true`), and `providers.<name>.parallel_tool_calls` to
  override it for one provider: whether the model may call several tools per reply and JAIL
  runs them at the same time; see [Parallel tool calls](#Parallel-tool-calls).
- `tool_approval` (default `"auto"`): `"all"`, `"auto"`, `"none"` or `"yolo"`; see
  [Security levels and approval](#Security-levels-and-approval). The older `confirm_tools`
  Preference is no longer read (JAIL warns once if it is set).
- `tool_auto_approvals` (default empty): per-tool and per-group `true`/`false` overrides; see
  [Auto-approving tools](#Auto-approving-tools).
- `registered_tools` (default: every built-in): built-in groups or tool names registered when
  JAIL loads (`[]` for none); see [Built-in tools](#Built-in-tools). The older `builtin_tools`
  is no longer read (JAIL warns if it is set).
- `loaded_tools` (default empty): tool or group names a new session loads; see
  [Tool search](#Tool-search).
- `providers.openai.tool_search`, `providers.anthropic.tool_search` (default `"hosted"`):
  `"client"` makes that provider use JAIL's `tool_search`/`tool_load`; see
  [Tool search](#Tool-search).
- `julia_code_module` (default `"main"`): where `execute_julia_code` runs, `"main"` or
  `"sandbox"`; see [Running Julia code](#Running-Julia-code).
- `protected_paths` (default empty): paths, relative to the workspace folder, whose writes are
  always `:high`, besides the built-in ones; see
  [The workspace and protected paths](#The-workspace-and-protected-paths).
- `path_allow_list` (default empty): files and folders whose writes by the `edit` tools are
  `:low`; see [Allow-listed paths and commands](#Allow-listed-paths-and-commands).
- `command_allow_list` (default empty): command prefixes for which `run_shell` is `:low`; see
  [Allow-listed paths and commands](#Allow-listed-paths-and-commands).
- `url_allow_list` (default empty): URL prefixes for which `http_request` is `:low`; see
  [HTTP requests](#HTTP-requests).
- `scrub_env_vars` (default empty): extra environment variable names removed from child
  processes; see [Child processes and secrets](#Child-processes-and-secrets).

```toml
[JAIL]
max_tool_rounds = 5
tool_approval = "none"
```
