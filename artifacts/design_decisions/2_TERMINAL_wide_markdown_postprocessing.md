# Terminal-Safe Markdown Post-Processing

| Field | Value |
|-------|-------|
| Artifact | `2_TERMINAL_wide_markdown_postprocessing.md` |
| Category | design_decision |
| Subject | `TERMINAL` — wide Markdown rendering |
| Date | 2026-09-25 |
| Decided by | agent, based on user requirements |
| Status | accepted |
| Related | `artifacts/work_history/6_TERMINAL_markdown_rendering.md` |

## Decision

Keep streaming output append-only so it appears immediately and preserves terminal scrollback. After the response completes, post-process oversized pipe tables before parsing and displaying the final Markdown. Wide tables become wrapped labeled entries; compact tables remain unchanged.

## Context

Terminal output is not a structured document surface. Once raw streaming text has scrolled into terminal history, selectively removing or replacing it would require cursor control or screen clearing and could erase earlier REPL commands. Markdown tables also do not reliably wrap in terminal renderers, even when the model is told the terminal width.

## Alternatives Rejected

- **Redraw the stream on every chunk:** rejected because cursor movement makes large responses difficult to scroll and can corrupt terminal history.
- **Clear the raw stream and replace it with formatted Markdown:** rejected because terminal escape sequences can remove earlier REPL output and there is no portable way to delete only the stream.
- **Wrap every Markdown line indiscriminately:** rejected because it can damage code blocks, headings, and already-valid Markdown structure.
- **Require the model to format every table correctly:** rejected because prompt guidance is advisory and models can emit malformed or oversized tables.

## Consequences

- Users see raw content while it streams and a cleaner formatted final block afterward.
- Oversized pipe tables are converted to labeled entries and wrapped to the current terminal width.
- Physically wrapped table rows and rows with extra pipe separators are normalized before conversion.
- The formatter is intentionally conservative for non-table Markdown.

## Revisit Trigger

Reopen this decision if JAIL adopts a structured terminal UI, a renderer with reliable in-place regions, or a requirement to hide raw streamed content while retaining immediate token display.
