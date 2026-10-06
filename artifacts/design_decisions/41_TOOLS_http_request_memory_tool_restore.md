# Decision: `http_request` + `url_allow_list`, session memory tools, restoring a session's tools

| Field | Value |
|-------|-------|
| Artifact | `41_TOOLS_http_request_memory_tool_restore.md` |
| Category | design_decisions |
| Subject | `TOOLS` |
| Date | 2026-10-06 |
| Area/Purpose scope | built-in tools (`web`, new `memory` group); session persistence |
| Related | `31_TOOLS_builtin_tools_policy.md`, `32_TOOLS_builtin_tools_groups_and_rules.md`, `35_TOOLS_allow_lists_remove_file_response_header.md`, `24_SESSION_persistence.md` |
| Status | accepted |
| Decided by | user (features, `:high` default, allow-list, memory file location and the three memory tools); agent (details listed, within the user's request) |

## Context

User asked for: an `http_request(url, method, query_params, body, headers)` tool, `:high` by
default, with a `url_allow_list` of URL prefixes that auto-approve; per-session memory as a
Markdown numbered list under `<storage_dir>/memory/sessions/<session id>` with `read_memory()`,
`add_memory(input)`, `remove_memory(number)`; and restored sessions getting their tools back
(saved `"tools": null` lost which tools were registered, so a restored session answered
"Unknown tool `read_memory`").

## Decision

Agent-decided:

- `http_request` in group `web`. Methods GET/HEAD/POST/PUT/PATCH/DELETE/OPTIONS; `http`/`https`
  only. `query_params`/`headers` are `Dict{String,String}` (JSON object schema with
  `additionalProperties`). Query params escaped and appended (`&` if the URL has a query).
  **No redirects followed, no retry, no cookies**: an allow-listed URL can't bounce a POST to
  an unapproved host; the 3xx comes back with `Location`. Returns `HTTP <status>`, headers,
  blank line, body (binary described, not returned). Preview: method, full URL, headers, body.
- `url_allow_list` match: plain string prefix **at a boundary** (entry ends in `/`, or URL
  continues with `/ ? #` or ends). Never allow-listed: userinfo, backslash, whitespace/control
  chars, `.`/`..` segments after percent-decoding the path. Case-sensitive.
- Memory group `memory`, all `:low` (only the calling session's file). File
  `<storage_dir>/memory/sessions/<id>.md` (agent added `.md`). Session = `tool_context()`
  session, else `active_session()`. **Numbers are stable**: removal leaves a gap, next = max+1,
  so numbers the model already saw keep meaning the same memory. Line breaks in `input`
  become spaces. Deleted by `_delete_files!` with the session's other files.
- Tool restore: session JSON gains `available_tools` (names of `tools(s)` at each save). On
  `_load_session`, built-ins named in `tools` ∪ `available_tools` that aren't registered are
  registered via `register_builtin_tools!`; other missing names get one warning (functions
  can't be rebuilt from disk). `tools` semantics (`null` = every registered tool) unchanged.

## Rejected

- Following redirects for `http_request` (same-level check as `fetch_url`): a body/method may
  be resent to a host the user never approved.
- Plain `startswith` allow-list matching (`https://api.x.com` would cover `api.x.com.evil.org`).
- Renumbering memories after a removal (shifts numbers the model is holding).
- Converting a restored `tools = null` session to an explicit list (changes its semantics:
  tools registered later would no longer be offered).

## Revisit Trigger

Users want redirects followed, host/method-aware allow rules, renumbered memory lists, or
user-defined tools restorable (e.g. a tool registry hook at load).
