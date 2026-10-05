# Built-in tools: 25 tools in six effect groups, opt-in, path/env security, tool context

| Field | Value |
|-------|-------|
| Artifact | `25_TOOLS_builtin_tools.md` |
| Category | work_history |
| Subject | `TOOLS` |
| Date | 2026-10-05 |
| Area/Purpose scope | public API, tool loop, Preferences, dependencies, docs, examples |
| Related | `implementation_plans/1_TOOLS_builtin_tools_catalogue.md`, `design_decisions/31_TOOLS_builtin_tools_policy.md`, `design_decisions/32_TOOLS_builtin_tools_groups_and_rules.md`, `todos/pending/5_TOOLS_builtin_tools.md`, `work_history/24_TOOLS_security_approval.md` |

## Scope of This Unit of Work

Follows `24_TOOLS_security_approval.md` (its next step 3, todo 5). User requests, in order:

1. "enumerate all the tools in this harness [VS Code Copilot] and what an equivalent tool in JAIL
   would look like ... how it runs / how it's sandboxed ... what security levels should apply" —
   produced plan `1_TOOLS_builtin_tools_catalogue.md` (first file in `artifacts/implementation_plans/`).
2. Three answer rounds (D1–D9, G1–G7, G8–G9 + two optional questions) — recorded as decisions 31
   and 32 (with amendment).
3. "Okay now please implement this plan" — Stages 1–8 below.

## What Changed

