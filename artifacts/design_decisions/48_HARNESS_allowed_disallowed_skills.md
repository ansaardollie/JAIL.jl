# Decision: `allowed_skills` / `disallowed_skills` Preferences filter skills everywhere

| Field | Value |
|-------|-------|
| Artifact | `48_HARNESS_allowed_disallowed_skills.md` |
| Category | design_decisions |
| Subject | `HARNESS` |
| Date | 2026-10-08 |
| Area/Purpose scope | skills discovery, Preferences |
| Related | `46_HARNESS_agent_mode_agents_and_skills.md`, `3_PREFERENCES_nested_layout.md` |
| Status | accepted |
| Decided by | user (scope, conflict rule, matching); agent (top-level keys, no setter) |

## Context

User: "add the ability to set via preferences one of two mutually exclusive array keys
(`allowed_skills` or `disallowed_skills`) which will either whitelist or blacklist skills from the
agent mode."

## Decision

- Top-level Preference keys `allowed_skills` and `disallowed_skills`: lists of skill names.
- Filter applied inside `skills()`, so a filtered skill is gone **everywhere**: `skills()`, the
  model's catalogue and `skill_<name>` tools, `/name` and `run_skill!`, the `|` mode listing and
  `edit_skill`.
- Exact name match; applies to every same-named skill across folders. Unknown names are ignored.
- Both set: warn once, `allowed_skills` wins.
- Not a list of strings: `ArgumentError` (same as other list Preferences).
- No Julia setter; set by hand (agent decision, like `loaded_tools`).

Rejected:
- Agent mode only (keep `skills()` unfiltered, mark filtered entries) — user chose everywhere.
- Model catalogue only (user can still `/name`) — user chose everywhere.
- Error when both set; ignore both when both set — user chose allowed wins.
- Glob patterns (`"python-*"`) — user chose exact names.

## Consequences

A disallowed skill can't be opened with `edit_skill`; edit the file directly or lift the filter.

## Revisit Trigger

Owner wants per-session or per-agent skill filters, glob patterns, or filtered skills still
editable/listed.
