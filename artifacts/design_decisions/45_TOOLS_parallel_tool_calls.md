# Decision: Parallel tool calls and concurrent tool execution

| Field | Value |
|-------|-------|
| Artifact | `45_TOOLS_parallel_tool_calls.md` |
| Category | design_decisions |
| Subject | `TOOLS` |
| Date | 2026-10-06 |
| Area/Purpose scope | tool loop, request bodies, ToolSpec, Preferences |
| Related | `18_TOOLS_session_tools_and_call_loop.md`, `17_TOOLS_definitions_and_registry.md`, `3_PREFERENCES_nested_layout.md` |
| Status | accepted |
| Decided by | user (scope, preference placement, no chat! kwarg, threads/tasks, public opt-out, one flag); agent (details listed) |

## Context

User: "add support for parallel tool/function calling - should be enabled by default with a
preference flag". Answers to the follow-up questions:

- Scope: wire flag **and** concurrent execution.
- Preference: both top-level `parallel_tool_calls` and `providers.<name>.parallel_tool_calls`
  (per-provider overrides top-level). Default `true`.
- No `chat!` keyword; Preference only.
- "if there's multiple threads use Threads.@spawn otherwise fallback to @async".
- Public per-tool opt-out for tools that must run alone.
- One flag controls both the wire field and concurrent execution.

## Decision

- Wire, only sent when the flag is `false` and the request has tools (provider defaults are
  parallel on): OpenAI Responses and OpenAI-compatible (Responses or Chat Completions)
  `parallel_tool_calls: false`; Anthropic `tool_choice: {type: "auto", disable_parallel_tool_use: true}`.
  Google (Interactions and generateContent) has no such field in the local specs; nothing sent.
- `ToolSpec.concurrent::Bool` (default `true`), set via `register_tool!(f; concurrent = false)` /
  `@tool concurrent=false f`; `show` prints "runs alone".
- Execution when on and a reply has more than one call: every call is confirmed first (one by
  one, in order); then `concurrent = false` calls run one by one in the main task; then the rest
  run together (`Threads.@spawn` when `Threads.nthreads() > 1`, else `@async`). Results and
  `on_step`/records are handled in the main task; the `ToolResultMessage` keeps call order.
  When off (or one call), the previous sequential loop is unchanged.
- Agent-decided built-ins with `concurrent = false`: `ask_user` (terminal), `execute_julia_code`
  (redirects process-wide stdout/stderr), `pkg_add`, `add_memory`, `remove_memory`, `tool_load`
  (mutates session tools), and `edit` tools except `create_directory` (same-file races).
- Agent-decided: the alone-calls run before the concurrent batch.
- Streaming display (user, follow-up: "for every group of parallel calls that are not needing
  confirmation ... `-> tool call` on the same line ... you don't need to show the `<- response`
  line. This should just apply to parallel tool call streaming"): in the concurrent path a call
  gets its own `→` line only when confirmed or run alone; the other batch calls share one line
  (`→ label (preview first line, 40 chars)` joined by two spaces) via `_RunningTogether`; no
  `←` lines; `_ToolsFinished` resets the non-streaming status to `thinking…`. Sequential path
  unchanged.

## Rejected

- Internal-only list of serial built-ins (user chose a public opt-out).
- `@async` only / threads only (user chose threads with an `@async` fallback).
- Sending `parallel_tool_calls: true` explicitly (some compatible servers reject unknown fields;
  true is every provider's default).
- Separate Preferences for the wire flag and execution.

## Revisit Trigger

Google adds a parallel-call field; users need the flag per call (`chat!` keyword); a tool's
side effects make the "alone first" ordering wrong; Ctrl-C needs to cancel running concurrent
calls (currently they finish in the background).
