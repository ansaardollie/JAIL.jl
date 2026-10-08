# Memory tools: session and agent scopes, loaded when an agent is applied

| Field | Value |
|-------|-------|
| Artifact | `45_TOOLS_memory_scopes_and_agent_loading.md` |
| Category | work_history |
| Subject | `TOOLS` |
| Date | 2026-10-08 |
| Area/Purpose scope | built-in tools (`memory` group), harness agent mode (`use_agent!`), docs, examples |
| Related | `design_decisions/49_TOOLS_memory_session_and_agent_scopes.md`, `design_decisions/50_TOOLS_memory_tools_loaded_for_agent_sessions.md`, `work_history/44_HARNESS_allowed_disallowed_skills.md`, `todos/pending/13_TOOLS_memory_follow_ups.md` |

## Scope of This Unit of Work

Follows `44_...` (commit `67ff295`). Two requests: split the memory tools into a session scope and
an agent scope (decision 49), then load all memory tools in agentic sessions and document the
changes against the jail-developer principles (decision 50). The previous `memory` group was
`read_memory`, `add_memory`, `remove_memory`.

## What Changed

| File | Change |
|-------|--------|
| `src/builtin_tools/memory.jl` | Six tools: `read_session_memory`, `add_session_memory`, `remove_session_memory`, `read_agent_memory`, `add_agent_memory`, `remove_agent_memory`. Helpers `_session_memory_path`, `_agent_memory_path` (validates the name), `_current_memory_path(scope)`, `_add_memory!`, `_remove_memory!`, `_memory_text`. All `:low`. Add and remove are `concurrent = false`. |
| `src/builtin_tools/common.jl` | `"memory"` row in the group table lists the six names |
| `src/harness/agent.jl` | `use_agent!` appends the registered `memory` group tools to `s.loaded_tools` when a file agent is applied. The built-in `julia` agent is excluded. `use_agent!(s, nothing)` keeps them. Docstring updated. |
| `src/persistence.jl` | `_delete_files!` removes the session memory file via `_session_memory_path` |
| `docs/src/guide/agents.md` | Agent memory section: path, shared list, `delete_session!` keeps the file, refused names, loading on apply |
| `docs/src/guide/tools.md` | Memory section (scopes, numbering, delete, `:low`); built-in table rows; parallel-calls paragraph lists the add and remove tools |
| `docs/src/guide/sessions.md` | saved-files list and delete note |
| `docs/src/builtin_tools.md` | memory section with the six names |
| `docs/src/guide/repl.md` | `tools:` line updated; lead-in now says the transcript is illustrative |
| `examples/agents.jl` | header line; two `@show` lines for the loaded memory tools |
| `examples/memory.jl` | new: offline scripted run of both scopes, agent memory across two sessions, and an error case |
| `artifacts/design_decisions/49_TOOLS_memory_session_and_agent_scopes.md` | new, accepted |
| `artifacts/design_decisions/50_TOOLS_memory_tools_loaded_for_agent_sessions.md` | new, accepted |

Behaviour, not diffs: session memory is `<storage_dir>/memory/sessions/<id>.md`. Agent memory is
`<storage_dir>/memory/agents/<name>.memory.md`, shared by every session that uses the agent and by
any agent file with the same name. Agent memory is not in the system prompt; the model reads it
with `read_agent_memory`. Numbering reuses max + 1 after removal.

## Design Decisions Made

- Decision 49: two scopes, separate tools per scope, no session argument on the tools.
- Decision 50: memory tools are loaded in the session's `loaded_tools` on `use_agent!`. Rejected:
  loading only inside agent turns (not saved with the session; recomputed each turn), and a
  Preference that loads them by default (changes plain chat sessions too). The code reads `_TOOLS`
  rather than the strict `load_tools!`, so an excluded `memory` group loads nothing without error.

## Verification

Module load, run after the last source change:

```
loaded JAIL OK
```

`examples/memory.jl` final run (`include` via the REPL):

