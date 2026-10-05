# REPL modes

JAIL adds two modes to the Julia REPL. Both act on the [`active_session`](@ref):

| Key | Mode | Prompt |
|---|---|---|
| `\|` | Model: providers, models, sessions, tools | `(default: openai/gpt-5) model> ` |
| `}` | Chat: talk to the model, which may call tools | `chat> ` |

The model mode's prompt shows the active session and its model; the chat prompt is kept short
so it doesn't crowd the conversation (use `|` then `st` to check the model).

Press the key at an empty `julia>` prompt to enter a mode, and backspace on an empty line to
return to `julia>`.

## The chat mode

Each line is sent with [`chat!`](@ref) as the next turn of the active session, so the
conversation carries on across lines and stays in `session.messages`. The finished turn is
printed in a purple box, like the box of an `@info` message, holding a green
`Response (model; N in; M out):` box with the reply rendered as Markdown (the colors are the
Julia logo's, in 24-bit color); the
tokens are summed over every request of the turn. While waiting, a dim `thinking…` shows;
Ctrl-C cancels the request and leaves the history unchanged. A line is printed after the box
only when the reply didn't end normally:

```text
chat> How do I append to a vector?
┏ Chat: default
┃ ┏ Response (anthropic/claude-sonnet-4-5; 14 in; 30 out):
┃ ┃   Use push!:
┃ ┃
┃ ┃   v = [1, 2]
┃ ┃   push!(v, 3)
┃ ┗
┗
chat> Tell me a long story
┏ Chat: default
┃ ┏ Response (anthropic/claude-sonnet-4-5; 60 in; 10 out):
┃ ┃   Once upon
┃ ┗
┗
[stop reason: max_tokens]
```

When the model calls tools, a red `Tool calls` box comes before the response: one line per
call with ✓ or ✗ and the tool's label (see [Groups and labels](tools.md#Groups-and-labels)),
followed by `View`, a link to the call's saved JSON file (see
[Saving and restoring](sessions.md#Saving-and-restoring)) in terminals that support OSC 8
hyperlinks (iTerm2, kitty, WezTerm, VS Code, …). When Julia is not interactive (a script run
with `julia script.jl` calling `chat!(...; stream = true)`), a blue `Prompt:` box with the
prompt comes first. While the turn runs
without streaming, a transient line shows `thinking…` or the tool being run. If the tool round
limit is reached, the turn ends with `[stop reason: tool_use]`.

```text
chat> Should I pack an umbrella for Paris?
┏ Chat: default
┃ ┏ Tool calls (1):
┃ ┃   ✓ get_weather  View
┃ ┗
┃ ┏ Response (anthropic/claude-sonnet-4-5; 1840 in; 52 out):
┃ ┃   No, it will be sunny for the next three days.
┃ ┗
┗
```

These transcripts are illustrative; the reply text and token counts depend on the model.

A call that needs confirmation (see
[Security levels and approval](tools.md#Security-levels-and-approval)) stops the turn with a
prompt such as `get_weather(city = "Paris") [medium]: run it? [y/N/a = always]`; for a tool
with a `preview`, its label and the preview are shown instead of every argument. `y` runs the
call, anything else declines it (the model is told), and `a` runs it and auto-approves the tool
from then on.

### Streaming

With `stream = true` in the `[JAIL]` Preferences, a reply streams in as raw text on the
terminal's alternate screen (like `less`), under your prompt, with a `→ label` line per tool
call (followed by the tool's `preview`, indented, if it has one) and a `← label: result` line per
result as they happen. A confirmation prompt for a streamed call doesn't repeat the preview.
When it's complete the normal
screen comes back and only the finished turn (the boxes described above) is printed, so the
streamed text and tool lines never end
up in the REPL output or scrollback. If the request fails or you press Ctrl-C, the normal screen
comes back with just the error. Without the Preference, `thinking…` shows until the whole reply
is ready.

```toml
[JAIL]
stream = true
```

### Multi-line prompts

Enter sends the prompt. To start a new line instead:

| Keys | Works in |
|---|---|
| Ctrl+J | every terminal |
| Alt+Enter (Option+Enter) | terminals that send Alt as Meta (macOS: enable "Use Option as Meta key") |
| Shift+Enter, Ctrl+Enter, Cmd+Enter | terminals that report them: kitty, WezTerm, iTerm2 with CSI u, xterm with `modifyOtherKeys` |

Pasted multi-line text is inserted without being sent.

The VS Code terminal sends a plain Enter for Shift/Ctrl/Cmd+Enter, so no program in it can tell
them apart. Add these to your `keybindings.json` to make them send Alt+Enter, which the chat
mode and the `julia>` prompt treat as a new line. Put them at the **end** of the file: a later
entry wins, and `terminalFocus` keeps editor bindings (e.g. the Julia extension's Shift+Enter)
unchanged.

```json
{ "key": "shift+enter", "command": "workbench.action.terminal.sendSequence",
  "args": { "text": "\u001b\r" }, "when": "terminalFocus" },
{ "key": "ctrl+enter", "command": "workbench.action.terminal.sendSequence",
  "args": { "text": "\u001b\r" }, "when": "terminalFocus" },
{ "key": "cmd+enter", "command": "workbench.action.terminal.sendSequence",
  "args": { "text": "\u001b\r" }, "when": "terminalFocus" }
```

In other programs running in the terminal these keys then act as Alt+Enter.

Lines starting with `/` are commands (Tab completes them):

| Command | Does | Same as |
|---|---|---|
| `/clear` | Clear the active session's history | `empty!(active_session())` |
| `/help` | Show help | |

To switch model or session, use the model mode (`|`). With no model on the active session:

```text
chat> hi
ERROR: session "default" has no model; choose one in the `|` mode with `use provider/model` or `select`
```

## The model mode

Press `|` at an empty `julia>` prompt to enter the model mode. The prompt shows the
[`active_session`](@ref) and its model:

```text
(default: openai/gpt-5) model>
```

It shows `(default: no model) model> ` when the active session has no model yet.

Every command calls the same public functions you can use from code; the table lists them.

## Commands

In the model mode:

| Command | Does | Same as |
|---|---|---|
| `status`, `st` | Show the active session, its model and provider, and the saved default if it differs | |
| `providers` | List providers and whether their key ENV var is set | [`providers`](@ref) |
| `models [provider]` | List models (default: the active model's provider) | [`list_models`](@ref) |
| `select [provider]` | Choose the active session's model from menus | [`select_model!`](@ref) |
| `use provider/model` | Set the active session's model | [`set_model!`](@ref) |
| `use provider` | Set the active session's model to that provider's own default | [`use_provider!`](@ref) |
| `default [provider/model]` | Show or save the global default model for new sessions | [`set_default_model!`](@ref) |
| `default provider [model-id]` | Show or save that provider's own default model | [`set_default_model!`](@ref)`(p, id)` |
| `sessions` | List sessions with creation time, model, message count and id; `*` marks the active one | [`sessions`](@ref) |
| `session new [name] [provider/model]` | Start a session and make it active | [`new_session!`](@ref) |
| `session use <name\|id>` | Switch the active session (a menu picks among sessions sharing the name) | [`use_session!`](@ref) |
| `session restore` | Choose a saved session from a menu and make it active | [`restore_session!`](@ref) |
| `session rm <name\|id> [--files]` | Delete a session (not the active one); `--files` also deletes its saved files | [`delete_session!`](@ref) |
| `tools` | List registered tools by group; `*` marks those the active session uses | [`tools`](@ref) |
| `tools show <name>` | Show a tool's group, label, description and parameters | |
| `tools use <name>...` | Restrict the active session to these tools; `group:<group>` stands for every tool in that group | [`set_tools!`](@ref) |
| `tools add <name>...`, `tools drop <name>...` | Add tools to, or remove them from, the active session (`group:<group>` works here too) | [`set_tools!`](@ref) |
| `tools all`, `tools none` | Every registered tool (the default), or none | `set_tools!(nothing)`, `set_tools!([])` |
| `tools approve <name\|group:<group>>...`, `tools unapprove ...` | Run these tools' calls without asking, or remove that entry | [`set_tool_auto_approval!`](@ref) |
| `help`, `?` | Show the command list | |

`use` and `select` change only the active session. The saved default changes only with
`default provider/model`.

## Example

This transcript was produced against a local OpenAI-compatible server registered with
`register_provider!(OpenAICompatible("lmstudio", "http://127.0.0.1:1234/v1"))`:

```text
(default: openai/gpt-5) model> st
Session:  default
Model:    gpt-5
Provider: OpenAI("https://api.openai.com/v1", "OPENAI_API_KEY")
(default: openai/gpt-5) model> providers
  openai     https://api.openai.com/v1
  anthropic  https://api.anthropic.com
  google     https://generativelanguage.googleapis.com
  lmstudio   http://127.0.0.1:1234/v1
(default: openai/gpt-5) model> models lmstudio
4 models from lmstudio:
    gemma-3-4b
    gemma-3-12b
    llama-3.1-8b
    qwen3-8b
(default: openai/gpt-5) model> use lmstudio/qwen3-8b
Session "default" now uses lmstudio/qwen3-8b
(default: lmstudio/qwen3-8b) model> default
Default model: openai/gpt-5
(default: lmstudio/qwen3-8b) model> default anthropic/claude-sonnet-4-5
Default model saved: anthropic/claude-sonnet-4-5 (used by new sessions)
(default: lmstudio/qwen3-8b) model> session new work
Started session "work" using anthropic/claude-sonnet-4-5
(work: anthropic/claude-sonnet-4-5) model> sessions
    default  2026-10-04 03:28  lmstudio/qwen3-8b               0 messages  01a10486-e702-7def-96a1-0985255da8d0
  * work     2026-10-04 03:28  anthropic/claude-sonnet-4-5     0 messages  01a10486-f0f6-7d0c-a6b0-8c8edd8c43b4
(work: anthropic/claude-sonnet-4-5) model> session use default
Active session: default (lmstudio/qwen3-8b)
(default: lmstudio/qwen3-8b) model> session rm work
Deleted session "work"
```

With two tools registered (`@tool get_weather` and `@tool group=files list_directory`) on a
session called `demo`:

```text
(demo: anthropic/claude-sonnet-4-5) model> tools
Session "demo" uses every registered tool:
  files
  * list_directory  List the names of the files and folders in the current work…
  global
  * get_weather     Get the weather forecast for a city.
(demo: anthropic/claude-sonnet-4-5) model> tools use get_weather
Session "demo" tools: get_weather
(demo: anthropic/claude-sonnet-4-5) model> tools add group:files
Session "demo" tools: get_weather, list_directory
(demo: anthropic/claude-sonnet-4-5) model> tools drop list_directory
Session "demo" tools: get_weather
(demo: anthropic/claude-sonnet-4-5) model> tools
Session "demo" uses 1 of 2 tools:
  files
    list_directory  List the names of the files and folders in the current work…
  global
  * get_weather     Get the weather forecast for a city.
(demo: anthropic/claude-sonnet-4-5) model> tools show get_weather
ToolSpec get_weather(city::String, days::Int64 = …)
  group: global, label: "get_weather", security: medium
  Get the weather forecast for a city.
  • city::String: the city name, e.g. "Cape Town"
  • days::Int64 (optional): how many days to forecast
  approval: by security level and tool_approval
(demo: anthropic/claude-sonnet-4-5) model> tools approve get_weather
get_weather: auto-approved
(demo: anthropic/claude-sonnet-4-5) model> tools
Session "demo" uses 1 of 2 tools:
  files
    list_directory  List the names of the files and folders in the current work…
  global
  * get_weather     Get the weather forecast for a city.  [auto-approved]
(demo: anthropic/claude-sonnet-4-5) model> tools unapprove get_weather
get_weather: by security level and tool_approval
(demo: anthropic/claude-sonnet-4-5) model> tools all
Session "demo" tools: all (get_weather, list_directory)
```

Errors are printed without a stack trace:

```text
(default: lmstudio/qwen3-8b) model> select lmstudio/qwen3-8b
ERROR: `select` opens a menu; to set a model directly use `use lmstudio/qwen3-8b`
(default: lmstudio/qwen3-8b) model> session rm default
ERROR: can't delete the active session "default"; switch to another session first
(default: lmstudio/qwen3-8b) model> frobnicate
ERROR: unknown command `frobnicate`; type `help`
```

## Tab completion

Tab completes:

- command names, and `new`, `use`, `restore`, `rm` after `session`
- provider names after `models` and `select`
- `provider/` after `use`, `default` and `session new`, then model ids once that provider's
  models have been listed in this Julia process (by `models`, `select` or `select_model!`).
  Pressing Tab never fetches models.
- session names after `session use` and `session rm`
- `show`, `use`, `add`, `drop`, `all`, `none` after `tools`, then tool names

## Turning the modes off

The modes are installed when JAIL loads in an interactive REPL. To turn off all of JAIL's REPL
modes, set `repl_modes = false` in the `[JAIL]` table of the active project's
`LocalPreferences.toml`:

```toml
[JAIL]
repl_modes = false
```

This setting is read only when JAIL loads.
