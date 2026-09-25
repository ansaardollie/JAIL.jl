# PromptingTools.jl library inventory

| Field | Value |
|-------|-------|
| Artifact | `4_PROMPTINGTOOLS_library_inventory.md` |
| Category | work_history |
| Subject | `PROMPTINGTOOLS` - vendored PromptingTools.jl API knowledge |
| Date | 2026-09-25 |
| Area/Purpose scope | dependency inventory, API reference, usage guidance |
| Related | `artifacts/lib_inventories/PromptingTools/1_PROMPTINGTOOLS_api_inventory.md`, `artifacts/lib_inventories/PromptingTools/2_PROMPTINGTOOLS_usage_guide.md`, `artifacts/work_history/3_OPENAI_library_inventory.md` |

## Scope of This Unit of Work

The previous work-history artifact documented the vendored OpenAI.jl dependency. This unit studied the vendored `libs/PromptingTools.jl` package and recorded its exported API, message/schema architecture, provider dispatch families, intended usage, extension points, experimental modules, and limitations for future JAIL work.

## What Changed

| File | Change |
|------|--------|
| `artifacts/lib_inventories/PromptingTools/1_PROMPTINGTOOLS_api_inventory.md` | Added a static API inventory for PromptingTools.jl 0.94.0, covering top-level exports, message types, schemas, provider dispatch, tools/extraction, model registry, serialization, streaming, and experimental modules. |
| `artifacts/lib_inventories/PromptingTools/2_PROMPTINGTOOLS_usage_guide.md` | Added usage guidance for the `ai*` pipeline, templates, conversations, memory, structured extraction, local/compatible providers, streaming, extension points, naming conventions, and sharp edges. |
| `/memories/repo/promptingtools.md` | Recorded the compact repository-scoped architecture digest for future sessions. |

## Design Decisions Made

- The inventory separates the actually exported top-level API from semi-public message, schema, registry, serialization, and provider symbols. The rejected alternative was presenting every dispatch-visible name as equally public, which would misstate the package's intended surface because only a small set is exported from `src/PromptingTools.jl`.
- Provider implementations are grouped by schema and source module rather than copying every overload. The rejected alternative was duplicating the entire multiple-dispatch surface, which would be difficult to read and become stale as provider methods change.
- No standalone design-decision artifact was created. The choices were documentation-scope decisions, not an application architecture or public API decision.

## Verification

The package load was verified through the Julia REPL with:

```julia
using JAIL
println("JAIL loaded: ", nameof(JAIL))
```

Actual REPL output:

```text
REPL mode askai initialized. Press } to enter and backspace to exit.
JAIL loaded: JAIL

```
nothing
```
```

The artifact files were checked for non-empty output and expected sections:

```text
1_PROMPTINGTOOLS_api_inventory.md 15077 bytes
2_PROMPTINGTOOLS_usage_guide.md 10360 bytes
```

`git diff --check` completed without whitespace errors, and Markdown diagnostics reported no errors for either inventory file.

## Known Limitations

- No live provider calls were made. The inventory is based on static source, package metadata, README/docs, and changelog material; credentials, network access, current provider behavior, and pricing were not verified.
- Every provider overload, model alias, and experimental operation is not reproduced inline. The authoritative implementations remain under `libs/PromptingTools.jl/src/llm_*.jl`, `src/user_preferences.jl`, `src/extraction.jl`, and `src/Experimental/`.
- Optional GoogleGenAI and Markdown extension behavior was documented from source but not exercised.
- The repository-memory file is outside the Git worktree and is not part of the commit.

## Todos

- Completed: none.
- Created: none.

## Next Steps

1. Use the distinction between `ai*` orchestration, message types, and provider schemas when integrating PromptingTools with JAIL.
2. Refresh this inventory if `libs/PromptingTools.jl` is upgraded or its provider/schema surface changes.
3. For runtime integration work, add focused tests using the package's echo schemas or local fake endpoints before relying on live provider calls.