| File | Change |
|-------|--------|
| `src/builtin_tools/common.jl` (new) | `ToolContext`, `tool_context()` (`ScopedValue`), internal `_PROMPT_HOOK`/`_before_prompt`; `_resolve(path)` → `_PathInfo(path, inside, protected)` (normpath, `..` first part, whole-component prefix, symlink walk below root, protected = `LocalPreferences.toml`/`Project.toml`/`.git`/`storage_dir` + Preference `protected_paths`, root-relative); `_read_level`, `_write_level`; `_child_env()` (drops `*_KEY`/`*_CREDENTIALS`/`*_CREDENTIAL` case-insensitively + Preference `scrub_env_vars`); `_run_cmd(cmd; timeout, dir)` (Pipe drained by a task, stdin devnull, Timer kill, returns output/exitcode/signal/timed_out); `_builtin!`, lazy `_builtins()`, `builtin_tools()`, `register_builtin_tools!(names...)`, `_register_builtin_prefs!()` (Preference `builtin_tools`) |
| `src/builtin_tools/glob.jl` (new) | `_glob_regex` (`*`, `**`, `?`, `[..]`, `[!..]`, `{a,b}`), `_glob_matcher` (no `/` = file name anywhere), `_workspace_files` (`git ls-files --cached --others --exclude-standard -z`, else `walkdir`; skips symlinks, `.git`, storage dir) |
| `src/builtin_tools/files.jl` (new) | `read_file`, `list_dir`, `find_files`, `grep_files` (read); `create_file`, `create_directory`, `replace_in_file`, `replace_in_files(::Vector{FileEdit})` (edit; atomic writes, all-or-nothing, `- `/`+ ` diff previews) |
| `src/builtin_tools/source.jl` (new) | Port of the owner's `src_helpers_claude.jl` (JuliaSyntax): `julia_source_method(signature)`, `julia_source_methods(name)` (dedupe by file:line, per-method notes), `julia_source_struct(name)` (each method location, then package-file search; handles abstract types), `julia_source_module(name)` (also searches `pkgdir` files / Base dir); no-`eval` resolver `_resolve_name` (names, `a.b`, `Base.:+`, `T{...}`); `_PARSED` mtime cache |
| `src/builtin_tools/julia.jl` (new) | `execute_julia_code` (`include_string` in `Main` or a per-session `Sandbox_<uuid tail>` module per Preference `julia_code_module`; captures stdout/stderr/logs/`display`; `=> value` with `:limit`; `_JuliaEvalError` keeps output + trimmed trace; `SOURCE_PATH` set to the workspace root), `julia_docs` (macros too), `find_julia_symbols`, `check_julia_syntax` (JuliaSyntax diagnostics) |
| `src/builtin_tools/process.jl` (new) | `run_shell`, `run_tests` (`julia --project=<root> -e "using Pkg; Pkg.test()"`), `pkg_add` (execute); `git_changes` (read; `--no-ext-diff --no-textconv`); `pkg_status` (inspect) |
| `src/builtin_tools/web.jl` (new) | `fetch_url` with `_url_level` (https + public DNS → `:medium`; http, IP literal, localhost, private/loopback/link-local/CGNAT/multicast, other port, unparsable, DNS failure → `:high`); manual redirects refused if riskier than the approved URL; Gumbo HTML → text; "Untrusted content from" prefix |
| `src/builtin_tools/repl.jl` (new) | `repl_history` (1.13 `HistoryFile.records`, ≤1.12 vectors), `last_result`, `ask_user` (RadioMenu on a TTY, numbered `readline` otherwise; calls `_before_prompt`), `_never_confirm(t) = t.f === ask_user` |
| `src/tools.jl` | `register_tool!` uses new `_register!`; `_run_tool` and `_confirmation_needed` skip approval for `_never_confirm` tools |
| `src/chat.jl` | `_Prompting` step event; `_tool_loop!` runs each call inside `with(_TOOL_CONTEXT => ToolContext(s, c), _PROMPT_HOOK => ...)`; `chat!(; stream)` ignores `_Prompting` |
| `src/repl/chat_mode.jl` | `}` clears its status line on `_Prompting` as on `_Confirming` |
| `src/JAIL.jl` | includes; exports `ToolContext, tool_context, builtin_tools, register_builtin_tools!`; `__init__` calls `_register_builtin_prefs!()` |
| `Project.toml`, `Manifest.toml` (via `Pkg.add`/`Pkg.compat`) | deps JuliaSyntax (`1`), Gumbo (`0.8`), InteractiveUtils, Logging, Pkg, Sockets (`1.11.0`) |
| `docs/src/guide/tools.md` | "Built-in tools" section (table, workspace/protected paths, running Julia code, child processes and secrets, web pages, tool context) + four Preferences |
| `docs/src/builtin_tools.md` (new), `docs/make.jl` | page with the 25 tool docstrings (moving them out of `reference.md` avoided Documenter's HTML size warning); new keys in `__clear__` |
| `docs/src/reference.md`, `docs/src/guide/providers.md` | new exports; Preferences table rows |
| `examples/builtin_tools.jl` (new), `examples/LocalPreferences.toml` | example (listing, opt-in, level table, scripted model running 11 tool calls, misuse, clean-up); four Preference keys |

## Decisions

- `31_TOOLS_builtin_tools_policy.md`: `&`-mode + opt-in availability; plain names; workspace =
  `pwd()`; outside → `:high`; `julia_code_module` `"main"`/`"sandbox"`; no output caps; `_KEY`
  env scrubbing.
- `32_TOOLS_builtin_tools_groups_and_rules.md` (+ amendment): function + Preference opt-in;
  effect groups `read/inspect/edit/execute/web/interact`; four `julia_source_*` tools; `..`,
  symlinks outside; root-relative protected paths, writes only, `storage_dir` included; suffixes
  `_KEY/_CREDENTIALS/_CREDENTIAL` + `scrub_env_vars`; public tool context; agent-chosen deps;
  names confirmed; source tools always `:low`; `a = always` allowed for `:high`; `ask_user` never
  confirmed.
- Agent-decided while implementing (not in the plan): `register_builtin_tools!()` with no names
  throws (no "all"); `ask_user` exemption by function identity (a user tool named `ask_user` is
  not exempt); sandbox module named from the UUID's random tail (the time-based head collided
  for sessions created together); `execute_julia_code` sets `SOURCE_PATH` so relative
  `include` resolves from the workspace (found when the example's `include` resolved against
  `examples/`); `fetch_url` redirect rule is "no riskier than the approved URL" (the plan said
  "refuse any `:high` hop", which would block every redirect of an approved localhost URL);
  `grep_files` matches case-insensitively; `find_julia_symbols` skips `_`-prefixed names.

