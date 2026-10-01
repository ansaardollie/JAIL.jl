# TODO: providers() throws on a google_enterprise table with no project

| Field | Value |
|-------|-------|
| Artifact | `6_PROVIDER_google_enterprise_partial_prefs.md` |
| Category | todos |
| Subject | `PROVIDER` |
| Date created | 2026-10-01 |
| Area/Purpose scope | configuration, REPL surface |
| Related | `work_history/17_PROVIDER_google_enterprise_generate_content.md` |
| Priority | medium |
| Owner | any |

## What

`set_default_model!(GoogleEnterprise(project = ..., location = ...), id)` saves only
`providers.google_enterprise.default_model` when no project/location is saved yet.
`providers()` then sees a `google_enterprise` key, calls `GoogleEnterprise()` and throws
"GoogleEnterprise needs a project". The `|` mode's `providers` listing and `select_model!` break.

Reproduced (Preferences saved and restored):

```
set_default_model!(GoogleEnterprise(project = "my-project", location = "global"), "gemini-2.5-flash")
providers()   # ArgumentError: GoogleEnterprise needs a project; ...
```

Options: `providers()` / `_provider` skip a `google_enterprise` table without `project`, or
`set_default_model!(p::GoogleEnterprise, id)` also saves `p`'s connection settings. The second
changes what that function writes, so ask the owner.

## Acceptance Criteria

- [ ] `providers()` never throws because of a partial `google_enterprise` table
- [ ] Docs caveat in `docs/src/guide/providers.md` ("Save `project` and `location` before ...") removed or updated
- [ ] Verified in the REPL with Preferences saved and restored
