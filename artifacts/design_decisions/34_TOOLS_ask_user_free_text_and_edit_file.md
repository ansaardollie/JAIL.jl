# Decision: `ask_user(...; allow_free_text)` and the line-based `edit_file` tool

| Field | Value |
|-------|-------|
| Artifact | `34_TOOLS_ask_user_free_text_and_edit_file.md` |
| Category | design_decisions |
| Subject | `TOOLS` |
| Date | 2026-10-05 |
| Area/Purpose scope | built-in tools (model-facing schema) |
| Related | `32_TOOLS_builtin_tools_groups_and_rules.md` |
| Status | accepted |
| Decided by | user (behavior); agent (names and details listed) |

## Context

User: "update the ask_user tool to include a bool argument (that is true by default) which allows
the user to enter free text input as an answer to multichoice question", and "add a `edit_file`
tool which works off line edits ... remove ... add (at this line number the added text is
appended) ... replace (at this line number the given regex is replaced with the input text)",
applied by iterating the original line numbers into a new IO buffer so edits don't shift each
other.

## Decision

```julia
ask_user(question, options = nothing, allow_free_text = true)
edit_file(path, edits::Vector{LineEdit})
struct LineEdit; action::String; line::Int; end_line::Union{Nothing,Int};
                 pattern::Union{Nothing,String}; text::Union{Nothing,String}; end
```

Agent-decided:

- Argument name `allow_free_text`; terminal menu gains a last "Other (type your own answer)"
  choice; without a terminal, non-number text is the answer, or with `false` the prompt repeats
  until a valid number.
- `edit_file` in group `edit`, label "Edit lines", security as `replace_in_file`
  (`:medium`, `:high` outside/protected); preview lists `- removed`, `+ added`, `/pattern/ → text`.
- `add` inserts after `line` (`0` = top); `remove`/`replace` take an optional `end_line`;
  replacement `text` is literal (no `$1` captures); a `replace` matching nothing, an unknown
  action, out-of-range lines, a line both removed and replaced, or a bad regex reject the whole
  call; CRLF and a missing final newline are kept.
- `action` is a `String`, not an `@enum` (an instance named `replace` would shadow
  `Base.replace` in JAIL); field rules live in the docstring because struct fields carry no
  per-field descriptions in the schema.

## Rejected

- Regex capture substitution in `text` (surprising `$`/`\` handling for the model).
- Applying edits sequentially with shifting line numbers (user specified original numbering).

## Revisit Trigger

Models misnumber lines often (consider numbered `read_file` output), or users want capture groups.
