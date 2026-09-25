# Initial package review and architecture overview

| Field | Value |
|-------|-------|
| Artifact | `1_ASKAI_package_overview.md` |
| Category | work_history |
| Subject | `ASKAI` — package architecture and runtime flow |
| Date | 2026-09-25 |
| Area/Purpose scope | package architecture, API integration, REPL behavior |
| Related | none |

## Scope of This Unit of Work

This session reviewed the package source and documentation to understand how AskAI currently works, how it configures providers, and how the user-facing macros and runtime state fit together.

## What Changed

| File | Change |
|-------|--------|
| `src/AskAI.jl` | Documented the module bootstrap, environment-based configuration, REPL entry mode, and the `@ai` / `@AI` macros. |
| `src/brain.jl` | Described the central `AIBrain` state, the request flow, streaming response handling, memory tracking, and conversation history behavior. |
| `src/models.jl` | Summarized the provider abstractions for `Gemini` and `ollama`, including JSON payload creation, API URLs, and response parsing. |
| `readme.md` | Confirmed the intended user-facing role: query an LLM, optionally run generated Julia code in a `playground` module, and use REPL mode. |

No source code was modified during this pass; this artifact records the existing design and behavior discovered from the current implementation.

## Design Decisions Made

- The package uses a single global `Brain` instance as the runtime state for prompts, memory, and history. This keeps the API very lightweight but makes the package stateful and implicit.
- Provider-specific logic is isolated behind `Gemini` and `ollama` model types rather than being embedded directly in the top-level module.
- The package intentionally favors a simple conversation wrapper over a more abstract service layer or dependency injection pattern.
- A rejected alternative was keeping all provider code inline in the entry module; the current structure is more maintainable and easier to extend.

## Verification

I confirmed the implementation by reading the current package source directly:

- `src/AskAI.jl`
- `src/brain.jl`
- `src/models.jl`
- `readme.md`

I also checked the repo state and commit history with:

```bash
git -C /home/coder/forks/AskAI --no-pager log --oneline -10

git -C /home/coder/forks/AskAI status --short
```

This showed the repository is a normal package repo with a recent commit history and no code changes made during this review pass.

## Known Limitations

- The runtime is highly stateful and relies on a global `Brain`, which makes concurrent or multi-session use awkward.
- The configuration is environment-driven and uses a single string format (`provider|model|apiOrURL`), which is brittle if inputs contain extra pipes or formatting issues.
- Response handling and memory summarization are simple and heuristic rather than strongly structured or validated.
- The `@AI` macro assumes a `Main.playground` module exists, so missing setup produces a warning message rather than a hardened runtime error.

## Todos

- Completed: none
- Created: none

## Next Steps

1. Decide whether this package should stay stateful and REPL-centric or be refactored toward a more explicit instance-based API.
2. If the package is to be extended, add a small test suite around `setapi`, `@ai`, and provider-specific response parsing.
3. Consider documenting the flow of `Brain.memory`, `Brain.history`, and `Brain.RAG` for future maintainers.
4. If another provider is added, follow the same pattern already used by the `Gemini` and `ollama` model wrappers.
