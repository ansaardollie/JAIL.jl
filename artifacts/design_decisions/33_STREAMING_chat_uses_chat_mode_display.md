# Decision: `chat!(...; stream = true)` uses the `}` mode's turn display

| Field | Value |
|-------|-------|
| Artifact | `33_STREAMING_chat_uses_chat_mode_display.md` |
| Category | design_decisions |
| Subject | `STREAMING` |
| Date | 2026-10-05 |
| Area/Purpose scope | public behavior, REPL surface |
| Related | `16_STREAMING_repl_and_chat.md`, `14_REPL_chat_mode.md`, `27_TOOLS_call_records_and_display.md` |
| Status | accepted |
| Decided by | user (display); agent (script detection, flagged) |

## Context

User: "When using the `chat!` function the output is displayed twice ... Please can this be fixed
to only display it once after the `AssistantMessage` line". The text was printed while streaming
and again by the REPL's display of the returned `AssistantMessage`. A first attempt (stream on
the alternate screen, then replay tool lines; user's option B) was undone by the owner, who
asked: "Can we just make it work the same way that the chat repl works".

## Questions and Answers

| Question | Options | Chosen |
|---|---|---|
| Avoid the duplicate how? | A tool lines only, no streamed text; B alternate screen then erase; C keep text, display header only | B (first attempt, then undone) |
| Reuse `}` display with which ending? | exactly `}` (Tool calls + rendered `Output:`, text twice at the REPL); `}` without `Output:` (text once via the REPL display); `}` and return `nothing` | **`}` without `Output:`** |

## Decision

`chat!(s, prompt; stream = true)` calls the shared `_display_turn` (moved out of `_chat_send`
in `src/repl/chat_mode.jl`): on a terminal the turn streams on the alternate screen, then the
normal screen shows the `Tool calls (n):` block; the returned reply is displayed by the REPL.
Not a terminal: inline text and tool lines, then the block (as in `}`).

Agent-decided: inside a script (`Base.source_path(nothing) !== nothing`, i.e. `include`), nothing
displays the return value, so `Output:` with the rendered reply is printed as well. The stop
reason line of `}` is not printed by `chat!` (the `AssistantMessage` header shows it).

## Rejected

- Option A (lose live text); C (order doesn't match the request); exactly `}` (text twice);
  returning `nothing` (breaks `reply = chat!(...)`).
- The undone alternate-screen-plus-replay implementation (owner preferred one shared display).

## Consequences

- At the REPL, text written before tool calls is only on the alternate screen, as in `}`.
- `chat!(...; stream = true);` (with `;`) at the prompt shows no reply text.

## Revisit Trigger

Owner wants pre-tool text kept, or the script heuristic misfires (e.g. VS Code inline execution
setting a source path).

## Amendment (2026-10-05)

User: "When using the `chat!()` function the final output from the AssistantMessage should also
be a markdown display". `show(io, MIME"text/plain"(), ::AssistantMessage)` now renders the text
with `Markdown.parse` under the header line (for every display of an `AssistantMessage`, not only
after `chat!`); tool-call lines follow as before.
