# Decision: Tool security levels, `tool_approval`, and argument previews

| Field | Value |
|-------|-------|
| Artifact | `29_TOOLS_security_approval_preview.md` |
| Category | design_decisions |
| Subject | `TOOLS` |
| Date | 2026-10-05 |
| Area/Purpose scope | public API, Preferences, REPL surface |
| Related | `18_TOOLS_session_tools_and_call_loop.md` (supersedes its `confirm_tools` row), `28_TOOLS_groups_and_labels.md`, `27_TOOLS_call_records_and_display.md` |
| Status | accepted |
| Decided by | user (levels, modes, matrix, defaults, Q&A below); agent (details listed) |

## Context

User: "implement tool security levels ... how auto approval should work ... 3 different levels:
low, medium, high. each tool should be allowed to defined with either a static level or defined
with a level function that takes as input the given arguments ... the confirmation preference can
be `all`, `auto`, `none` and `yolo`" with the matrix below, "default security level should be
medium and the default confirmation preference should be auto". Also: "an option of which
arguments should be displayed and how ... for execute code/shell commands to be able to just
display the code/command it's going to run".

| confirm first? | all | auto | none | yolo |
|---|---|---|---|---|
| low | yes | no | no | no |
| medium | yes | yes | no | no |
| high | yes | yes | yes | no |

## Questions and Answers

| Question | Options | Chosen |
|---|---|---|
| Preference | same key `confirm_tools` mapping booleans; same key strings only; new key | **new key `tool_approval`**; `confirm_tools` ignored with a one-time warning |
| Level keyword | `security`; `risk`; `level` | **`security`** |
| Level function input | Dict of the model's arguments; same positional args as `f` | **same args as `f`** |
| Preview forms | one arg raw; subset `name = value`; custom function | **all three** |
| Preview keyword | `display`; `show_args`; `preview` | **`preview`** |
| Preview function input | same args as `f`; Dict | **same args as `f`** |
| Where previews show | prompt + stream + block; prompt + stream; prompt only | **prompt + streamed `→ label` line** (block stays `✓ label  View`) |
| Override scope | Preference only; plus `chat!` kwarg and `/confirm` | **Preference only** |

## Decision

```julia
register_tool!(f; group, label, security = :medium, preview = nothing)
#   security :: :low | :medium | :high | Function(args...) -> level
#   preview  :: nothing | :arg | [:a, :b] | Function(args...) -> text
@tool security=high preview=code label="Julia code" run_julia
@tool security=shell_level preview=[path, mode] f     # non-level name/expression = function
```

```toml
[JAIL]
tool_approval = "auto"   # "all" | "auto" | "none" | "yolo"
```

Agent-decided:

- `ToolSpec` gains `security::Union{Symbol,Function}`, `preview::Union{Nothing,String,Vector{String},Function}`;
  preview names are validated against the parameters at registration.
- A level function that throws or returns anything but `:low/:medium/:high` (strings included)
  makes the call `:high` with a `@warn`. Functions receive the converted arguments; omitted
  trailing optionals are absent, so they must mirror the tool's defaults.
- The level is computed after argument conversion; unknown tools and invalid arguments still
  become error results without a prompt.
- Prompt: `label [level]`, the preview indented 4 spaces, `Run it? [y/N]`; without a preview,
  `name(args…) [level]: run it? [y/N]`.
- Previews: a single argument shows a string as-is (others `repr`); a vector shows
  `name = repr(value)`; a throwing preview function shows nothing (warned).
- `_run_tool` takes `approval` and a `before_confirm` hook; the loop passes `_Confirming(call)` to
  `on_step` so the `}` mode clears its transient status line before the prompt.
- In `@tool`, `security=low|medium|high` are literals even when those names are bound in the
  caller (e.g. an `@enum`); any other value is evaluated as the security function. `preview=`
  bare names are arguments; a named function needs `register_tool!`.

## Rejected

- Keeping `confirm_tools` (booleans don't map cleanly onto four modes); per-call / REPL
  overrides (not needed yet); Dict-of-arguments functions (user wanted symmetry with `f`);
  previews in the Tool calls block (the `View` file holds the arguments).

## Consequences

- Default is `"auto"` + `:medium`: every call of an unannotated tool is now confirmed. Owners with
  `confirm_tools = false` get a warning and must set `tool_approval = "yolo"` to keep the old
  behaviour.
- Streaming with a confirmed preview shows the preview twice (stream line and prompt).

## Revisit Trigger

Requests for per-session/per-call approval, group-level defaults (e.g. all of `shell` high),
recording the level/approval in tool record files, or non-terminal approval (e.g. a callback).

## Amendment (2026-10-05, user follow-up)

User: "let's fix the preview showing twice. Also add the public helpers ... if the tool call
doesn't provide an argument then security/preview invocation should be done with a nothing value
placed in those args."

| Question | Options | Chosen |
|---|---|---|
| Helpers | `tool_approval()`, `set_tool_approval!(mode)`, `security_level(call)`, `needs_confirmation(call; approval)`, `tool_preview(call)` | **all five** |
| Helper input | `ToolCall` only; also `(spec, args...)` | **`ToolCall` only** (converted like the loop; unknown tool / bad args throw `ArgumentError`) |

- Security and preview functions now always get every parameter; omitted optionals are
  `nothing` (supersedes "omitted trailing optionals are absent"). The tool itself still gets its
  Julia defaults. One-argument and vector previews still skip omitted arguments.
- `set_tool_approval!(nothing)` deletes the Preference; Symbols are accepted.
- Preview shown once: `on_step(_Confirming)` returns `true` when the preview is already on screen
  (streaming in `chat!` and `}`), and the prompt becomes `label [level]: run it? [y/N]`.
