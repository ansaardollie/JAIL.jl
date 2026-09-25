# Responses API as the default endpoint for `OpenAICompatible`

| Field | Value |
|-------|-------|
| Artifact | `9_OAI_PROVIDER_responses_default.md` |
| Category | work_history |
| Subject | `OAI_PROVIDER` — default endpoint and chat-completions opt-in |
| Date | 2026-09-25 |
| Area/Purpose scope | providers, configuration, docs |
| Related | `artifacts/design_decisions/5_OAI_PROVIDER_responses_default.md`, `artifacts/work_history/8_OAI_PROVIDER_responses_api.md` |

## Scope of This Unit of Work

A follow-up user request after artifact 8: make the Responses API the default and chat
completions the opt-in. It does not work through artifact 8's "Next Steps", which all remain
open.

## What Changed

| File | Change |
|------|--------|
| `src/models.jl` | `OpenAICompatible.responses::Bool = false` is renamed to `chat_completions::Bool = false`, and the logic is inverted. `request_body` takes the Responses path when `!m.chat_completions`. `request_url` returns `/v1/chat/completions` only when `m.chat_completions`, otherwise `/v1/responses`. `parse_answer` calls `_responses_answer` unless `m.chat_completions`. |
| `src/AskAI.jl` | The `setapi` keyword `responses` is now `chat_completions = nothing`, falling back to `ENV["ASK_AI_CHAT_COMPLETIONS"]` in (`1`, `true`, `yes`), default `false`. Docstring example and `CONFIG_HELP` row updated. `ASK_AI_RESPONSES_API` is removed. |
| `readme.md` | The env-var row is now `ASK_AI_CHAT_COMPLETIONS`. |

## Design Decisions Made

See `artifacts/design_decisions/5_OAI_PROVIDER_responses_default.md`, which partially supersedes
decision 4. Rejected:

- keeping `responses` with a default of `true`;
- a string setting such as `ASK_AI_OPENAI_API`;
- a deprecation alias for `ASK_AI_RESPONSES_API` (it was never released).

## Verification

Fresh REPL (`restart-julia-repl`), local gateway, model `Discovery-large` from the environment:

```julia
delete!(ENV, "ASK_AI_RESPONSES_API"); delete!(ENV, "ASK_AI_CHAT_COMPLETIONS")
using AskAI
B = AskAI.Brain; B.stream = false; B.render_final = false
show_mode(label) = println(rpad(label, 34), "chat_completions=", B.model.chat_completions, "  ", AskAI.request_url(B.model, false))
show_mode("default (no env):")
println("  -> ", repr(string(B("Reply with exactly: responses ok"))))
ENV["ASK_AI_CHAT_COMPLETIONS"] = "true"; setapi(ENV["ASK_AI_PROVIDER"], ENV["ASK_AI_MODEL"])
show_mode("ENV ASK_AI_CHAT_COMPLETIONS=true:")
B.stream = true; B("Reply with exactly: chat ok"); B.stream = false
setapi(ENV["ASK_AI_PROVIDER"], ENV["ASK_AI_MODEL"]; chat_completions = false)
show_mode("keyword false overrides env:")
delete!(ENV, "ASK_AI_CHAT_COMPLETIONS"); setapi(ENV["ASK_AI_PROVIDER"], ENV["ASK_AI_MODEL"]; chat_completions = true)
show_mode("keyword true, no env:")
setapi("openai", "gpt-5-mini"; api = "x"); show_mode("openai provider default:")
```

```text
default (no env):                 chat_completions=false  https://llmgarden.in.zeus.dsyai.co.za/v1/responses
  -> "responses ok\n"
ENV ASK_AI_CHAT_COMPLETIONS=true: chat_completions=true  https://llmgarden.in.zeus.dsyai.co.za/v1/chat/completions
¬ chat ok
keyword false overrides env:      chat_completions=false  https://llmgarden.in.zeus.dsyai.co.za/v1/responses
keyword true, no env:             chat_completions=true  https://llmgarden.in.zeus.dsyai.co.za/v1/chat/completions
openai provider default:          chat_completions=false  https://llmgarden.in.zeus.dsyai.co.za/v1/responses
```

`get_errors` on `src/`: no errors.

Not verified:

- The multi-turn eval from artifact 8 was not rerun after the rename. The Responses code path
  itself is unchanged; only the flag's name and polarity changed.
- Real OpenAI (the last line only checks the URL; `ASK_AI_BASE_URL` from the environment
  overrides the `api.openai.com` default).
- Local servers that don't support `/v1/responses`.

## Known Limitations

- Local servers without `/v1/responses` fail by default until `ASK_AI_CHAT_COMPLETIONS=true` is
  set. There is no automatic fallback.
- Any code that used the one-commit-old `responses` keyword or field breaks. No alias was kept.
- Artifact 8's limitations still apply (error events, turn-count-only limit, chat completions has
  no message history).

## Todos

- Completed: none (no `artifacts/todos/` folder exists).
- Created: none.

## Next Steps

1. Consider an automatic fallback to chat completions when `/v1/responses` returns 404
   (decision 5's revisit trigger).
2. Artifact 8's Next Steps 1–5 are still open: raise errors on `response.failed`, message history
   for chat completions, a `test/` eval script, real OpenAI verification, and the carried-over
   items.
