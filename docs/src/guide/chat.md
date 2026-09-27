# Chat

[`chat!`](@ref) sends the next turn of a [`Session`](@ref):

1. The prompt is appended to `session.messages` as a [`UserMessage`](@ref).
2. The history and the session's `system` instructions go to the session's model (see
   [What gets sent](#What-gets-sent)).
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

## What gets sent

`session.messages` is always the full conversation, but not every turn resends it:

- **OpenAI and Google** store each reply server-side. The next turn sends only the new prompt
  plus the stored reply's id (`previous_response_id` / `previous_interaction_id`, taken from
  `reply.id`). The model may change between turns, as long as the provider stays the same.
- The full history is sent instead when the history was changed since that reply (edited,
  seeded, or `empty!`), the provider changed, or the stored reply is gone (the provider answers
  HTTP 400/404; JAIL retries once with the full history).
- **Anthropic and OpenAI-compatible servers** always get the full history.

Set the Preference `store_requests = false` to send `store = false` to OpenAI and Google and
always send the full history. Stored responses are kept by the provider (OpenAI: 30 days;
Google: 55 days paid, 1 day free).

## Options and Preferences

- `max_tokens` caps the reply length for one call: `chat!(s, "..."; max_tokens = 200)`.
  Without it, the `max_tokens` Preference applies to every provider if it's set. Otherwise
  Anthropic uses 8192 (it requires a value) and the other providers let the model decide.
- `store_requests` (default `true`): see above.

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
