# Chat

[`chat!`](@ref) sends the next turn of a [`Session`](@ref):

1. The prompt is appended to `session.messages` as a [`UserMessage`](@ref).
2. The whole history and the session's `system` instructions go to the session's model.
3. The reply is appended as an [`AssistantMessage`](@ref) and returned.

If the request fails, the history is left as it was.

```julia
s = Session("anthropic/claude-sonnet-4-5"; system = "Answer with one word.")
reply = chat!(s, "Colour of grass?")
string(reply)          # "Green"
reply.stop_reason      # :end_turn
reply.usage            # Usage(21 in, 4 out)

chat!("Colour of coal?")   # on the active session
```

Every provider is supported, text only for now: OpenAI (Responses API), Anthropic
(Messages API), Google (Interactions API), and OpenAI-compatible servers (Responses, or Chat
Completions when registered with `api = :chat_completions`).

## Messages

History is provider-agnostic, so a session can switch model or provider between turns with
[`set_model!`](@ref). A message's `content` is a vector of content parts. [`TextPart`](@ref)
is the only one so far. `string(msg)` returns the text.

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
| `:tool_use` | The model wants to call a tool. |
| `:refusal` | The model declined. |
| `:content_filter` | The provider filtered the output. |
| `:other` | Anything else. |

## Options and Preferences

- `max_tokens` caps the reply length for one call: `chat!(s, "..."; max_tokens = 200)`.
  Without it, the `max_tokens` Preference applies to every provider if it's set. Otherwise
  Anthropic uses 8192 (it requires a value) and the other providers let the model decide.
- OpenAI and Google keep requests server-side by default. JAIL keeps the history itself and
  sends `store = false` unless the Preference `store_requests = true` is set.

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
