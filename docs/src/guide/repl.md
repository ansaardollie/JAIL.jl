# REPL modes

JAIL adds two modes to the Julia REPL. Both act on the [`active_session`](@ref):

| Key | Mode | Prompt |
|---|---|---|
| `\|` | Model: providers, models, sessions | `(default: openai/gpt-5) model> ` |
| `}` | Chat: talk to the model | `chat> ` |

The model mode's prompt shows the active session and its model; the chat prompt is kept short
so it doesn't crowd the conversation (use `|` then `st` to check the model).

Press the key at an empty `julia>` prompt to enter a mode, and backspace on an empty line to
return to `julia>`.

## The chat mode

Each line is sent with [`chat!`](@ref) as the next turn of the active session, so the
conversation carries on across lines and stays in `session.messages`. The reply is rendered
as Markdown. While waiting, a dim `thinking…` shows; Ctrl-C cancels the request and leaves the
history unchanged. A line is printed after the reply only when it didn't end normally:

```text
chat> How do I append to a vector?
  Use push!:

  v = [1, 2]
  push!(v, 3)
chat> Tell me a long story
  Once upon
[stop reason: max_tokens]
```

### Streaming

With `stream = true` in the `[JAIL]` Preferences, a reply streams in as raw text on the
terminal's alternate screen (like `less`), under your prompt. When it's complete the normal
screen comes back and only the Markdown rendering is printed, so the streamed text never ends
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
| `default [provider/model]` | Show or save the default model for new sessions | [`set_default_model!`](@ref) |
| `sessions` | List sessions; `*` marks the active one | [`sessions`](@ref) |
| `session new [name] [provider/model]` | Start a session and make it active | [`new_session!`](@ref) |
| `session use <name>` | Switch the active session | [`use_session!`](@ref) |
| `session rm <name>` | Delete a session (not the active one) | [`delete_session!`](@ref) |
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
    default  lmstudio/qwen3-8b            0 messages
  * work     anthropic/claude-sonnet-4-5  0 messages
(work: anthropic/claude-sonnet-4-5) model> session use default
Active session: default (lmstudio/qwen3-8b)
(default: lmstudio/qwen3-8b) model> session rm work
Deleted session "work"
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

- command names, and `new`, `use`, `rm` after `session`
- provider names after `models` and `select`
- `provider/` after `use`, `default` and `session new`, then model ids once that provider's
  models have been listed in this Julia process (by `models`, `select` or `select_model!`).
  Pressing Tab never fetches models.
- session names after `session use` and `session rm`

## Turning the modes off

The modes are installed when JAIL loads in an interactive REPL. To turn off all of JAIL's REPL
modes, set `repl_modes = false` in the `[JAIL]` table of the active project's
`LocalPreferences.toml`:

```toml
[JAIL]
repl_modes = false
```

This setting is read only when JAIL loads.