```
filter((n->begin
            #= /Users/ansaardollie/Workspaces/Julia/JAIL.jl/examples/memory.jl:70 =#
            endswith(n, "_memory")
        end), s.loaded_tools) = ["remove_agent_memory", "read_agent_memory", "remove_session_memory", "add_agent_memory", "add_session_memory", "read_session_memory"]
← add_session_memory:
1. Keep the public API unchanged.
← add_agent_memory:
1. Use four-space indents.
← read_agent_memory:
1. Use four-space indents.

← remove_agent_memory:
`remove_agent_memory` threw an error: ArgumentError: there is no memory number 9

```
nothing
```
```

The second session reads the agent file written by the first session, so agent memory is shared as
documented. Session memory from the first session does not appear in the second.

`examples/agents.jl` (earlier run, before the docstring reflow): `include` completed. The memory
check printed `6` after `use_agent!(s, nothing)`. The exact REPL output of the earlier six-name
check (after `use_agent!(s, "jail-developer")`, after `use_agent!(s, nothing)`, and for the built-in
`julia` agent) is not retained; the summary above is what was observed. The `use_agent!` docstring
reflow after that run changed no code.

`get_errors` on `src/harness/agent.jl`: no errors.

Docs build, `jd docs/make.jl` (after all edits, with the `repl.md` lead-in change):

```
[ Info: SetupBuildDirectory: setting up build directory.
[ Info: Doctest: running doctests.
[ Info: ExpandTemplates: expanding markdown templates.
[ Info: CrossReferences: building cross-references.
[ Info: CheckDocument: running document checks.
[ Info: Populate: populating indices.
[ Info: RenderDocument: rendering document.
[ Info: HTMLWriter: rendering HTML pages.
[ Info: Automatic `version="1.0.0"` for inventory from ../Project.toml
build exit: 0
```

The grep for `warn|error` over the build output returned no lines (exit 1 from grep).

Not verified: the `registered_tools` exclusion of the memory group (expected to load nothing without
error, not run). No test suite exists (0 tests). The real-terminal check of the memory tools' output
in the REPL chat.

## Known Limitations

- Memory tools take no session argument. They act on the session of the tool call, or the active
  session when called directly. This conflicts with the explicit-instance principle (todo 13, item 1).
- Sessions that call `agent!` without applying a file agent (the built-in `julia` agent) do not get
  the memory tools (decision 50).
- Agent memory is shared by every session using the agent, and by agent files with the same name.
- Remove by number: after removal, numbers are not renumbered; the next add uses max + 1.
- `examples/memory.jl` prints a trailing `nothing` because `include` returns the last value. Cosmetic.
- `examples/agents.jl` gives `Assignment to s in soft scope` when included at REPL top level. This
  predates this unit.
- `docs/src/guide/repl.md` transcript is illustrative and was not captured from a live session.
  Stale fields: `system` (970 chars in the transcript; 976 in the current code), `thinking`
  (Preference-dependent), `reasoning` (hidden in the transcript; shown in the current run),
  `loaded` (none in the transcript; the six memory tools after an agent is applied).

## Drift Found and Resolved

- `tools.md` said numbers are never reused. Corrected to max + 1.
- `repl.md` lead-in claimed a live capture. Reworded as illustrative.
- `use_agent!` docstring line too long. Reflowed.
- `sessions.md`, `agents.md`, `tools.md`, `builtin_tools.md`: checked against `memory.jl`,
  `persistence.jl`, and `agent.jl`; consistent.
- The `tools.md` parallel-calls paragraph: add and remove tools run alone (`concurrent = false`),
  consistent with `memory.jl`.

## Todos

- Completed: none.
- Created: `todos/pending/13_TOOLS_memory_follow_ups.md` (session-argument decision, `repl.md`
  transcript regeneration, `julia` agent memory decision).
- Pending `12_HARNESS_live_checks_and_gates.md` is unchanged; the real-terminal memory check is not
  in its scope.

## Next Steps

1. Owner: decide item 1 and item 3 in `todos/pending/13_TOOLS_memory_follow_ups.md`.
2. Run a live provider session and regenerate the `repl.md` transcript; update the lead-in to match.
3. Run the `registered_tools` exclusion check: set the Preference `registered_tools` to `[]`, call
   `use_agent!` on a file agent, and confirm `s.loaded_tools` gains no memory names and no error is
   raised. Restore the Preference afterwards.
