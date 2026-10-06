> **Superseded in part by:** `42_TOOLS_tool_search_and_loaded_tools.md` (availability/opt-in: built-ins registered at load; `builtin_tools` → `registered_tools`)

# Decision: Built-in tools — opt-in, effect groups, source-definition tools, path and env rules, tool context, dependencies

| Field | Value |
|-------|-------|
| Artifact | `32_TOOLS_builtin_tools_groups_and_rules.md` |
| Category | design_decisions |
| Subject | `TOOLS` |
| Date | 2026-10-05 |
| Area/Purpose scope | public API, Preferences, tool security, dependencies |
| Related | `31_TOOLS_builtin_tools_policy.md` (resolves its open items), `implementation_plans/1_TOOLS_builtin_tools_catalogue.md`, `28_TOOLS_groups_and_labels.md`, `30_TOOLS_auto_approvals.md`, `17_TOOLS_definitions_and_registry.md`, `src_helpers_claude.jl` (owner's helper) |
| Status | accepted (names confirmed in the amendment below) |
| Decided by | user (G1–G6, answers below); agent, by owner delegation, for the G7 dependency choices ("you can add dependencies") |

## Context

Second answer round on plan `1_TOOLS_builtin_tools_catalogue.md` (gates G1–G7), following
decision 31.

## Questions and Answers

| # | Question | Options offered | Chosen (owner's words where given) |
|---|---|---|---|
| G1 | Opt-in in normal chat | (a) function; (b) export functions for `register_tool!`; (c) Preference listing groups; (a)+(c) | **(a) and (c) together** |
| G2 | Groups | A by subject; B by effect; C mixed | **B**: `read`, `inspect`, `edit`, `execute`, `web`, `interact` |
| G3 | `*_source_def` shape | one `julia_source`; three tools | **four tools**: "seperate functions per syntax node (i.e. `julia_source_module`, `julia_source_struct`, `julia_source_method` (with call signature), `julia_source_methods` just a name without call signatures that returns all definitions)", built on the owner's `src_helpers_claude.jl` |
| G4a | `..` paths | inside (literal); outside | **outside**: "Any `..` as the first path part would be outside the folder so that is high security" |
| G4b | Symlinks | follow; don't | **"Symlinks count as outside"** |
| G4c | Protected paths | keep; drop | **keep**: defaults `LocalPreferences.toml`, `Project.toml`, `.git`, "but should also include a preference of additional paths/files/dirs that are protected" |
| G5a | `execute_julia_code` module values | — | **`"main"`, `"sandbox"`** ("main and sandbox are fine") |
| G5b | `_KEY` case | sensitive; insensitive | **insensitive** |
| G5c | Other variables | provider `api_key_env`; GCP credentials | **suffixes `_KEY`, `_CREDENTIALS`, `_CREDENTIAL`** (case-insensitive) **plus a Preference array of extra full variable names** |
| G6 | Tool context | (a) internal ScopedValue; (b) same, exported; (c) context argument | **(b)** |
| G7 | Dependencies | per item | owner: "you can add dependencies"; agent's picks below |

## Decision

- **Availability:** built-ins are never in the registry at load, except that the `&` mode
  attaches them (decision 31). In normal chat a user opts in with a function and/or a Preference
  listing groups registered when JAIL loads.
- **Groups (built-ins only):** `read` (read_file, list_dir, find_files, grep_files,
  check_julia_syntax, git_changes), `inspect` (julia_source_*, julia_docs, find_julia_symbols,
  pkg_status, repl_history, last_result), `edit` (create_file, create_directory,
  replace_in_file, replace_in_files), `execute` (execute_julia_code, run_shell, run_tests,
  pkg_add), `web` (fetch_url), `interact` (ask_user).
- **Source tools:** `julia_source_module(name)`, `julia_source_struct(name)`,
  `julia_source_method(signature)`, `julia_source_methods(name)`, implemented from the
  JuliaSyntax-based helpers in `src_helpers_claude.jl`.
- **Paths:** outside the current directory → `:high`, which includes `..` as the first part
  and any path through a symlink. Writes to protected paths → `:high`; defaults
  `LocalPreferences.toml`, `Project.toml`, `.git`, plus a Preference of extra paths.
- **Child-process environment:** remove every variable whose name ends, case-insensitively, in
  `_KEY`, `_CREDENTIALS` or `_CREDENTIAL`, plus the names in a Preference array (no redaction of
  tool results — not requested).
- **Tool context:** public and exported, so user tools can read the calling session and call
  (a `ScopedValue` set by the tool loop around each call).
- **`execute_julia_code` Preference values:** `"main"` (default), `"sandbox"`.

Agent-decided under G7 delegation:

| Need | Pick | Why |
|---|---|---|
| Source definitions, syntax check | **JuliaSyntax.jl** (package, as in the owner's helper) + **InteractiveUtils** (stdlib, `functionloc`) | Helper already uses them; `Base.JuliaSyntax` is internal |
| Glob | **own glob → `Regex` translator** (`*`, `**`, `?`, `[..]`, `{a,b}`) over `walkdir` | Small, no dependency; unsure Glob.jl supports `**` |
| `.gitignore` | **`git ls-files --cached --others --exclude-standard`** inside a git repo; fixed skips otherwise | Exact git semantics without a parser |
| Grep | **pure Julia** | One code path, same output everywhere |
| `git` | **system binary** via `Sys.which("git")`, clear error when missing | Avoids bundling a jll |
| HTML → text | **Gumbo.jl** (parser) + own text walker | Owner allowed deps; robust vs regex stripping |
| Semantic errors (JET) | **not added** | Heavy, tied to Julia versions; syntax check covers `get_errors` for now |
| REPL-defined source (CodeTracking) | **not added** | Error result names the limitation |
| Stdlibs | **Pkg, Sockets, Logging, InteractiveUtils** | `pkg_*`, DNS checks in `fetch_url`, log capture, `functionloc` |

Planner's readings, flagged to the owner in the same reply:

- `..` is checked **after `normpath`**, so `src/../../x` (→ `../x`) is outside.
- "Through a symlink" means any existing component **below the root** is a symlink (the root
  itself may sit under one, e.g. macOS `/tmp` → `/private/tmp`).
- Absolute paths are inside only if the root is a whole-component prefix (`/a/b` is not inside
  `/a/bc`'s root).

*Proposed* names (await confirmation): Preferences `builtin_tools` (groups list),
`julia_code_module`, `protected_paths`, `scrub_env_vars`; functions
`register_builtin_tools!(groups_or_names...)`, `builtin_tools()`; context `ToolContext`
(`session`, `call`) and `tool_context()`; method-signature argument form
`"Mod.f(::T1, ::T2)"`.

## Rejected

- G1: exporting the tool functions for `register_tool!` (loses group/security/preview);
  function-only or Preference-only.
- G2: subject groups (approving `files` would approve writes), mixed groups.
- G3: one `julia_source` tool; three kind tools.
- G4: following symlinks with `realpath`; treating `..` paths as inside; dropping protected
  paths.
- G5: case-sensitive matching; redacting values from results.
- G6: internal-only context; a context first argument (would change decision 17).
- G7: `rg`, Glob.jl, Git.jl, JET.jl, CodeTracking.jl, regex HTML stripping.

## Consequences

- New deps: JuliaSyntax, Gumbo, and stdlibs Pkg, Sockets, Logging, InteractiveUtils — added via
  `Pkg.add` with `[compat]` entries, never by hand.
- `GOOGLE_APPLICATION_CREDENTIALS` is removed from child processes, so `gcloud`/ADC-based
  commands run by `run_shell` lose it.
- Symlinked folders inside a project (common for data dirs) make every call through them `:high`.
- A public `ToolContext` becomes API every user tool can depend on.

## Revisit Trigger

Owner rejects any *proposed* name; symlinked project folders make the agent unusable; JuliaSyntax
or Gumbo compat blocks a Julia upgrade; demand for semantic diagnostics (JET).

## Amendment (2026-10-05, owner follow-up: G8 names, G9 levels)

| Question | Chosen (owner's words where given) |
|---|---|
| Preference names | **`builtin_tools`, `julia_code_module`, `protected_paths`, `scrub_env_vars`** ("provided preference names are fine") |
| Functions | **`register_builtin_tools!(groups_or_tool_names...)`, `builtin_tools()`** |
| Tool context | **`ToolContext` (`session`, `call`), `tool_context()`** |
| `julia_source_method` argument | **`"Mod.f(::T1, x::T2, y)"`** (untyped = `Any`, no `where`) |
| Protected-path matching | **root-relative**: "any file without a path is considered protecting files in the workspace root — there has to be relative path for anything else; and yes folder paths protect everything inside." The planner's "bare name matches anywhere" is rejected: `Project.toml` protects only `<root>/Project.toml`; `docs/Project.toml` needs its own entry |
| Protected reads | **writes only are `:high`**; reads follow the tool's normal level |
| JAIL `storage_dir` | **protected by default** (the `storage_dir` Preference, default `.jail`, resolved against the root) |
| Source tools | **always `:low`**, even though they read files outside the root (Base, `~/.julia`) |
| `a = always` for `:high` built-ins | **allowed** (unchanged behaviour of decision 30: saves `true` in `tool_auto_approvals`) |
| `ask_user` approval | **never needs approval**: "`ask_user` should never need approval" — not under `"all"`, and not with a `false` entry in `tool_auto_approvals` |

Defaults are now `LocalPreferences.toml`, `Project.toml`, `.git`, `storage_dir`. The
*proposed* markers above are confirmed. `scrub_env_vars` names are matched case-insensitively,
like the suffixes (planner's reading of G5b).

## Amendment 2 (2026-10-05, after running the tools live)

User: "When using the :fetch_url tool ... the output returned to the LLM is a markdown content and
not the actual html. It should be the actual html content. Without the additional `Untrusted
content from ..`"

- `fetch_url` returns the body exactly as served (HTML as HTML, other text formats as they
  are; binary content still refused). The `Untrusted content from <url>:` prefix is gone; the
  tool's docstring (what the model reads) still says to treat the content as untrusted.
- Supersedes the G7 pick "HTML → text: Gumbo.jl": Gumbo removed from the dependencies
  (`Pkg.rm("Gumbo")`). URL security levels and redirect checks are unchanged.
