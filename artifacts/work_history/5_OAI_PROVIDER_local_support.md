# OpenAI-Compatible Local Provider Support

| Field | Value |
|-------|-------|
| Artifact | `5_OAI_PROVIDER_local_support.md` |
| Category | work_history |
| Subject | `OAI_PROVIDER` — local OpenAI-compatible model support |
| Date | 2026-09-25 |
| Area/Purpose scope | provider API, configuration, streaming, documentation |
| Related | `artifacts/design_decisions/1_OAI_PROVIDER_key_at_url_config.md` |

## Scope of This Unit of Work

This unit started from the existing Gemini/Ollama provider dispatch documented in `4_PROMPTINGTOOLS_library_inventory.md` and added support for local OpenAI-compatible `/v1` APIs. It also documented the provider, changed credentials to a portable `key@url` form with an `JAIL_key` fallback, and removed the terminal reset that erased prior REPL output.

## What Changed

| File | Change |
|------|--------|
| `src/models.jl` | Added `OpenAICompatible`, OpenAI chat-completions payloads, `/v1/models`, bearer headers, URL normalization, non-streaming response parsing, and SSE delta parsing. Added graceful model-listing error handling. |
| `src/JAIL.jl` | Added `openai` and `openai-compatible` provider names. Parses the third field as `key@url`, accepts `@url`, and falls back to `ENV["JAIL_key"]` for URL-only configurations. |
| `src/brain.jl` | Uses provider-specific request headers, ignores empty streaming deltas, and no longer emits `\033c`, preserving terminal output. |
| `readme.md` | Added local OpenAI-compatible setup and `key@url` examples. |
| `docs/src/index.md` | Added provider requirements, model discovery, streaming/non-streaming examples, and fallback-key documentation. |
| `.github/agents/oai-provider-builder.agent.md` | Preserved the user-customized provider-agent instruction change already present in the worktree. |
| `artifacts/design_decisions/1_OAI_PROVIDER_key_at_url_config.md` | Recorded the public configuration decision and rejected alternatives. |

## Design Decisions Made

- OpenAI-compatible credentials use `key@url` in the existing `JAIL_config` third field. `@url` is unauthenticated, and URL-only remains compatible through `ENV["JAIL_key"]`. The rejected alternatives were separate environment variables, retaining the development-specific `AI_DEV_KEY`, or adding a new configuration dependency/object. See `artifacts/design_decisions/1_OAI_PROVIDER_key_at_url_config.md`.
- The implementation uses existing HTTP.jl and JSON3.jl dependencies and the established `modelProvider` dispatch rather than adding OpenAI.jl or PromptingTools.jl as dependencies.
- Streaming ignores empty role/reasoning deltas before repetition detection. This was necessary because the live gateway emits reasoning-only chunks before content; the alternative of treating every SSE chunk as visible output caused premature stream termination.

## Verification

Package loading and configuration parsing were verified in the Julia REPL:

```julia
using JAIL
ENV["JAIL_key"] = "fallback-key"
ENV["AI_DEV_KEY"] = "old-key"
JAIL.setapi("openai-compatible|local|http://localhost:7000")
fallback = JAIL.Brain.model
println("uses JAIL_key fallback: ", fallback.api == "fallback-key")
JAIL.setapi("openai-compatible|local|embedded-key@http://localhost:8000")
embedded = JAIL.Brain.model
println("key@url overrides fallback: ", embedded.api == "embedded-key" && embedded.baseurl == "http://localhost:8000")
```

Actual output:

```text
REPL mode askai initialized. Press } to enter and backspace to exit.
uses JAIL_key fallback: true
key@url overrides fallback: true
```

Earlier live gateway verification also completed through the Julia REPL after the environment was configured:

```text
models available: 90
non-stream: JAIL non-stream works.
stream history: ans: JAIL stream works.
```

The raw SSE probe confirmed content chunks after reasoning chunks, and the provider parser returned `parser probe.` from the streamed response. Source diagnostics reported no errors for `src/models.jl`, `src/brain.jl`, `src/JAIL.jl`, `readme.md`, or `docs/src/index.md`. `git diff --check` passed.

## Known Limitations

- The Documenter build was not run successfully because the docs environment lacks the installed `Documenter` package; `include("/home/coder/forks/JAIL/docs/make.jl")` failed with `Package Documenter ... does not seem to be installed`.
- No real OpenAI account/key was tested; verification used the configured local gateway.
- The `key@url` syntax treats the first `@` as the separator. Keys containing `@` are not supported without a future escaping rule.
- No automated test suite was added; verification was performed through the project Julia REPL and source diagnostics.

## Todos

- Completed: none.
- Created: none.

## Next Steps

1. Instantiate the docs environment with Documenter available and run `docs/make.jl`.
2. Add focused fake-endpoint tests for `/v1/models`, non-streaming chat, SSE streaming, auth headers, and `key@url` parsing.
3. Consider validating `setapi` input shape and documenting an escaping rule if credentials containing `@` become relevant.
