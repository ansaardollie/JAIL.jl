# Decision: Session registry, default session, and REPL session commands

| Field | Value |
|-------|-------|
| Artifact | `10_SESSION_registry_and_default_session.md` |
| Category | design_decisions |
| Subject | `SESSION` |
| Date | 2026-09-27 |
| Area/Purpose scope | public API, REPL surface |
| Related | `9_SESSION_session_type.md` (superseded in part), `8_REPL_model_mode.md`, `7_MODEL_interactive_selection.md` |
| Status | accepted |
| Decided by | user; agent (auto-name base, name rules, registry holds strong refs, `use_session!` also accepts a Session) |

## Context

User, after seeing decision 9 implemented: "this is not what I want. The package should start a
default session and this should be used by the REPL. That default session should read from the
preferences to select the model to use for the default session. Also the repl mode should be able
to start a new session and also select the session to use."

## The Questions and Answers

| Question | Options | Chosen |
|---|---|---|
| How are sessions identified? | named (auto-name if omitted) / numbered | **named** |
| At load with no saved default model? | default session with no model / create later | **no model**; user: "A is fine but if model preferences are set in the Preferences then it should start with that model" |
| What do `use`/`select` change? | active session only + `default` command / active + saved default | **active session only**, separate `default` command |
| New session's model? | saved default unless given / copy active | **saved default unless given** |
| Commands/functions | proposal / rename | **proposal** |
| Sessions made in code visible to REPL? | only `new_session!` ones / every `Session` | **every `Session` is registered** |
| Imperative `session rm` | `remove_session!` / `delete_session!` / `close!` | **`delete_session!`** |
| Duplicate names | error / replace / auto-suffix | **auto-suffix** (`refactor-2`) |

## Decision

```julia
Session(model; name = nothing, system = nothing)   # registered; name auto-suffixed if taken
Session(; name, system)                            # saved default model; throws if none
sessions()                                         # Vector{Session}, creation order
new_session!(name = nothing; model = nothing, system = nothing)   # create + activate
use_session!(name_or_session)                      # activate
active_session()                                   # replaces repl_session()
delete_session!(name_or_session)                   # unregister; refuses the active one
select_model!()  / select_model!(p)                # menus → active session only
set_default_model!(m)                              # saved default for new sessions
```

`|` mode:

```
(default: anthropic/claude-sonnet-4-5) model> sessions
(default: anthropic/claude-sonnet-4-5) model> session new [name] [provider/model]
(default: anthropic/claude-sonnet-4-5) model> session use <name>
(default: anthropic/claude-sonnet-4-5) model> session rm <name>
(default: anthropic/claude-sonnet-4-5) model> use provider/model     # active session only
(default: anthropic/claude-sonnet-4-5) model> default [provider/model]   # show / save default
```

- On load (`__init__`), JAIL creates session `"default"` from the saved default model, or with
  `model = nothing` if none is saved (or it no longer resolves). It becomes the active session.
- Only that startup session may have no model; `Session()` / `new_session!()` still require one.
- Agent-decided: unnamed sessions are `"session"`, then `"session-2"`, ...; names follow the
  provider-name rule `^[A-Za-z0-9._-]+$` so they parse as single REPL words; the registry holds
  strong references, so sessions live until `delete_session!`.

## Consequences

- `repl_session()` and the "session-less selection also saves the default" rule from decision 9
  are gone.
- Scripts that create many sessions accumulate them until deleted.

## Revisit Trigger

Registry growth becoming a problem in scripts (consider weak references for code-created
sessions), or a need to persist sessions across restarts.
