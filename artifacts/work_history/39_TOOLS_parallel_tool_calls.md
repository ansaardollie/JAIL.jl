# Parallel tool calls, grouped streaming line, julia_source_module for unloaded packages

| Field | Value |
|-------|-------|
| Artifact | `39_TOOLS_parallel_tool_calls.md` |
| Category | work_history |
| Subject | `TOOLS` — parallel tool calling and concurrent execution |
| Date | 2026-10-06 |
| Area/Purpose scope | tool loop, request bodies, ToolSpec, streaming display, built-in source tools, docs |
| Related | `design_decisions/45_TOOLS_parallel_tool_calls.md`, `38_DEBUG_save_http_exchanges.md` |

## Scope of This Unit of Work

Previous artifact (`38_...`) left live checks pending (untouched). The owner asked for parallel
tool/function calling, on by default behind a Preference; then for a compact streaming display of
parallel calls, and for `julia_source_module` to find packages that aren't loaded.

## What Changed

| File | Change |
|-------|--------|
| `src/ontology/requests.jl` | `_Request.parallel_tool_calls::Bool` (13th field) |
| `src/chat.jl` | `_parallel_tool_calls(p)` (provider pref > top-level > true); `_complete` passes it; tool loop picks `_run_calls` (old sequential body) or `_run_calls_concurrently`; `_tool_scope`; events `_RunningTogether`, `_ToolsFinished`; `_print_tool(io, ::_RunningTogether)`; `chat!` docstring |
| `src/tools.jl` | `_run_tool` split into `_prepare_tool` (checks + confirmation) and `_invoke_tool`; `concurrent` kw on `_tool_spec`/`register_tool!`/`@tool`; docstrings |
| `src/ontology/tools.jl` | `ToolSpec.concurrent::Bool` (9th field); `show` prints "runs alone" |
| `src/providers/{openai,openai_compatible,anthropic}.jl` | send `parallel_tool_calls: false` / `tool_choice {auto, disable_parallel_tool_use: true}` only when off and tools present (spec lines cited) |
| `src/tokens.jl` | `_Request(..., true)` |
| `src/builtin_tools/*.jl` | `concurrent = false` for ask_user, execute_julia_code, pkg_add, add/remove_memory, tool_load, edit tools except create_directory |
| `src/builtin_tools/source.jl` | `julia_source_module`: unresolved root name → loaded copy in `Base.loaded_modules`, else `identify_package`/`locate_package`; else error; `_dir_files`, `_package_files`, `_root_name` |
| `src/repl/chat_mode.jl` | `_display_turn` handles `_RunningTogether` (one `→` line / status) and `_ToolsFinished` |
| `docs/src/guide/{tools,chat,providers,repl}.md`, `docs/make.jl`, `examples/LocalPreferences.toml` | Parallel tool calls section, Preference rows, streaming notes, `__clear__` key |
| `examples/parallel_tool_calls.jl` | new: offline scripted model, parallel vs off, streaming, misuse |

## Design Decisions Made

`design_decisions/45_TOOLS_parallel_tool_calls.md` (scope, preference layout, threads with
`@async` fallback, public `concurrent` opt-out, one flag; display rule). Rejected: internal-only
serial list, explicit `parallel_tool_calls: true`, separate Preferences, `chat!` keyword.

## Verification

REPL, mock Responses server, 8 threads:
```
on:  a start 6.48 / b start 6.48 / a end 7.48 / b end 7.48 (alone ran first); results ["c1","c2","c3"]; body parallel_tool_calls: -
off: sequential 2.32 s; body parallel_tool_calls: false
anthropic override: true, openai: false
ArgumentError: Preference `providers.anthropic.parallel_tool_calls` must be true or false, got "yes"
d1 true `boom` threw an error: kaboom / d2 true Unknown tool `nope` / d3 false A done
```
Streaming (`_display_turn`, tty = false):
```
→ alone
→ weather (Paris)  → weather (Rome)
Done.
┏ Tool calls (4): ✓ weather ✓ weather ✓ alone ✗ nope
```
`julia_source_module`: `SparseArrays`, `Distributed`, `DelimitedFiles`, `SparseArrays.HigherOrderFns`
found while unloaded (still unloaded after); `JuliaSyntax.Tokenize` found via the loaded copy;
`NotAPkgXYZ` → "`NotAPkgXYZ` is not defined in Main and is not a package in the active environments".
Example ran top to bottom (output in chat). Docs build: no warnings.

Not verified: live providers; `@async` path (`julia -t 1`); alternate-screen display in a real
terminal; a confirmation-needing call inside a parallel batch.

## Known Limitations

- Ctrl-C during a batch ends the turn but running calls finish in the background.
- Alone-calls run before the batch, not in model order.
- Unknown/invalid calls in a parallel round show no streamed line (only the Tool calls box).
- `julia_source_module` for an unloaded package searches only its own `src` tree.

## Todos

- Completed: none
- Created: `todos/pending/11_TOOLS_live_check_parallel_tool_calls.md`

## Next Steps

- `todos/pending/11_TOOLS_live_check_parallel_tool_calls.md`, then
  `todos/pending/10_TOOLS_live_check_tool_search.md`.
- API friction noted while writing the example: no public setter for `parallel_tool_calls`.