## Verification

Stage 1 (REPL):

```
(R("src/JAIL.jl")).inside = true   (R("./src")).inside = true   (R(joinpath(pwd(), "src"))).inside = true
(R("/etc/hosts")).inside = false   (R("../x")).inside = false   (R("src/../../x")).inside = false   (R(pwd() * "x/y")).inside = false
(R("Project.toml")).protected = true   (R(".git/config")).protected = true   (R(".jail/x.json")).protected = true
(R("docs/Project.toml")).protected = false
(R("tmp_link/a")).inside = false
out = (output = "", exitcode = 0, timed_out = true)            # sleep 5, timeout 1
length(out.output) = 200000                                     # no deadlock, no cap
[... if haskey(env, k)] = ["KEYRING"]                           # FAKE_KEY, fake_api_key, GOOGLE_APPLICATION_CREDENTIALS, MY_CREDENTIAL removed
(JAIL._run_cmd(`sh -c 'echo "[$FAKE_KEY][$KEYRING]"'`)).output = "[][e]\n"
haskey(JAIL._child_env(), "GITHUB_TOKEN") = false               # scrub_env_vars = ["github_token"]
(JAIL._resolve("secrets/a")).protected = true   (JAIL._resolve("secretsx")).protected = false
ArgumentError: Preference `protected_paths` must be a list of strings, got "oops"
```

Preference `builtin_tools = ["read", "ask_user"]`, REPL restarted:
`["ask_user", "check_julia_syntax", "find_files", "git_changes", "grep_files", "list_dir", "read_file"]`;
`["nope"]` → `[Warn | JAIL] JAIL: could not register the built-in tools listed in the Preference builtin_tools`, 0 tools.

Stages 2–3: glob checks all `true` (`*.jl`, `src/**/*.jl`, `a?c`, `[ab]`, `[!ab]`, `*.{jl,md}`,
regex metacharacters); `read_file` levels `:low` / `/etc/hosts` `:high` / `../JAIL.jl/...` `:high`;
`find_files("**/*.html")` excludes git-ignored `docs/build`; replace with 2 matches and 0 matches
error and leave the file byte-identical; a 2-edit batch with a bad edit writes nothing; levels
`create_file` in root `:medium`, `/tmp/x` `:high`, `Project.toml` edit `:high`,
`docs/Project.toml` `:medium`, `create_directory` `:low`, `.git/x` `:high`, `read_file Project.toml` `:low`.

Stage 4: `julia_source_methods("JAIL.register_tool!")`, `julia_source_struct` for `JAIL.ToolSpec`,
`JAIL.AbstractProvider` (no constructor → file search), `Dict{String,Int}`,
`julia_source_module("Base.Iterators")` (`baremodule Iterators`), `julia_source_method("JAIL.read_file(::String, ::Int)")`
all return `# file:line` + source; `rm("x")` → error result ("is not a name"); REPL-defined
`f_repl` → note line; `julia_docs("Base.@kwdef")`; `check_julia_syntax` → `# Error @ .../bad.jl:3:12`.

Stage 5: `println("hi"); @info "note"; display([1,2]); 1 + 1` →
`hi\n[ Info: note\n2-element Vector{Int64}:\n 1\n 2\n=> 2`; error keeps `before` + `ERROR: boom` +
trace ending `@ jail_tool:2`; `y_tool = 41;` → `(no output)`. Mock tool rounds through `chat!`:

```
("responses", ("tool said: from responses\n=> 42", ...))
("chat_completions", ("tool said: from chat_completions\n=> 42", ...))
("anthropic", ("tool said: from anthropic\n=> 42", ...))
s1: => (1, Main.Sandbox_edce151333cc)
s2: => (2, Main.Sandbox_dd213ba6f1e3)
isdefined(Main, :xsb) = false
bogus: `execute_julia_code` threw an error: ArgumentError: Preference `julia_code_module` must be "main" or "sandbox", got "bogus"
last_output[] = "ctx-demo whoami_tool"       # user tool reading tool_context() through chat!
```

