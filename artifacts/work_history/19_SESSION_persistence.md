# Session persistence (JSON + JSON Lines), UUID v7 ids, non-unique session names

| Field | Value |
|-------|-------|
| Artifact | `19_SESSION_persistence.md` |
| Category | work_history |
| Subject | `SESSION` |
| Date | 2026-10-04 |
| Area/Purpose scope | public API, data model, Preferences, REPL surface, docs |
| Related | `design_decisions/24_SESSION_persistence.md` (incl. amendment), `design_decisions/10_SESSION_registry_and_default_session.md` (partly superseded), `design_decisions/21_PROVIDER_google_enterprise_generate_content.md` (revisit trigger met) |

## Scope of This Unit of Work

Owner requests, in order: (1) serialise `Session`s to disk — session as JSON, messages as JSON
Lines, Preference-keyed folder (default `.jail`), UUID v7 ids + timestamp on the object, append-only
message writes, tool calls/results as objects, restore via terminal menu from Julia and the `|`
mode; (2) use `UUIDs.uuid7()` instead of an in-package generator; (3) drop unique session names and
the `-2` suffix. Previous work history (`18_AGENT_planning_agent.md`) was unrelated agent tooling.

## What Changed

| File | Change |
|-------|--------|
| `src/persistence.jl` (new) | Encoding/decoding of sessions and messages; `_sync!` (meta rewrite on hash change + append new messages, full atomic rewrite when history shrank); `_guard` (disk errors → `@warn`); `_load_session`, `_saved_sessions`, `_first_prompt`; public `restore_session!()` (menu) / `restore_session!(id)`. Thought signatures saved on `tool_call` parts. |
| `src/session.jl` | `Session` gains `const id::UUID` (`uuid7()`), `const created::DateTime` (from the id), private `_store::_SessionStore`. Names no longer unique; `_session(x, term)` resolves `Session` / `UUID` / UUID string / name (menu via `_pick` when shared). Names that parse as a UUID are rejected. `delete_session!(x; files = false)`. `set_model!`, `set_tools!`, `empty!` sync to disk. `_session_rows` for listings. |
| `src/chat.jl` | `_sync!` after each push in `_chat!` / `_tool_loop!`; rollback resyncs, or deletes files when the failed turn was the first. |
| `src/repl/model_mode.jl` | `session restore`; `session use|rm <name|id>`; `session rm … --files`; `sessions` lists created time + id; completion dedups names. |
| `src/JAIL.jl` | `using Dates: Dates, DateTime`, `using UUIDs: UUID, uuid7, uuid_version`; export `restore_session!`; include `persistence.jl`. |
| `Project.toml` | `UUIDs` dep (compat 1.11.0); `julia` compat raised 1.10 → 1.12 (uuid7). Via Pkg. |
| `docs/src/guide/{sessions,repl,providers}.md`, `docs/src/reference.md` | Saving/restoring section, non-unique names, new REPL commands, `persist_sessions` / `storage_dir` keys. |
| `examples/session_persistence.jl` (new), `examples/sessions.jl` | Persistence walkthrough; sessions example uses ids instead of `review-2`. |
| `.gitignore` | `.jail/` (done at the owner's request for the feature, not by housekeeping). |

File format (details in decision 24): `<storage_dir>/sessions/<id>.json` (pretty, `version`, `id`,
`name`, `created` ISO `…Z`, `model` `"provider/id"`, `system`, `tools`) and
`<storage_dir>/messages/<id>.jsonl` (`{"role","content":[parts],…}`; parts `text` / `tool_call`
with `arguments` object / `tool_result` with `content` stored as JSON value when it round-trips
exactly).

## Design Decisions Made

All in `24_SESSION_persistence.md`: always-on with `persist_sessions = false` (rejected opt-in,
per-session flag); `storage_dir` (rejected `session_dir`); write on first message (rejected at
creation); `restore_session!` / `session restore` (rejected `load_session!`); `delete_session!`
keeps files unless `files = true`; fields `id` / `created` (rejected `created_at`); `UUIDs.uuid7()`
(replaced the in-package generator, which was strictly monotonic); non-unique names with a menu
for ambiguity in both Julia and REPL (rejected: error listing ids, pick most recent).

## Verification

Mock Anthropic server (`HTTP.serve!` on 127.0.0.1, temp `storage_dir`, Preferences restored):

```
isdir(joinpath(tmp, "sessions")) = false            # before first message
r2.id == id = true; r2.created == s.created = true; length(r2.messages) = 4
all(fingerprints equal after round trip) = true
countlines(mp) = 6; filesize(mp) > sz = true        # append
threw: JAIL._APIError; length(r2.messages) == n = true; countlines(mp) = 6   # rollback
empty!: filesize(mp) = 0, session json kept
crash-truncated line skipped with warning, file rewritten (countlines = 2)
failed first turn → no files; delete_session!(…; files = true) → files gone; persist_sessions=false → no files
thought_signature restored: "sig=="
```

After the UUIDs switch: `JAIL.uuid_version(s.id) = 7`, save/restore round trip `r.id == id = true`.
After non-unique names:

```
  * default  2026-10-04 02:37  openai/gpt-6-luna               0 messages  01a10458-1ead-…
    review   2026-10-04 02:37  anthropic/claude-sonnet-4-5     0 messages  01a10458-1fb7-…
    review   2026-10-04 02:37  openai/gpt-5                    0 messages  01a10458-1fc4-…
use_session!(string(b.id)) === b = true; use_session!(a.id) === a = true
menu (↓ Enter) → b; menu cancelled → nothing
ArgumentError: session name can't be a UUID (UUIDs refer to session ids), got "01a10458-…"
```

`examples/sessions.jl` ran end to end; offline parts of `examples/session_persistence.jl` ran.
**Not verified:** live provider calls; menus on a real TTY (fake terminal only); docs build —
`julia --project=docs docs/make.jl` fails with `ArgumentError: Unable to automatically determine
remote for main repo` (pre-existing, unrelated to these changes).

## Known Limitations

- In-place edits of `s.messages` that don't shrink it aren't written to disk.
- Chain state isn't persisted: first turn after restore replays full history.
- Restored model strings resolve through current Preferences (one-off provider instances come back
  as the configured provider of that name).
- `UUIDs.uuid7()` isn't monotonic within one millisecond.
- Name lookups with shared names open a menu, unusable in non-interactive scripts (use ids).
- `session rm --files` REPL flag was agent-added; owner hasn't explicitly confirmed it.
- No automated tests.

## Todos

- Completed: none.
- Created: `8_DOCS_build_git_remote.md`.

## Next Steps

1. Fix the docs build (`8_DOCS_build_git_remote.md`), then rebuild and check the sessions/REPL pages.
2. When `1_TESTS_test_suite_setup.md` is done, port the persistence checks above (mock server +
   temp `storage_dir`), and replace "naming/suffixes" there with the non-unique-name + menu rules.
3. Confirm `session rm --files` with the owner.
