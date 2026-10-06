# Decision: Saving HTTP exchanges when JULIA_DEBUG includes JAIL

| Field | Value |
|-------|-------|
| Artifact | `44_DEBUG_save_http_exchanges.md` |
| Category | design_decisions |
| Subject | `DEBUG` |
| Date | 2026-10-06 |
| Area/Purpose scope | HTTP layer, persistence |
| Related | `24_SESSION_persistence.md` |
| Status | accepted |
| Decided by | user (switch, paths, url/headers/body, no Authorization); agent (details listed) |

## Context

User: "save HTTP requests/responses when `JAIL` is included in the `JULIA_DEBUG` env var ...
under `<storage_dir>/debug/<session_id>/<turn_id>/request.json` and `.../response.json` and
include url/headers/body however the authorisation header should be removed."

## Decision

Agent-decided:

- `<turn_id>` = a UUID v7 per HTTP request (a tool-using `chat!` turn makes several requests;
  fixed file names would overwrite each other).
- Switch: `JULIA_DEBUG` entries `JAIL` or `all`, not `!JAIL`; read per request.
- Also removed: `x-api-key` (Anthropic) and `x-goog-api-key` (Google), case-insensitive.
- Session from a ScopedValue set by `_chat!` and `count_tokens`; requests without one (model
  listing) are only logged. Written regardless of `persist_sessions`; removed by
  `delete_session!(s; files = true)`.
- Response `body`: parsed JSON when it parses, else text; a stream as `[{event, data}]`.

## Rejected

- One folder per `chat!` turn with numbered files (doesn't match the requested names).
- Removing only `Authorization` (would save Anthropic/Google keys).

## Revisit Trigger

Owner wants per-turn grouping, model-listing requests saved, or a Preference instead of
`JULIA_DEBUG`.
