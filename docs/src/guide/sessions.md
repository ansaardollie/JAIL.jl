# Sessions

A [`Session`](@ref) holds one conversation: a `name`, the active `model`, optional `system`
instructions, the `tools` its model may call, and the typed message history in `messages`.
It can also set a `thinking_effort` and `temperature` for its requests (see
[Thinking effort and temperature](#Thinking-effort-and-temperature)).
[`chat!`](@ref) sends turns on a session (see [Chat](chat.md)). A new session offers every
registered tool; see [Tools on a session](tools.md#Tools-on-a-session) to restrict it. Its
`loaded_tools` are the ones the model sees in full; the rest it finds through
[tool search](tools.md#Tool-search).

## The default session

When JAIL loads it starts a session called `"default"` and makes it the **active session**.
Its model is the saved default model. If none is saved (or the saved one can't be used), it
starts with no model.

These docs are built with no default model saved when JAIL loads, so:

```@example sessions
using JAIL

active_session()
```

Saving a default doesn't change sessions that already exist; it applies to new sessions, and
to `"default"` the next time JAIL loads:

```@example sessions
set_default_model!("openai/gpt-5")
active_session()
```

## Creating sessions

```@example sessions
s = Session("anthropic/claude-sonnet-4-5"; name = "review", system = "Be terse.")
```

The detailed display (also the `|` mode's `status`). `loaded` lists the session's loaded tools
and how the model finds the others. `thinking` and `temperature` show what
the session's requests will send: its own value, the Preference marked `(Preference)`, or
`model default` when neither is set. `reasoning` reflects the Preference `show_reasoning`:

```@example sessions
show(stdout, MIME"text/plain"(), s)
```

Without a model, the saved default is used. It's an error if none is saved.

```@example sessions
Session()
```

Every session is **registered**, so the REPL can list it and switch to it.
- A session without a name is called `"session"`.
- Names need not be unique; each session's `id` tells it apart.
- Names may contain letters, digits, `.`, `_` and `-`, and can't be a UUID.

```@example sessions
r2 = Session("anthropic/claude-sonnet-4-5"; name = "review")
```

```@example sessions
sessions()
```

Functions that take a session ([`use_session!`](@ref), [`delete_session!`](@ref)) accept the
`Session`, its `id` (a `UUID` or its string), or its name. When several sessions share the
name, a terminal menu lists them (name, creation time, model, message count, id) to choose
one; cancelling returns `nothing`.

Sessions stay registered, and in memory, until [`delete_session!`](@ref).

## Changing a session's model

[`set_model!`](@ref) switches the model and keeps the history. Other sessions and the saved
default are unaffected:

```@example sessions
set_model!(s, "google/gemini-3.8-flash")
s
```

```@example sessions
default_model()
```

`empty!(s)` clears the history and keeps the model and system instructions. To pick a model
from menus, use `select_model!(s)` (see [Models](models.md)).

## Thinking effort and temperature

A session's `thinking_effort` and `temperature` apply to every [`chat!`](@ref) on it, unless a
call passes its own; `nothing` (the default) leaves them to the Preferences of the same name.
Set them when creating the session or with [`set_thinking_effort!`](@ref) and
[`set_temperature!`](@ref). They are saved with the session. How each provider takes them is
in [Chat](chat.md#Thinking-effort,-temperature-and-reasoning).

```@example sessions
set_thinking_effort!(s, :low)
set_temperature!(s, 0.2)
show(stdout, MIME"text/plain"(), s)
```

```@example sessions
set_thinking_effort!(s, nothing)
set_temperature!(s, nothing)
s.thinking_effort, s.temperature
```

Values are checked when set: the effort must be a `Symbol` (or a string), the temperature a
non-negative number. Levels are not checked against the model.

```@example sessions
try
    set_temperature!(s, -1)
catch e
    showerror(stdout, e)
end
```

## System instructions

A session created without `system` (including `"default"` and REPL `session new`) gets JAIL's
built-in instructions: it is running in a Julia REPL, should be concise, should put code
in fenced ```` ``` ```` blocks, and has tool search, so it should check for a relevant tool
before starting a task. They end with a line describing the environment when the
session was created: Julia version, OS, active project, and the packages in that project's
`[deps]` (the packages available to `using`, whether loaded or not).

```@example sessions
print(Session("openai/gpt-5"; name = "sys").system)
```

- `system = "..."` replaces them for one session; `system = ""` gives the session none.
- The Preference `system_prompt` replaces the instructions for new sessions (the environment
  line is still added); `system_prompt = ""` turns them off.
- The environment line is not updated later, so packages added to the project (or a project
  switch) after the session was created aren't reflected.

## The active session

The REPL modes and session-less calls act on the [`active_session`](@ref). Every function
that changes or uses a session also works without one: `set_model!(model)`,
`select_model!()`, `set_tools!(tools)`, `load_tools!(tools...)`, `unload_tools!(tools...)`,
`tool_status(tool)`, `set_thinking_effort!(level)`, `set_temperature!(t)`, `use_agent!(name)`,
`chat!(prompt)` and `agent!(prompt)`. The exception is
[`tools`](@ref): `tools()` lists the tool registry, so use `tools(active_session())` for the
active session's tools.

```@example sessions
w = new_session!("work"; model = "anthropic/claude-sonnet-4-5")   # create and activate
active_session() === w
```

```@example sessions
set_model!("openai/gpt-5")   # the active session, "work"
w
```

```@example sessions
use_session!(s)               # the Session, its id, or a name (menu if shared)
active_session().name
```

```@example sessions
use_session!("default");
delete_session!(r2.id)
[x.name for x in sessions()]
```

## Saving and restoring

Every session has an `id` (a version 7 UUID, so ids sort by creation time) and a `created`
time in UTC; both are shown in the detailed display above. From its first message on, a
session is saved under the Preference `storage_dir` (default `.jail`; a relative path is
resolved against the working directory when the session is first saved):

- `sessions/<id>.json`: name, id, creation time, model (as `"provider/model-id"`), system
  instructions, tools (`null` for every registered tool), the names of the tools the session
  could use when last saved (`available_tools`), its loaded tools (`loaded_tools`), thinking
  effort, temperature, and its agent (`agent`, the name, and `agent_path`, the agent file chosen
  when it was applied; see [Agents and skills](agents.md)).
- `messages/<id>.jsonl`: one message per line. Each new message is appended, so saving adds
  almost nothing to a chat turn. Tool calls are stored with their arguments as a JSON object;
  a tool result whose text is JSON is stored as that JSON value, other results as text.
  [`ReasoningPart`](@ref)s and [`ToolSearchPart`](@ref)s are stored with their provider data,
  so a restored session can still send them back.
- `tools/<id>/<pair id>.json`: one file per tool call and its result, named by the
  [`ToolResult`](@ref)'s `id` (a version 7 UUID, also stored with the result in the messages
  file). It holds the session id, model, start and finish times, the tool (name, label, group),
  the call (provider call id, name, arguments) and the result (content, `is_error`), plus
  `generated`, the path of the file below (or `null`).
- `generated/<type>/<id>/<pair id>/generated.<ext>`: the text a call carried, as a file of its
  own so it reads as code rather than a JSON string: `code` for `execute_julia_code` (`.jl`),
  `shell` for `run_shell` (`.sh`), `file` for `create_file` (the created file's extension, else
  `.txt`).
- `reasoning/<id>/<trace id>.md`: with `show_reasoning` on, one Markdown file per reasoning
  summary: YAML front matter (`version`, `id`, `session_id`, `reply_id`, `model`, `format`,
  `created`), then the summary as the model wrote it.
  The `}` mode links to them (see [Chat](chat.md#Thinking-effort,-temperature-and-reasoning)).
- `memory/sessions/<id>.md`: the session's memory list, written by the memory tools (see
  [Memory](tools.md#Memory)). Agent memory is under `memory/agents/` and is not removed with the
  session.

A session with no messages is not saved, and a turn that fails is removed from the file too.
[`set_model!`](@ref), [`set_tools!`](@ref), [`load_tools!`](@ref), [`unload_tools!`](@ref),
[`set_thinking_effort!`](@ref), [`set_temperature!`](@ref), [`use_agent!`](@ref) and `empty!` update the files. Set the Preference
`persist_sessions = false` to stop saving.

[`restore_session!`](@ref) brings a saved session back, in this or a later Julia process, and
makes it active. Without an id it opens a menu of saved sessions, newest first, showing each
one's name, creation time and first prompt (the `|` mode's `session restore` opens the same
menu):

```julia
restore_session!()       # menu
restore_session!(id)     # a UUID, or its string form
```

- The model is looked up by name in the current Preferences. If it can't be (for example the
  provider was removed), the session comes back without a model and a warning is shown; pick
  one with [`set_model!`](@ref).
- Built-in tools the session could use (or chose with [`set_tools!`](@ref)) are registered
  again if they aren't (for example when the Preference `registered_tools` leaves them out; see
  [`register_builtin_tools!`](@ref)). Your own tools can't be
  restored from disk: a warning names those that are not registered, so you can
  [`register_tool!`](@ref) them again.
- Restoring a session that is already loaded just makes it active.
- After a restore in a new Julia process, the first turn sends the full history (see
  [What gets sent](chat.md#What-gets-sent)).
- Messages edited in place in `s.messages` (rather than added or removed) are not re-saved.

[`delete_session!`](@ref) keeps the files, so a deleted session can be restored;
`delete_session!(s; files = true)` removes them as well: the tool call and generated files, and the
session memory file. Agent memory is kept.

## Common errors

```@example sessions
try
    delete_session!(active_session())
catch e
    showerror(stdout, e)
end
```

```@example sessions
try
    use_session!("nope")
catch e
    showerror(stdout, e)
end
```

```@example sessions
try
    Session("openai/gpt-5"; name = "my work")
catch e
    showerror(stdout, e)
end
```

```@example sessions
try
    s.messages = AbstractMessage[]    # history can be emptied, not replaced
catch e
    showerror(stdout, e)
end
```
