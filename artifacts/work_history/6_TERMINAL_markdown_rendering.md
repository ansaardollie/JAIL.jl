# Terminal Markdown Rendering

| Field | Value |
|-------|-------|
| Artifact | `6_TERMINAL_markdown_rendering.md` |
| Category | work_history |
| Subject | `TERMINAL` — streaming and wide Markdown output |
| Date | 2026-09-25 |
| Area/Purpose scope | terminal rendering, Markdown post-processing, documentation |
| Related | `artifacts/design_decisions/2_TERMINAL_wide_markdown_postprocessing.md`, `artifacts/work_history/5_OAI_PROVIDER_local_support.md` |

## Scope of This Unit of Work

This unit continued from the local OpenAI-compatible provider work and addressed terminal usability: streaming output was difficult to scroll, and large Markdown tables still overflowed the terminal. The completed behavior preserves append-only streaming while making the final rendered Markdown more terminal-friendly.

## What Changed

| File | Change |
|------|--------|
| `src/brain.jl` | Replaced cursor-redraw streaming with append-only flushed chunks; removed the terminal reset; added a final output boundary; added Markdown table post-processing that detects oversized pipe tables, merges physically wrapped continuation rows, normalizes extra pipe cells, converts wide tables to labeled entries, and wraps values to terminal width. |
| `src/models.jl` | Continues to include live terminal rows and columns in the model prompt as advisory formatting guidance. |
| `readme.md` | Documents terminal-size guidance and wide-table conversion. |
| `docs/src/index.md` | Documents terminal-size guidance and wide-table conversion. |
| `artifacts/design_decisions/2_TERMINAL_wide_markdown_postprocessing.md` | Records the terminal-safe rendering decision and rejected alternatives. |

## Design Decisions Made

- Preserve raw append-only streaming and render a normalized final Markdown block below it. The rejected alternatives were cursor redraws and clearing/replacing the stream, both of which make scrollback unreliable or risk erasing earlier REPL output. See `artifacts/design_decisions/2_TERMINAL_wide_markdown_postprocessing.md`.
- Normalize only oversized pipe tables rather than wrapping all Markdown. This avoids damaging code blocks, headings, and ordinary Markdown while addressing the specific terminal renderer limitation.

## Verification

Package loading and wide-table formatting were verified in the Julia REPL:

```julia
using JAIL
wide = "| Feature | OLAP | OLTP |\n|---|---|---|\n| Purpose | A very long analytical description that exceeds the terminal width and should wrap safely | A long transactional description that should also wrap safely |"
formatted = JAIL._formatMarkdownForTerminal(wide)
println("wide table converted: ", !occursin("| Feature | OLAP | OLTP |", formatted))
println("max formatted line: ", maximum(length.(split(formatted, "\\n"))))
```

Actual output:

```text
REPL mode askai initialized. Press } to enter and backspace to exit.
JAIL loaded: JAIL
wide table converted: true
max formatted line: 78
```

A malformed-table probe with physically wrapped continuation rows also produced one logical entry per source row and no repeated `Feature` labels. `get_errors` reported no errors for `src/brain.jl`, `readme.md`, or `docs/src/index.md`, and `git diff --check` passed.

## Known Limitations

- Raw streamed text remains visible while tokens arrive; only the completed final Markdown block is post-processed. Selectively replacing already-scrolled terminal output is not portable or safe.
- The formatter targets pipe-style Markdown tables. Other table syntaxes or highly malformed structures may require future handling.
- Pipe characters inside table cell content are treated as separators by the lightweight parser.
- The full Documenter build remains unverified because the docs environment lacks `Documenter.jl`.
- No automated test suite was added; verification used the Julia REPL and source diagnostics.

## Todos

- Completed: none.
- Created: none.

## Next Steps

1. Add focused tests for compact tables, wrapped continuation rows, malformed extra separators, and pipe characters inside cells.
2. Consider a structured terminal renderer if raw streaming output must also be formatted before display.
3. Instantiate the docs environment and run `docs/make.jl` when Documenter is available.
