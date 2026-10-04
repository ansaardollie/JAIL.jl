# Decision: Sessions persist to disk as JSON + JSON Lines; restore from a menu

| Field | Value |
|-------|-------|
| Artifact | `24_SESSION_persistence.md` |
| Category | design_decisions |
| Subject | `SESSION` |
| Date | 2026-10-04 |
| Area/Purpose scope | public API, data model, Preferences, REPL surface |
| Related | `10_SESSION_registry_and_default_session.md` (revisit trigger met), `21_PROVIDER_google_enterprise_generate_content.md` (thought signatures), `12_MESSAGES_types_and_chat.md` |
| Status | accepted |
| Decided by | user (format, layout, ids, restore surface, all items in the Q&A table); agent (file formats in detail, write strategy, failure handling) |

## Context

User request: serialise `Session`s to/from disk. Requirements given verbatim: JSON for the
session, JSON Lines for its messages, separate artifacts; a Preference-keyed folder defaulting to
`.jail` in the working dir; UUID v7 ids so file names sort by creation, with the timestamp also on
the object; the messages file has the session's file name in another folder; append-only write on
every new message to keep chat latency low; tool calls/results stored as objects, not JSON text;
restore from Julia and from the model REPL mode via a terminal menu showing name + timestamp +
truncated first user message.

## The Questions and Answers

| Question | Options | Chosen |
|---|---|---|
| Automatic? | always on + `persist_sessions = false` / opt-in Preference / per-session flag | **always on**, Preference `persist_sessions = false` disables |
| Folder Preference + layout | `session_dir` / `storage_dir` | **`storage_dir`**, `<dir>/sessions/<uuid>.json` + `<dir>/messages/<uuid>.jsonl` |
| First write | first message / creation | **first message** (empty sessions, e.g. each startup `default`, leave no files) |
| Restore names | `restore_session!` + `session restore` / `load_session!` + `session load` | **`restore_session!`, `session restore`** |
| `delete_session!` and files | never / always / opt-in kwarg | **`delete_session!(s; files = true)`** |
| New fields | `created` / `created_at` | **`id::UUID` (v7), `created::DateTime` (UTC)** |

## Decision

```julia
s.id         # Base.UUID, version 7; its timestamp equals s.created
s.created    # DateTime, UTC
restore_session!()                 # menu of saved sessions, newest first; activates; nothing if cancelled
restore_session!(id)               # UUID or its string
delete_session!(s; files = true)   # also removes its two files
```

```
model> session restore
```

```toml
[JAIL]
storage_dir = ".jail"        # relative paths resolve against pwd() at the session's first write
persist_sessions = true
```

Agent-decided:

- Session file: `{"version":1,"id","name","created":"…Z","model":"provider/id"|null,"system","tools":null|[names]}`.
  Rewritten atomically (tmp + `mv`) when its content changes, checked on every sync (so direct field
  edits are picked up) and on `set_model!` / `set_tools!`.
- Messages file: one object per line, `{"role":"user"|"assistant"|"tool","content":[parts], …}`;
  assistant lines add `model`, `stop_reason`, `usage`, `id` when set. Parts:
  `{"type":"text","text"}`, `{"type":"tool_call","id","name","arguments":{…}}`,
  `{"type":"tool_result","call_id","name","content","is_error"}`. A tool result whose text is a
  JSON object/array/number that re-serialises identically is stored as that value; otherwise as
  the string.
- New messages are appended (open `"a"`, write, close). When the history shrank (`empty!`, a failed
  turn rolled back by `chat!`) the file is rewritten in full.
- A session's folder is fixed at its first write, so a later `cd` doesn't split its files.
- Disk errors are logged with `@warn`, never thrown into a chat turn.
- Restored model strings resolve through the current Preferences; an unresolvable one leaves the
  session (or message) with `model = nothing` and a warning. Tool names are restored without
  validation (`tools(s)` already skips unregistered names).
- Restoring an id that is already loaded just activates that session.

## Amendment (2026-10-04, user request): names are not unique

User: "remove the unique constraint and the adding a increasing int to the name as this making
the session names weird". Supersedes the auto-suffix rule of decision 10.

- `Session(...; name)` keeps the name as given; the `id` is the identity.
- `use_session!`, `delete_session!` (and `session use` / `session rm`) accept a `Session`, a
  `UUID`, a UUID string (looked up as an id), or a name. Several sessions sharing a name open a
  terminal menu in both Julia calls and the REPL (user: "there should be menu to choose amongst
  the matches in both model repl and imperative code"); cancelling returns `nothing`.
  Rejected: error listing ids; pick the most recent.
- Agent-decided: a name that parses as a UUID is rejected so names and ids can't collide; the
  `sessions` listing now shows creation time and id.
- Google thought signatures (decision 21's revisit trigger) are stored on the `tool_call` part
  as `thought_signature` and put back in the private table on restore.
- UUID v7 from `UUIDs.uuid7()` (user request, 2026-10-04: "use the implementation provided by
  `UUIDs.uuid7()`"). Adds the `UUIDs` stdlib dependency and raises the `julia` compat to 1.12,
  where `uuid7` was added. An earlier in-package generator (strictly increasing within a process)
  was removed; ids made in the same millisecond may now sort in either order.
- Chain state (`previous_response_id`) is not persisted: the first turn after a restore replays
  the full history.

## Consequences

- Every chatting session leaves files under `.jail/` in the working directory; users may want it
  in `.gitignore`.
- Editing `s.messages` in place (not shrinking it) is not detected; the file keeps the old text.

## Revisit Trigger

Large histories making the full rewrite on rollback noticeable; a need to edit history in place;
multiple processes writing the same session.
