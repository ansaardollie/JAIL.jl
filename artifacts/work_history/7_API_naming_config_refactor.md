# Naming and configuration refactor

| Field | Value |
|-------|-------|
| Artifact | `7_API_naming_config_refactor.md` |
| Category | work_history |
| Subject | `API` — public names, configuration, request lifecycle |
| Date | 2026-09-25 |
| Area/Purpose scope | API, core, configuration, docs |
| Related | `artifacts/design_decisions/3_API_naming_and_env_config.md`, `artifacts/work_history/6_TERMINAL_markdown_rendering.md` |

## Scope of This Unit of Work

A large refactor fixing design and naming decisions that were not ideal. The chat session that
produced it was lost; this record was reconstructed from `git diff` against `2402586` and then
verified in a fresh REPL. It does not follow the "Next Steps" of artifact 6 (tests, docs build),
which remain open.

## What Changed

| File | Change |
|------|--------|
| `src/models.jl` | `modelProvider`→`ModelProvider`, `ollama`→`Ollama`; `OpenAICompatible.baseurl`→`url` (with or without `/v1`); new `NotConfigured` placeholder. Dispatch renamed: `available_models(m = Brain.model; pretty)` (via per-provider `_list_models`), `check_config` (via `_required_config`), `request_body(m, brain, question)`, `request_url(m, stream)`, `parse_answer(m, resp, stream)`, `_request_headers`, `_base_url`. Brain context (terminal hint, `prompt`, `rag`, `memory`) is now sent as a real system message (`_system_prompt`), not string-prefixed. Gemini key moved from the query string to the `x-goog-api-key` header. Errors are thrown rather than returned as strings. |
| `src/brain.jl` | `AIBrain` fields concretely typed; `RAG`→`rag`; `timeout` default 10→60; new `terminal_hint` and `render_final` flags. Request split into `_complete`, `_ask_once`, `_ask_stream`, `_remember!`. Streaming uses one channel with a line buffer for SSE lines split across reads (replacing the two-channel `showStreamStringFromChannel`/`streamToMemory`). History no longer stores the `"ans: "` prefix. `check_memory!` now summarizes with the current model (previous code referenced an undefined `AI_API_KEY`). `changeModels!`→`change_model!`; internal helpers snake_cased. |
| `src/AskAI.jl` | `const Brain` mutated in place; `setapi(provider, model; url, api)` with env fallbacks `ASK_AI_PROVIDER/MODEL/BASE_URL/API_KEY`, `OPENAI_API_KEY`, `OPENAI_BASE_URL`, `GEMINI_API_KEY`; provider defaults for Ollama and OpenAI URLs; `"openai"` added as provider. `setapi("p|m|x")` and `ENV["AskAI_config"]` kept with deprecation warning. `reset()` clears history/memory/rag only. `@ai`/`@AI` share `_question_expr`; `@AI` restores `Brain.stream` in a `finally`. `exe`→`run_code`. Deprecations for `avaliableModels`, `changeModels!`, `exe`, `modelProvider`, `ollama`. REPL mode calls `Brain(s)` directly instead of re-parsing a string. Exports `setapi, @ai, @AI, available_models, change_model!`. |
| `Project.toml` | Added compat `HTTP = "2"`, `JSON3 = "1"`, `julia = "1.10"` (key order also changed). |
| `readme.md`, `docs/src/index.md` | Documented the env-var configuration table, keyword `setapi`, `run_code`, `terminal_hint`. |
| `artifacts/design_decisions/1_OAI_PROVIDER_key_at_url_config.md` | Marked superseded. |

## Design Decisions Made

See `artifacts/design_decisions/3_API_naming_and_env_config.md` (supersedes decision 1). Rejected:
keeping the overloaded `key@url` string, and a hard break without deprecations.

## Verification

Fresh REPL (`restart-julia-repl`), local gateway configured via the new env vars:

```julia
let (key, url) = split(split(pop!(ENV, "AskAI_config"), "|")[3], "@"; limit=2)
    ENV["ASK_AI_PROVIDER"] = "openai-compatible"; ENV["ASK_AI_MODEL"] = "openai/qwen3-coder-30b"
    ENV["ASK_AI_BASE_URL"] = url; ENV["ASK_AI_API_KEY"] = key
end
using AskAI
println(typeof(AskAI.Brain.model), " models: ", length(available_models(pretty=false)))
AskAI.Brain.stream = false
println(@ai "Reply with exactly: ASK_AI ok")
```

```text
REPL mode askai initialized. Press } to enter and backspace to exit.
AskAI.OpenAICompatible models: 90
ASK_AI ok
```

```julia
AskAI.Brain.stream = true
r = @ai "Reply with exactly: stream ok"
println("\nhistory: ", length(AskAI.Brain.history["ans"]), " last=", repr(AskAI.Brain.history["ans"][end]))
AskAI.reset(); println("after reset: ", length(AskAI.Brain.history["ans"]), " ", typeof(AskAI.Brain.model))
println(AskAI.ollama === AskAI.Ollama, " ", AskAI.modelProvider === AskAI.ModelProvider)
```

```text
¬ stream ok
history: 2 last="stream ok"
after reset: 0 AskAI.OpenAICompatible
true true
```

`get_errors` on `src/`: no errors.

Not verified: Gemini and Ollama providers (no endpoints available), real OpenAI key auth, the
deprecated `setapi("p|m|x")` / `AskAI_config` path, `@AI` code execution, `check_memory!`
summarization (needs >3000 chars of memory), docs build.

## Known Limitations

- No automated test suite.
- `check_memory!` runs asynchronously and replaces `memory` wholesale; a concurrent question may
  race with it.
- Deprecated names must be removed in a future breaking release.

## Todos

- Completed: none (no `artifacts/todos/` folder exists).
- Created: none.

## Next Steps

1. Add a `test/` suite: `setapi` env fallbacks and defaults, `_base_url` normalization, `parse_answer`
   on sample SSE lines for each provider, `_format_markdown_for_terminal` cases from artifact 6.
2. Exercise the deprecated `setapi("provider|model|key@url")` and `ENV["AskAI_config"]` paths once.
3. Verify against real OpenAI with `setapi("openai", "gpt-4o-mini")` + `OPENAI_API_KEY`.
4. Instantiate the docs environment and run `docs/make.jl`.
