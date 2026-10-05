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

JAIL doesn't ask providers for reasoning summaries yet, so `text` is usually empty, and the REPL
doesn't show reasoning.

## Streaming

`chat!(s, prompt; stream = true)` prints the reply's text to `stdout` as it arrives and still
returns the full [`AssistantMessage`](@ref). Tool calls and their results are printed as
`→ name(args)` and `← result` lines between the text. All built-in providers can stream. The
`}` REPL mode streams when the Preference `stream = true` is set (see [REPL modes](repl.md)).

## Options and Preferences

- `max_tokens` caps the reply length for one call: `chat!(s, "..."; max_tokens = 200)`.
  Without it, the `max_tokens` Preference applies to every provider if it's set. Otherwise
  Anthropic uses 8192 (it requires a value) and the other providers let the model decide.
- `max_tool_rounds` caps tool rounds for one call: `chat!(s, "..."; max_tool_rounds = 2)`.
  Without it, the `max_tool_rounds` Preference applies (default 10).
- `store_requests` (default `true`): see above.
- `confirm_tools` (default `false`): see [Tools](tools.md#Preferences).

```toml
[JAIL]
max_tokens = 2048
store_requests = false
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
