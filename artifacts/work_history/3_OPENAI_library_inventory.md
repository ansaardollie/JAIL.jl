# OpenAI.jl library inventory

| Field | Value |
|-------|-------|
| Artifact | `3_OPENAI_library_inventory.md` |
| Category | work_history |
| Subject | `OPENAI` - vendored OpenAI.jl API knowledge |
| Date | 2026-09-25 |
| Area/Purpose scope | dependency inventory, API reference, usage guidance |
| Related | `artifacts/lib_inventories/OpenAI/1_OPENAI_api_inventory.md`, `artifacts/lib_inventories/OpenAI/2_OPENAI_usage_guide.md` |

## Scope of This Unit of Work

The previous work-history artifact, `2_JAIL_misconfig_hang_fix.md`, left the repository with the vendored `OpenAI.jl` dependency present but undocumented for future JAIL work. This unit studied `libs/OpenAI.jl` and recorded its public API, generated-client structure, intended usage, extension points, and limitations.

## What Changed

| File | Change |
|-------|--------|
| `artifacts/lib_inventories/OpenAI/1_OPENAI_api_inventory.md` | Added a static API inventory for OpenAI.jl 0.13.0, covering providers, request helpers, handwritten endpoints, streaming, legacy assistants/thread/message/run helpers, generated API groups, generated model conventions, visibility, and source paths. |
| `artifacts/lib_inventories/OpenAI/2_OPENAI_usage_guide.md` | Added usage guidance for handwritten calls, provider overrides, StreamCallbacks streaming, generated typed clients, extension points, naming conventions, and sharp edges. |
| `/memories/repo/openai_jl.md` | Recorded the compact repository-scoped architecture digest for future sessions. |

## Design Decisions Made

- The inventory separates the handwritten convenience API from the generated `OpenAIClient` because they have different input and output contracts. The rejected alternative was presenting them as one uniform API, which would hide the distinction between `OpenAIResponse`/JSON3 results and generated typed-model plus `ApiResponse` results.
- The generated surface is indexed by its authoritative include/export files and grouped by API concern rather than reproducing hundreds of generated names inline. The rejected alternative was copying every generated model and endpoint signature into the artifact, which would duplicate generated source and become stale quickly.
- No standalone design-decision artifact was created because these choices are documentation-scope decisions, not a new application architecture or public API decision.

## Verification

Package loading was verified through the Julia REPL with:

```julia
using JAIL
println("JAIL loaded: ", nameof(JAIL))
```

The actual REPL output was:

```text
REPL mode askai initialized. Press } to enter and backspace to exit.
JAIL loaded: JAIL

```
nothing
```
```

The source inventory was cross-checked against `libs/OpenAI.jl/Project.toml`, `README.md`, `AGENTS.md`, `src/OpenAI.jl`, `src/assistants.jl`, `src/generated/OpenAIClient.jl`, representative generated model/API files, `docs/src/`, `CHANGELOG.md`, examples, tests, and the OpenAPI regeneration script. Git status before housekeeping showed only the new untracked `artifacts/lib_inventories/` directory.

## Known Limitations

- The generated model and operation names are not duplicated in full; their authoritative catalogs remain in `libs/OpenAI.jl/src/generated/OpenAIClient.jl`, `modelincludes.jl`, `models/`, and `apis/`.
- No live OpenAI API calls were made during this inventory. The vendored package tests are mostly live-API oriented and require `OPENAI_API_KEY`, network access, and model availability.
- The repository-memory file is outside the Git worktree and is not part of the commit.
- Existing follow-up items from the previous JAIL work-history artifact, including HTTP compatibility bounds, memory handling, `setapi` validation, and automated fake-server tests, remain future work and were not changed here.

## Todos

- Completed: none.
- Created: none.

## Next Steps

1. Use the generated-client and handwritten-layer distinction when adding OpenAI support to JAIL.
2. Refresh the inventory if `libs/OpenAI.jl` is upgraded or regenerated from a new OpenAPI snapshot.
3. For runtime integration work, add focused local tests before relying on the vendored package's live API tests.
