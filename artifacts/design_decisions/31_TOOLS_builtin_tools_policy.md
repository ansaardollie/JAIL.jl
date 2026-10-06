> **Superseded in part by:** `42_TOOLS_tool_search_and_loaded_tools.md` (every built-in is registered at load, none loaded; Preference `builtin_tools` → `registered_tools`)

# Decision: Built-in tools — availability, names, workspace folder, Julia evaluation target, output size, secret scrubbing

| Field | Value |
|-------|-------|
| Artifact | `31_TOOLS_builtin_tools_policy.md` |
| Category | design_decisions |
| Subject | `TOOLS` |
| Date | 2026-10-05 |
| Area/Purpose scope | public API, Preferences, tool security |
| Related | `implementation_plans/1_TOOLS_builtin_tools_catalogue.md`, `todos/pending/5_TOOLS_builtin_tools.md`, `29_TOOLS_security_approval_preview.md`, `30_TOOLS_auto_approvals.md`, `18_TOOLS_session_tools_and_call_loop.md` |
| Status | accepted (partial — open items listed below) |
| Decided by | user |

## Context

Planning the built-in tools (plan `1_TOOLS_builtin_tools_catalogue.md`) raised nine blocking
choices (D1–D9). The owner answered D1–D5, D7 and D9 on 2026-10-05 and asked for more detail on
the groupings, `*_source_def`, D6 (tool context) and D8 (dependencies), which stay open.

## Questions and Answers

| # | Question | Options offered | Chosen (owner's words) |
|---|---|---|---|
| D1 | How built-ins become available | registered at load; opt-in; only in `&` mode; opt-in + `&` | **`&` mode + opt-in**: "Built ins should only be registered on load for `&` agentic repl mode. But the tools should be available for registration in normal chat mode as opt in." |
| D2 | Wire names | plain (`read_file`); prefixed (`jl_read_file`) | **plain**: "Plain names is fine." Groupings and the `*_source_def` shape: open |
| D3 | Workspace folder | `pwd()`; active project's folder; Preference; per session | **current directory** |
| D4 | Paths outside the folder | raise level; refuse; allow | **always `:high`**: "anything outside workspace folder automatically makes the tool call `High` — should check whether path has prefix of current dir or has `.` as first part or does not have absolute path (i.e. if the path is `src/` it is assumed that it relative to the current workspace folder and then it's fine)" |
| D5 | Where `execute_julia_code` evaluates | `Main`; per-session module; worker process | **a Preference**, default `"main"` (the `Main` module); `"sandbox"` = a Sandbox module per session |
| D7 | Output size cap | constant; Preference | **none**: "No size caps please." |
| D9 | Secrets in tool environments | scrub child-process env; redact results; both; neither | **scrub**: "any environment variable that ends with `_KEY` should be removed" |

## Decision

- Built-in tools are not put in the global registry when JAIL loads, so `}` / `chat!` sessions
  (`tools = nothing` = every registered tool) do not get them. The `&` mode attaches them when it
  loads. In normal chat they are opt-in. **Open:** the form of the opt-in.
- Built-in tools use plain wire names (`read_file`, `execute_julia_code`, …).
- Workspace folder = the current directory.
- A path counts as inside the workspace if it is absolute and starts with the current directory,
  its first part is `.`, or it is relative (e.g. `src/`). Any call that touches a path outside is
  `:high`, whatever the tool's level for inside paths. **Open:** relative paths that leave the
  folder through `..` (e.g. `../x`) or symlinks.
- `execute_julia_code` evaluates in `Main` by default; a Preference switches it to `"sandbox"`,
  a separate module for each session. **Open:** the Preference key name. Planner's note (not
  decided): a per-session module keeps names apart; it is not a security boundary (code there
  can still `run`, do file IO and read `ENV`), so the tool stays `:high` in both settings.
- Tool output is never truncated.
- Child processes started by built-in tools get the environment without any variable whose name
  ends in `_KEY`. **Open:** case sensitivity; provider `api_key_env` names that don't end in
  `_KEY`; whether values are also redacted from results. In-process tools (`execute_julia_code`
  in either mode) still see `ENV`, because removing variables from the process would break JAIL's
  own provider requests.

## Rejected

- D1: registering at load for every session (built-ins would go to every `}` chat); `&` only
  with no opt-in.
- D2: a name prefix.
- D3: the active project's folder, a Preference, per-session folders.
- D4: refusing outside paths; allowing them freely; the planner's draft of `:medium` for
  outside reads.
- D5: a worker process (no REPL state, needs Distributed or Malt); hard-coding one module.
- D7: a fixed or Preference-set cap.
- D9: scrubbing only the configured `api_key_env` names; doing nothing.

## Consequences

- With no cap, a very large result can exceed a provider's limit (OpenAI Responses
  `function_call_output.output` string `maxLength: 10485760`,
  `artifacts/provider_docs/openapi/api_spec.yaml#L81074-L81110`), and the failed request rolls
  back the whole turn (`_chat!` in `src/chat.jl`). Large results also cost tokens on every later
  request in the session.
- `"sandbox"` needs to know the current session inside the tool, which tools can't do today;
  this pulls the tool-context question (D6) forward into the `execute_julia_code` stage.
- A new Preference key means updating `examples/LocalPreferences.toml`.

## Revisit Trigger

Provider errors from oversized tool results; a need to isolate model code from the REPL
process; secrets stored under names not ending in `_KEY`; owner reports that the `..`/symlink
handling lets paths escape.

## Amendment (2026-10-05)

The open items above (opt-in form, `..`/symlinks, protected paths, scrubbing details, case
sensitivity) are settled in `32_TOOLS_builtin_tools_groups_and_rules.md`; the scrubbed suffixes
grow to `_KEY`, `_CREDENTIALS`, `_CREDENTIAL` (case-insensitive) plus a Preference list.