Stage 6: `run_shell` with `OPENAI_API_KEY` set → `[]\nerr\n[exit code 3]`; `sleep 5` with
timeout 1 → `[killed after 1 s]`; `git_changes(false)` lists the tree; `run_tests()` on JAIL (no
test folder) → Pkg's error + `[exit code 1]`.

Stage 7: `_url_level` table — `https://julialang.org` medium; http, 127.0.0.1, localhost:8080,
169.254.169.254, [::1], 10.0.0.1, :8443, ftp, garbage, `.invalid` all high. Local server: 302
followed, HTML → `Title: Demo page`, `# Hi`, `[link](/next)`, list items; `image/png` refused.

Stage 8: `ask_user` with options under `tool_approval = "all"`, stdin piped `2` → `blue`,
events `[:AssistantMessage, :ToolCall, :_Prompting, :ToolResult, :AssistantMessage]` (no
`_Confirming`); free text `Ansaar`; `needs_confirmation(ask_user call; approval = "all") = false`,
also with `set_tool_auto_approval!("ask_user", false)`; `repl_history(2)` returns the last two
1.13 entries.

`examples/builtin_tools.jl` in a fresh REPL, stdin `y y y 3 y`, MODE `"auto"` (excerpt):

```
Edit file [medium]: run it? [y/N/a = always] ← Edit file: Replaced 1 occurrence in `builtin_tools_demo_iPDLY6/greet.jl`.
Julia code [high]: run it? [y/N/a = always] ← Julia code: Hello, JAIL!
The tool said:
Hello, JAIL!
=> 12
prefs unchanged: true
demo folders left: String[]  tools left: 0
```

Docs: `julia --project=docs docs/make.jl` — 0 warnings (first attempt: `25 docstrings not
included`; second: `Generated HTML over size_threshold_warn limit: reference.md`; fixed with the
new page); no owner values in `docs/build`. Load check: `length(builtin_tools()) = 25`,
`isempty(tools()) = true`, `fieldnames(ToolContext) = (:session, :call)`. `LocalPreferences.toml`
restored byte-for-byte after every test that wrote Preferences.

**No live provider calls, no live web fetch, nothing seen in a real terminal.**

## Known Limitations

- Not exercised: the `}` REPL mode with built-ins (status clearing on `_Prompting`), `ask_user`'s
  `RadioMenu` (TTY) path, a Google mock round, `pkg_add`, the `fetch_url` redirect refusal (needs
  a `:medium` start URL), `repl_history` on Julia ≤ 1.12.
- `_run_cmd` kills the child, not its process group; a backgrounded grandchild survives.
- `execute_julia_code` shows the value with `:limit => true` (as the REPL does), so long arrays
  are elided — the only shortening of tool output; decision 31 said no caps.
- `fetch_url`'s security function resolves DNS on every call of `security_level`/the loop.
- `@eval`-generated methods (e.g. `Base.sum(::Vector{Int})`) return the generating line.
- `find_julia_symbols` lists exported internals of `Compiler` etc.
- Sandbox modules are not saved; a restored session gets a fresh one. `_SANDBOXES`/`_PARSED`
  are unlocked Dicts.
- `security_level`, `needs_confirmation`, `tool_preview` look tools up in `_TOOLS` only, so the
  future `&` mode must register built-ins (or extend `_spec_and_args`) to attach them.
- `FileEdit` is a new non-exported type name in `JAIL`.
- Owner's helper `src_helpers_claude.jl` is still at the repo root (left for the owner).

## Todos

- Completed: none (todo 5's items 1–3 done; item 4, the `&` mode, remains — see update in the todo)
- Created: none
- Updated: `5_TOOLS_builtin_tools.md`

## Next Steps

1. Owner: run `examples/builtin_tools.jl` in a terminal REPL (TTY `ask_user` menu, prompts).
2. Plan the `&` agentic mode (todo 5 item 4): attach built-ins, `security_level` lookup for
   unregistered specs, agent-state tools (todo list, sub-agents, tool search).
3. `1_TESTS_test_suite_setup.md`: port the Stage 1–8 checks above into `test/`.
4. Decide whether `execute_julia_code` should drop `:limit` (decision 31 "no caps").
