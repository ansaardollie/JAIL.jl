# Decision: Tool groups and display labels

| Field | Value |
|-------|-------|
| Artifact | `28_TOOLS_groups_and_labels.md` |
| Category | design_decisions |
| Subject | `TOOLS` |
| Date | 2026-10-05 |
| Area/Purpose scope | core ontology, public API, REPL surface |
| Related | `17_TOOLS_definitions_and_registry.md`, `18_TOOLS_session_tools_and_call_loop.md`, `27_TOOLS_call_records_and_display.md` |
| Status | accepted |
| Decided by | user (syntax given in the request, Q&A below); agent (validation, listing layout) |

## Context

User: "I want tool/functions to be able to be organised (i.e. grouped under various classes). by
default any new `@tool`/`register_tool!()` should be defined in the global tool set but there
should be way to define a group for tools e.g `@tool group=shell execute_shell_command` /
`register_tool!(execute_shell_command; group="shell")`. Tools should also get a standard name
which by default is just the function name but could also be set differently. These name should
be displayed without parentheses in the tool call/result output in streamed/final responses".

## Questions and Answers

| Question | Options | Chosen |
|---|---|---|
| "Standard name" | the name the model sees (`name=` override); separate display name | **separate display name** (model still sees the function name) |
| Keyword / field | `display_name`; `label`; `title` | **`label`** |
| What groups do | label + select via `tools(group)` / REPL `group:<g>`; dynamic group membership on sessions; label only | **label + select** (snapshot) |

## Decision

```julia
struct ToolSpec; name; description; parameters; f; group::String; label::String; end
register_tool!(f; group = "global", label = nothing)   # label defaults to string(nameof(f))
@tool group=shell label="Shell command" run_shell!      # group= for all named; label= for one
tools(group) -> Vector{ToolSpec}                          # throws for an empty/unknown group
set_tools!(s, tools("shell"))                             # names at that moment
```

REPL (`|`): `tools` lists by group (bold group header, label in parentheses when it differs from
the name); `tools use|add|drop` accept `group:<group>`; completion offers `group:<g>`;
`tools show` prints `group: …, label: …`.

Agent-decided:

- Default group `"global"`; group names match `^[A-Za-z0-9_.-]+$` (no spaces or `:` so
  `group:<g>` parses). Labels: any non-blank text, stripped.
- `@tool` options accept a bare name or a plain string literal; unknown options, repeats,
  interpolated strings, and `label=` with several functions throw `ArgumentError`.
- Re-registering replaces the whole spec, so `register_tool!(f)` without `group=` moves `f` back
  to `"global"`.
- Labels are looked up from the registry at display time (`_tool_label(name)`); calls of an
  unregistered tool show the wire name.
- `chat!(...; stream = true)` lines also use the label.

## Rejected

- `name =` override of the wire name: user wanted the model-facing name to stay the function
  name.
- Sessions holding groups dynamically: more state on `Session` and its file; snapshot is enough.

## Consequences

- `ToolSpec` has two more fields; `ToolSpec(...)` positional construction changed (internal use
  only).
- Relabelling a grouped tool needs its group repeated.

## Revisit Trigger

Requests for wire-name overrides, sessions that follow a group as it grows, or per-group
settings (e.g. confirmation only for `shell`).
