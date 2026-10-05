# Decision: boxed turn display in Julia logo colors (Colors.jl dependency)

| Field | Value |
|-------|-------|
| Artifact | `36_STREAMING_boxed_turn_display.md` |
| Category | design_decisions |
| Subject | `STREAMING` |
| Date | 2026-10-05 |
| Area/Purpose scope | `}` mode / `chat!(; stream = true)` finished-turn display; dependencies |
| Related | `33_STREAMING_chat_uses_chat_mode_display.md`, `35_TOOLS_allow_lists_remove_file_response_header.md` |
| Status | accepted |
| Decided by | user (boxes, colors, bold, Colors.jl); agent (details listed) |

## Context

User: surround the whole chat output (prompt if shown + tool calls + response) in a colored
vertical box like `@info`'s; each of `Prompt` / `Tool calls` / `Response` in its own box and
color. Then: use `Colors.JULIA_LOGO_COLORS` (user added Colors.jl) — outer purple, prompt blue,
tools red, response green; then "make sure that the box is bolded".

## Decision

- Layout (`_render_turn` in `src/repl/chat_mode.jl`):
  ```
  ┏ Chat: <session name>
  ┃ ┏ Prompt:            (only when !isinteractive())
  ┃ ┃   ...
  ┃ ┗
  ┃ ┏ Tool calls (n):    (only when tools ran)
  ┃ ┗
  ┃ ┏ Response (model; N in; M out):
  ┃ ┗
  ┗
  ```
- Colors: `Colors.JULIA_LOGO_COLORS` purple/blue/red/green, printed as bold 24-bit SGR
  (`_print_rgb`; plain when `io` has no `:color`). `printstyled` can't take RGB.
- Heavy glyphs `┏ ┃ ┗`: bold SGR alone doesn't thicken box-drawing glyphs in most terminals.
- Section bodies are rendered into a buffer with `:displaysize` narrowed by the border width,
  then prefixed line by line (`_captured_lines`, `_box`).
- The Prompt box is drawn with the rest at the end (confirmations / `ask_user` appear above the
  box), except when streaming to a non-TTY: then Prompt box first, raw stream, Tool calls box,
  no outer box. With `output = false` (`chat!` at the REPL) only the Tool calls box.
- The `chat>` prompt stays `:cyan` (ReplMaker takes named colors only).

## Rejected

- Light glyphs `┌ │ └` with bold only (user saw no bold).
- 256-color approximations via `printstyled` (not the logo colors).
- Prefixing streamed non-TTY text live (more state for a rare path).

## Revisit Trigger

Terminals without truecolor show wrong colors; or users want the stop reason inside the box.
