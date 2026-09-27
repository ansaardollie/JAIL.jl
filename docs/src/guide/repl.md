# The model REPL mode

Press `|` at an empty `julia>` prompt to enter the model mode. Press backspace on an empty
line to return to `julia>`. The prompt shows the [`active_session`](@ref) and its model:

```text
(default: openai/gpt-5) model>
```

It shows `(default: no model) model> ` when the active session has no model yet.

Every command calls the same public functions you can use from code; the table lists them.

## Commands

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

The mode is installed when JAIL loads in an interactive REPL. To turn off all of JAIL's REPL
modes, set `repl_modes = false` in the `[JAIL]` table of the active project's
`LocalPreferences.toml`:

```toml
[JAIL]
repl_modes = false
```

This setting is read only when JAIL loads.
