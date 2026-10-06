# Chat

[`chat!`](@ref) sends the next turn of a [`Session`](@ref):

1. The prompt is appended to `session.messages` as a [`UserMessage`](@ref).
2. The history, the session's `system` instructions and its tools go to the session's model
   (see [What gets sent](#What-gets-sent)).
3. The reply is appended as an [`AssistantMessage`](@ref). If it calls tools, JAIL runs them,
   appends a [`ToolResultMessage`](@ref) and asks again, until a reply calls no tools (see
   [Tools](tools.md)).
4. The last reply is returned.

If a request fails, the history is left as it was. Each message is also saved to disk as it is
added, and a failed turn is removed again (see
[Saving and restoring](sessions.md#Saving-and-restoring)).

```julia
s = Session("anthropic/claude-sonnet-4-5"; system = "Answer with one word.")
reply = chat!(s, "Colour of grass?")
string(reply)          # "Green"
reply.stop_reason      # :end_turn
reply.usage            # Usage(21 in, 4 out)

chat!("Colour of coal?")   # on the active session
```

Every provider is supported: OpenAI (Responses API), Anthropic (Messages API), Google
(Interactions API), [`GoogleEnterprise`](@ref) (the Interactions API by default, or Vertex AI
`generateContent` with `api = :generate_content`), and OpenAI-compatible servers (Responses, or Chat
Completions when registered with `api = :chat_completions`). The model may call the session's
tools; see [Tools](tools.md).

## Messages

History is provider-agnostic, so a session can switch model or provider between turns with
[`set_model!`](@ref). A message's `content` is a vector of content parts: [`TextPart`](@ref),
[`ToolCall`](@ref) / [`ToolResult`](@ref) when tools are used, and in replies the model's
[`ReasoningPart`](@ref)s. `string(msg)` returns the text.

```@example chat
using JAIL

u = UserMessage("What is 2 + 2?")
```

```@example chat
u.content
```

A hand-written reply has no model, stop reason or usage. Push messages onto
`session.messages` to seed a history, e.g. with few-shot examples:

```@example chat
s = Session("anthropic/claude-sonnet-4-5"; name = "few-shot", system = "Answer with one word.")
push!(s.messages, UserMessage("Colour of the sky?"), AssistantMessage("Blue"))
s.messages
```

## Stop reasons

`reply.stop_reason` is one of:

| Symbol | Meaning |
|---|---|
| `:end_turn` | The model finished its turn. |
| `:max_tokens` | The reply hit `max_tokens` or the context window. |
| `:stop_sequence` | A stop sequence was generated (Anthropic only). |
| `:tool_use` | The model called tools (the reply holds [`ToolCall`](@ref)s). |
| `:refusal` | The model declined. |
| `:content_filter` | The provider filtered the output. |
| `:other` | Anything else. |

## What gets sent

`session.messages` is always the full conversation, but not every turn resends it:

- **OpenAI and Google** (and `GoogleEnterprise`, unless `api = :generate_content`) store each reply
  server-side. The next request sends only what came
  after the stored reply (the new prompt, or the results of the tools it called) plus that
  reply's id (`previous_response_id` / `previous_interaction_id`, taken from `reply.id`). The
  model may change between turns, as long as the provider stays the same.
- The full history is sent instead when the history was changed since that reply (edited,
  seeded, or `empty!`), the provider changed, the session was restored with
  [`restore_session!`](@ref) in a new Julia process, or the stored reply is gone (the provider
  answers HTTP 400/404; JAIL retries once with the full history).
- **Anthropic, OpenAI-compatible servers and `GoogleEnterprise` with `api = :generate_content`**
  always get the full history.

Set the Preference `store_requests = false` to send `store = false` to OpenAI, Google and
`GoogleEnterprise` (Interactions) and always send the full history. Stored responses are kept by
the provider (OpenAI: 30 days; Google: 55 days paid, 1 day free).

## Reasoning

Thinking models return their reasoning alongside the reply as signed records that only the
provider can read: Anthropic `thinking` blocks, OpenAI `reasoning` items, Google `thought` steps,
and `thoughtSignature`s on `GoogleEnterprise`'s `generateContent` replies. Each is kept in the
reply's `content`, in the order it arrived, as a [`ReasoningPart`](@ref). Its `text` is the
readable summary and `format` names the wire format it came from; its `data` is opaque. It is
not part of `string(reply)`:

```@example chat
reply = AssistantMessage([ReasoningPart("Check the units first.", :anthropic), TextPart("22°C")])
reply.content
```

```@example chat
string(reply)
```

When the full history is sent (see above), reasoning goes back unchanged, which the providers
require when a reply called tools. It goes back only to the provider type and wire format that
produced it: after a switch to another provider, or between `GoogleEnterprise`'s two `api`
settings, it is left out. Hand-written replies such as the one above have no model, so their
reasoning is never sent. Chained turns don't resend it; the provider already holds it.

JAIL doesn't ask providers for reasoning summaries unless `show_reasoning` is on (see
[Thinking effort, temperature and reasoning](#Thinking-effort,-temperature-and-reasoning)), so
`text` is usually empty. OpenAI-compatible servers on Chat Completions that return reasoning text
(`reasoning_content` or `reasoning`, e.g. vLLM, LM Studio, DeepSeek) get a `:chat_completions`
part, which is never sent back.

## Thinking effort, temperature and reasoning

`thinking_effort` sets how much the model reasons, `temperature` its sampling temperature:

```julia
chat!(s, "Prove it."; thinking_effort = :high)
chat!(s, "Name a colour."; temperature = 0.2)
```

Each is taken from, in order: the `chat!` keyword, the session (set with
[`set_thinking_effort!`](@ref) / [`set_temperature!`](@ref), or `Session(...; thinking_effort,
temperature)`; saved with the session), then the Preference of the same name. When all are
unset, nothing is sent and the model's default applies.

```julia
s = Session("openai/gpt-5"; thinking_effort = :low)
set_temperature!(s, 0.5)
set_thinking_effort!(s, nothing)    # back to the Preference, if any
```

The effort is a `Symbol`, sent as-is; JAIL doesn't check it against the model:

| Provider | Sent as | Levels the provider documents |
|---|---|---|
| OpenAI, OpenAI-compatible (Responses) | `reasoning.effort` | `:none`, `:minimal`, `:low`, `:medium`, `:high`, `:xhigh`, `:max` (per model) |
| OpenAI-compatible (Chat Completions) | `reasoning_effort` | as OpenAI; up to the server |
| Anthropic | `output_config.effort` plus `thinking: {type: "adaptive"}`; `:none` sends `thinking: {type: "disabled"}` | `:low`, `:medium`, `:high`, `:xhigh`, `:max` (per model) |
| Google, `GoogleEnterprise` (Interactions) | `generation_config.thinking_level` | `:minimal`, `:low`, `:medium`, `:high` (per model) |
| `GoogleEnterprise` (`generateContent`) | `generationConfig.thinkingConfig.thinkingLevel`, in upper case | as Google |

A level the model doesn't take comes back as the provider's error. Temperature is sent as-is
too: OpenAI takes 0 to 2, Anthropic 0 to 1. The newest Anthropic models (e.g. Claude Sonnet 5)
reject any temperature but the default, with or without thinking, and Google has deprecated it
on its latest models.

`show_reasoning = true` (or the Preference `show_reasoning = true`) asks for readable reasoning
summaries, which fill the replies' [`ReasoningPart`](@ref) `text`:

| Provider | Sent as |
|---|---|
| OpenAI, OpenAI-compatible (Responses) | `reasoning.summary = "auto"` |
| OpenAI-compatible (Chat Completions) | nothing; reasoning text the server returns anyway is kept |
| Anthropic | `thinking.display = "summarized"`, only with a `thinking_effort` |
| Google, `GoogleEnterprise` (Interactions) | `generation_config.thinking_summaries = "auto"` |
| `GoogleEnterprise` (`generateContent`) | `generationConfig.thinkingConfig.includeThoughts = true` |

Without a `thinking_effort` (from `chat!`, the session or the Preference), Anthropic gets no
thinking or effort settings at all, so models that hide their thinking by default (Sonnet 5,
Opus 5.x) return no summaries. Anthropic models that only support extended thinking
(`budget_tokens`, e.g. Haiku 4.5) reject the adaptive thinking an effort sends, so leave
`thinking_effort` unset for them.

When streaming, summaries are shown dimmed above the reply text as they arrive. After each
turn, each summary is saved to `<storage_dir>/reasoning/<session id>/<trace id>.md`: YAML front
matter with the trace id, session id, reply id, model, format and time, then the summary as the
model wrote it. In the `}` mode and with `chat!(...; stream = true)`, the finished turn gets a
`Reasoning` box linking to those files rather than repeating the text (see
[REPL modes](repl.md#Reasoning)).

```julia
chat!(s, "What is the GCD of 1071 and 462?"; stream = true, show_reasoning = true)
```

## Counting tokens

[`count_tokens`](@ref) asks the model's provider how many input tokens the session's context
takes up: its system instructions, tool definitions and full message history, as a full-history
turn would send them. Pass a prompt to count it as the next turn without sending it, and
`model` to count the same context for another model:

```julia
count_tokens(s)                                  # TokenCount: total, system, tools, messages
count_tokens(s, "And London?")                   # as if this were the next prompt
count_tokens(s; model = "google/gemini-3-flash")  # the same context on another model
```

It uses each provider's counting endpoint (OpenAI and OpenAI-compatible:
`/responses/input_tokens`; Anthropic: `/v1/messages/count_tokens`; Google and `GoogleEnterprise`:
`:countTokens`), which generates nothing, and makes one request per part present. The parts are
found by counting with a part left out, so they are approximate; `total` is their sum. Many
OpenAI-compatible servers have no counting endpoint, and `count_tokens` throws for them.

## Streaming

`chat!(s, prompt; stream = true)` shows the turn as the `}` REPL mode does (see
[REPL modes](repl.md)): on a terminal the reply streams on the alternate screen, with
`→ label` (plus the tool's `preview`, if any) and `← label: result` lines for tool calls (see
[Tools](tools.md#Previewing-arguments)); then the normal screen gets the `Tool calls` box and
the REPL's display of the returned [`AssistantMessage`](@ref) shows the text, once, rendered as
Markdown (any `AssistantMessage` displays this way). Inside a
script (`include`), where nothing displays the return value, the whole turn is printed in the
`}` mode's boxes instead (with a `Prompt:` box first when Julia is not interactive). When
`stdout` isn't a terminal, text and tool lines are printed as they
arrive. All built-in providers can stream. The `}` REPL mode streams when the Preference
`stream = true` is set.

## Options and Preferences

- `max_tokens` caps the reply length for one call: `chat!(s, "..."; max_tokens = 200)`.
  Without it, the `max_tokens` Preference applies to every provider if it's set. Otherwise
  Anthropic uses the model's maximum output (128000; Haiku 4.5: 64000; 3.5: 4096) (it requires a value) and the other providers let the model decide.
- `max_tool_rounds` caps tool rounds for one call: `chat!(s, "..."; max_tool_rounds = 2)`.
  Without it, the `max_tool_rounds` Preference applies (default 10).
- `thinking_effort`, `temperature` and `show_reasoning`: see
  [above](#Thinking-effort,-temperature-and-reasoning).
- `store_requests` (default `true`): see above.
- `tool_approval` (default `"auto"`) and `tool_auto_approvals` (default empty): which tool calls
  are confirmed first; see [Tools](tools.md#Security-levels-and-approval).

```toml
[JAIL]
max_tokens = 2048
store_requests = false
thinking_effort = "low"
temperature = 0.5
show_reasoning = true
```

## Troubleshooting

Set `ENV["JULIA_DEBUG"] = "JAIL"` to log each request and response body. Headers, and so API
keys, are never logged.

```@example chat
try
    chat!(s, "   ")
catch e
    showerror(stdout, e)
end
```
