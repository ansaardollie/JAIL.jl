# Decision: Session tools, tool-call types and the tool loop

| Field | Value |
|-------|-------|
| Artifact | `18_TOOLS_session_tools_and_call_loop.md` |
| Category | design_decisions |
| Subject | `TOOLS` |
| Date | 2026-09-28 |
| Area/Purpose scope | core ontology, public API, REPL |
| Related | `17_TOOLS_definitions_and_registry.md`, `9_SESSION_session_type.md`, `12_MESSAGES_types_and_chat.md`, `14_REPL_chat_mode.md`, `provider_reviews/4_TOOLS_function_calling.md` |
| Status | accepted |
| Decided by | user (all questions below); agent (details listed) |

## Context

User: "implementing the conversion to provider specific API shapes. Also, there should be way to
view all tools in the model repl mode. Also we can attach all tools to the session but add
functionality to restrict to a subset (in both code and the model repl mode)". Sending tools
without handling the calls breaks multi-turn history (Anthropic needs a `tool_result` after
every `tool_use`), so scope was asked. Supersedes the "no tools field" answer of decision 9.

## Questions and Answers

| Question | Options | Chosen |
|---|---|---|
| Scope | A conversion + attachment only; B also parse calls; C full loop | **C full loop** |
| Session tools API | A `tools(s)` + `set_tools!`; B `session_tools(s)`; C `restrict_tools!`/`allow_all_tools!` | **A** |
| Model-mode commands | full set; minimal | **full set** (below) |
| Google schema docs | fetch; send as-is | **fetch** (page had no field list; UNVERIFIED) |
| Call/result types | A `ToolCall` + `ToolResultMessage(results)`; B results in `UserMessage`; C one message per call | **A** |
| Result → text | string as-is, else JSON, else repr; string else repr | **string, else JSON, else repr** |
| Loop limit | Preference `max_tool_rounds` default 10 + `chat!` kwarg; pref only 10; pref only 25 | **Preference + kwarg, default 10** |
| `}` mode | uses session tools; text-only | **uses session tools** |
| `chat!` output | print tool lines when `stream = true`; never; always | **when `stream = true`** |
| Execution | sequential; concurrent; sequential + `confirm_tools` | **sequential + Preference `confirm_tools` (default false)** |

## Decision

```julia
struct ToolCall <: AbstractContentPart; id::String; name::String; arguments::Dict{String,Any}; end
struct ToolResult <: AbstractContentPart; call_id::String; name::String; content::String; is_error::Bool; end
struct ToolResultMessage <: AbstractMessage; content::Vector{ToolResult}; end

Session(model; name, system, tools = nothing)   # nothing = every registered tool
tools(s::Session) -> Vector{ToolSpec}           # effective tools
set_tools!(s, names_or_functions) / set_tools!(s, nothing) / set_tools!(names)  # active session
chat!(s, prompt; max_tokens, stream, max_tool_rounds = nothing)
```

Model mode: `tools`, `tools show <name>`, `tools use <name>...`, `tools add <name>...`,
`tools drop <name>...`, `tools all`, `tools none`; `status` shows a `Tools:` line.

Agent-decided details:

- `Session.tools::Union{Nothing,Vector{String}}`. Restricting to an unregistered name throws;
  a tool unregistered later is skipped silently. `tools add` on an unrestricted session is a
  no-op message; `tools drop` on one restricts to all-but-those.
- Loop: after each reply with `ToolCall`s, run them in order and append one
  `ToolResultMessage`; stop when a reply has no calls. On the limit, remaining calls get error
  results ("not run: tool round limit reached") so history stays valid, and `chat!` returns the
  last reply (`stop_reason = :tool_use`). If a request fails mid-loop, the whole turn
  (prompt included) is rolled back.
- Errors become `is_error = true` results: unknown tool, bad arguments, exceptions (message via
  `showerror`), user declined. Anthropic/Google send `is_error`; OpenAI/Chat get the text only.
- Arguments convert from JSON using `ToolParameter.type`; omitted trailing optionals use the
  Julia default; an omitted optional followed by a given one is an error result.
- `confirm_tools = true` asks `Run name(args)? [y/N]` on stdin before each call.
- `stop_reason` is `:tool_use` whenever a reply contains calls (OpenAI reports `completed`).
- Anthropic: consecutive same-role turns (a `ToolResultMessage` then a `UserMessage` after a
  hit limit) are merged into one user message, results first.
- `_replayable` keeps assistant messages that have calls even without text.

## Rejected

- Sending tools before the loop existed (breaks history). `session_tools`, `restrict_tools!`
  (less consistent with `tools()`/`set_model!`). Results inside `UserMessage` (not user-authored).
- Concurrent execution (side effects in the REPL become unordered).

## Consequences

- Every `chat!` on a session sends all registered tools unless restricted.
- Google stateless tool turns lose `thought` steps (todo 4).

## Revisit Trigger

Need for `tool_choice`/forced calls, per-call tool sets, provider-side rejection of the Google
schema, or a request for concurrent tool execution.
