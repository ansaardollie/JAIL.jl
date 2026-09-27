# Decision: Built-in system instructions for new sessions

| Field | Value |
|-------|-------|
| Artifact | `13_SESSION_default_system_prompt.md` |
| Category | design_decisions |
| Subject | `SESSION` |
| Date | 2026-09-27 |
| Area/Purpose scope | public API, Preferences |
| Related | `10_SESSION_registry_and_default_session.md`, `12_MESSAGES_types_and_chat.md` |
| Status | accepted |
| Decided by | user (scope, override, key, context details, wording, capture time); agent (opt-out, override semantics, package filter, path shortening, display) |

## Context

User: "work on the system instructions for the default session. I want it to describe the
context (i.e. that it's being run from Julia repl session) as well to be concise (since too
much output will crowd out the REPL outputs) and also if it generates any large code blocks
that it should be wrapped in triple backtick blocks."

## The Questions and Answers

| Question | Options | Chosen |
|---|---|---|
| Which sessions | default + REPL-created; only default; every session created without `system=` | **every session without `system=`** |
| Configurable | built-in + Preference override; built-in only | **Preference override** |
| Key name | `repl_system`; `default_system`; `system_prompt` | **`system_prompt`** |
| Environment details | Julia version, active project, OS/arch, loaded packages | **all four** |
| Wording | draft; change | **draft** |
| When captured | every request (system may be a function); once at creation | **once at creation** (agent had recommended per request) |

## Decision

```text
You are an assistant inside an interactive Julia REPL session (via the JAIL.jl package).
Your replies are printed directly in the user's terminal, between their REPL inputs and outputs.

- Be concise: answer directly, no preamble or closing summary. Expand only when asked.
- Assume questions are about Julia unless told otherwise.
- Put any code longer than one line in a fenced block with a language tag, e.g. ```julia.

Environment: Julia 1.13.0 on Darwin aarch64, active project ~/…/Project.toml, loaded packages: ….
```

Code: `src/system_prompt.jl` (`_REPL_INSTRUCTIONS`, `_environment_line`, `_main_packages`,
`_default_system`); applied in `Session(model; system = nothing)` and `_start_default_session!`.

Agent-decided:

- `system = ""` → no system instructions (`nothing`); explicit strings are used as-is.
- `system_prompt` Preference replaces only the instructions; the environment line is still
  appended. `system_prompt = ""` disables both. Non-string value → `ArgumentError` (at startup,
  a warning and no system instructions).
- Packages = top-level modules bound in `Main` with a UUID, excluding Base/Core/Main
  (`names(Main; imported = true, usings = true)`), not their dependencies.
- Home directory shown as `~` in the project path.
- `Session` text/plain display shows only the first line (60 chars) and the length.
- Not exported: no new public function; users read `session.system`.

## Consequences

- The `"default"` session is built during `using JAIL`, so its package list only has packages
  loaded before JAIL; project changes afterwards aren't reflected.
- The active project path (home-shortened) is sent to the provider with every request.
- Docs built from `@example` blocks embed the builder's environment line.

## Revisit Trigger

Users noticing stale environment lines (switch to per-request rendering), or concern about
sending project paths to providers.
