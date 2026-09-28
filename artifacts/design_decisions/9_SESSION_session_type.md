> **Superseded by:** `10_SESSION_registry_and_default_session.md` (REPL session, selection
> semantics, `repl_session`). The fields, `set_model!`, `empty!` and `Session()`-throws still hold.
> **Superseded in part by:** `18_TOOLS_session_tools_and_call_loop.md` (sessions gain a `tools` field).

# Decision: The `Session` type and how selection interacts with it

| Field | Value |
|-------|-------|
| Artifact | `9_SESSION_session_type.md` |
| Category | design_decisions |
| Subject | `SESSION` |
| Date | 2026-09-27 |
| Area/Purpose scope | core ontology, public API, REPL surface |
| Related | `5_API_provider_model_functions.md`, `7_MODEL_interactive_selection.md`, `8_REPL_model_mode.md` |
| Status | accepted |
| Decided by | user (all questions); agent (field mutability, REPL-session update rule details) |

## Context

Design principle 1: session context is allowed but must not become OldJAIL's `AIBrain` god
object. Many can exist; the REPL may use a default instance but it must not be the only way in.
Decisions 5 and 7 deferred this type; selection so far only set the persistent default.

## The Question

1. "Name of the session type?" — `Session` (chosen), `Conversation`, `Chat`.
2. "What goes into the session in this step?" — **A** model + system + abstract messages (chosen);
   B A + minimal concrete messages (rejected: locks message shape before tool calls / content
   parts are designed); C A + reserved tools field (rejected: YAGNI).
3. "Session() when no default model is set?" — allow `nothing` (agent recommendation, rejected);
   **throw** (chosen).
4. "What do the | mode and session-less select_model!() change now?" — A REPL session only +
   `default` command (rejected); **B** session-less calls update the REPL session *and* the default
   (chosen); C REPL session follows the default (rejected).
5. "Names for session functions?" — proposal (chosen).

## Decision

```julia
mutable struct Session
    model::AbstractModel
    system::Union{Nothing,String}
    const messages::Vector{AbstractMessage}   # abstract only; concrete types come later
end

Session()                                     # default_model(); throws if none is set
Session("anthropic/claude-sonnet-4-5"; system = "Be terse.")
Session(Model(Anthropic(), "claude-sonnet-4-5"))
set_model!(s, "openai/gpt-5")                 # returns the Model
select_model!(s); select_model!(s, Anthropic())   # menus, change only s
repl_session()                                # the REPL modes' session (created on first use)
empty!(s)                                     # clear history, keep model/system
```

- History is provider-agnostic, so a session may switch model across providers.
- Session-less `select_model!()` / `select_model!(p)` and the `|` mode's `use` / `select` call
  `set_default_model!` and, if the REPL session exists, `set_model!(repl_session(), m)`.
- `set_default_model!` stays Preferences-only (not a "selection" call).
- The `|` prompt shows the REPL session's model if it exists, else the default.
- `messages` is a `const` field: the vector can be mutated but not replaced.

## Consequences

Request/ask functions will take an explicit `Session`; the REPL modes pass `repl_session()`.
Provider server-side state (OpenAI `previous_response_id`, Google interaction ids) is not stored
yet; switching provider mid-session will need to drop it.

## Revisit Trigger

Concrete messages / tools landing (new fields), or a need for several named REPL sessions.
