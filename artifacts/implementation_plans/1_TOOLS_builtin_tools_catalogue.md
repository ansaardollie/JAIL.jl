# Plan: Built-in tools — catalogue mapped from the VS Code Copilot harness, with sandboxing and security levels

| Field | Value |
|-------|-------|
| Artifact | `1_TOOLS_builtin_tools_catalogue.md` |
| Category | implementation_plans |
| Subject | `TOOLS` |
| Date | 2026-10-05 |
| Area/Purpose scope | public API, core tool loop, Preferences, docs, examples |
| Related | `design_decisions/31_TOOLS_builtin_tools_policy.md` (answers D1–D5, D7, D9), `design_decisions/32_TOOLS_builtin_tools_groups_and_rules.md` (answers G1–G7), `src_helpers_claude.jl` (owner's source-definition helper), `todos/pending/5_TOOLS_builtin_tools.md` (this plan covers its items 1–3; item 4, the `&` mode, is a separate plan), `design_decisions/17_TOOLS_definitions_and_registry.md`, `design_decisions/18_TOOLS_session_tools_and_call_loop.md`, `design_decisions/27_TOOLS_call_records_and_display.md`, `design_decisions/28_TOOLS_groups_and_labels.md`, `design_decisions/29_TOOLS_security_approval_preview.md`, `design_decisions/30_TOOLS_auto_approvals.md`, `work_history/24_TOOLS_security_approval.md`, redesign notes #5 and #8 |
| Status | done — Stages 1–8 implemented, see `work_history/25_TOOLS_builtin_tools.md` |

## Goal

JAIL ships a set of built-in tools, organised in groups, that cover the parts of the VS Code
Copilot agent toolset that make sense in a Julia process: reading/searching/editing files,
executing Julia code, Julia reflection (source/doc lookup), shell and git, package/test commands,
web fetch, REPL introspection and asking the user. Each tool is an ordinary
`ToolSpec` (same groups, labels, `security`, `preview` and approval matrix as user tools),
kept out of the registry until a user opts in with `register_builtin_tools!` or the
`builtin_tools` Preference, with its sandboxing tier and security rule documented and verified.
The future `&` agentic mode can then attach them without new tool plumbing.

## Non-Goals

- The `&` agentic REPL mode itself (todo 5 item 4) — separate plan once this one is accepted.
- Agent-state tools that need the `&` mode's design first: todo list, sub-agents, deferred tool
  loading, session search (listed in the catalogue as **deferred**).
- Images in tool results (`view_image`) — needs an ontology change to `ToolResult`; listed as
  **deferred** with provider evidence below.
- OS-level sandboxing (`sandbox-exec`, `bwrap`) — listed as a future tier, not built here.
- Any truncation or size cap on tool output (decision 31, D7).
- Running model code in a worker process (decision 31, D5).
- Embeddings / semantic search, language-server features (rename, find usages), notebooks,
  anything that drives the VS Code UI.
- Ollama-native anything.

## Prerequisites

- Read: `src/tools.jl` (`_run_tool`, `_security_level`, `_preview_text`, `_confirm`),
  `src/chat.jl` (`_tool_loop!`, `_Confirming`), `src/ontology/tools.jl`,
  `src/persistence.jl` (`_write_atomic`), decisions 17, 18, 27–30.
- Decision `31_TOOLS_builtin_tools_policy.md` (settled: `&`-mode + opt-in availability, plain
  names, workspace = current directory, outside paths `:high`, `execute_julia_code` module
  Preference `"main"`/`"sandbox"`, no output caps, `*_KEY` env scrubbing).
- Decision `32_TOOLS_builtin_tools_groups_and_rules.md` (settled: function + Preference opt-in,
  effect groups, four `julia_source_*` tools, `..`/symlink/protected-path rules, env suffixes
  `_KEY`/`_CREDENTIALS`/`_CREDENTIAL` + Preference list, public tool context, dependencies).
- Read the owner's helper `src_helpers_claude.jl` (repo root) before Stage 4.
- Decision 32's amendment (names confirmed; protected paths root-relative, writes only;
  `storage_dir` protected; source tools always `:low`).

## Facts the design rests on (current code)

- Tools run **in the user's Julia process, sequentially**, from `_run_tool` in `src/tools.jl`:
  `t.f(args...)`; any exception becomes an `is_error = true` `ToolResult` with
  `sprint(showerror, e)`; `InterruptException` is rethrown, which rolls back the whole turn in
  `_chat!` (`src/chat.jl`).
- A tool's result is **text only**: `ToolResult.content::String` (`src/ontology/messages.jl`),
  produced by `_result_text` (string as-is, plain data as JSON, else `repr(MIME"text/plain")`).
- A tool function receives only its arguments — there is **no session/context argument**
  (Stage 1 adds the public `tool_context()`, decision 32).
- `tools(s)` is re-read every round in `_tool_loop!`, so the tool set can change mid-turn.
- Security: `security::Union{Symbol,Function}`; a function gets the converted args (omitted
  optionals = `nothing`); throwing or returning a non-level makes the call `:high`
  (decision 29). Approval matrix: `"auto"` (default) runs `:low` silently and asks for
  `:medium`/`:high`; `tool_auto_approvals` overrides per tool/group (decision 30).
- `Session(...; tools = nothing)` means **every registered tool**, so built-ins must stay out of
  `_TOOLS` until opted in (decision 31). Note `security_level`, `tool_preview` and
  `needs_confirmation` look tools up in `_TOOLS` (`_spec_and_args`), so `&`-mode attachment
  without registration needs those lookups extended — the `&` plan's concern.
- No test suite yet (`todos/pending/1_TESTS_test_suite_setup.md`); verification below is by
  `julia --project -e` scripts.

**Consequence for "sandboxing":** everything that runs in-process (tiers T0/T1 below) is
*policy*, not isolation — it has the user's full privileges and the approval prompt is the
safety boundary. Real isolation exists only for child processes (T2) and only partially
(cwd, environment, timeout, no stdin), unless an OS sandbox (T3) is added later.

## The VS Code harness toolset and JAIL equivalents

Tools visible to the planning session that wrote this plan are marked **(seen)**. The rest are
from the standard Copilot agent toolset as known to the planner and were *not* exposed in
planning mode — verify the names against the owner's tool picker.

### Mapped tools (built in this plan)

"Root" = the current directory. A path is **outside** when, after `normpath`, it is absolute
without the root as a whole-component prefix, its first part is `..`, or any existing component
below the root is a symlink; any call touching an outside path is `:high`. A **write** to a
protected path (`LocalPreferences.toml`, `Project.toml`, `.git`, plus the `protected_paths`
Preference) is `:high`; reads of protected paths keep the tool's normal level. Groups are the
effect groups of decision 32.

| # | VS Code tool | JAIL tool | Group | What it does in JAIL | Tier | Security level (rule) |
|---|---|---|---|---|---|---|
| 1 | `read_file` (seen) | `read_file(path, start_line = 1, end_line = nothing)` | read | Lines of a text file, 1-based, with a header `path (lines a–b of n)`; refuses binary files (NUL in first 8 KB); no cap | T1 | fn: `:low` inside root, `:high` outside |
| 2 | `list_dir` (seen) | `list_dir(path = ".")` | read | Entries, dirs suffixed `/`, symlinks marked `@`, sorted | T1 | fn: `:low` inside root, `:high` outside |
| 3 | `file_search` (seen) | `find_files(pattern, max_results = 200)` | read | Own glob → `Regex` translator (`*`, `**`, `?`, `[..]`, `{a,b}`) matched against root-relative paths, so a pattern can't leave the root. File list from `git ls-files --cached --others --exclude-standard` inside a git repo, else `walkdir` skipping `.git` and the JAIL `storage_dir`; symlinks not followed | T1 | static `:low` |
| 4 | `grep_search` (seen) | `grep_files(query, is_regex = false, include = nothing, max_results = 100)` | read | Pure Julia; `path:line: text` matches over the same file list as `find_files`; `include` is a glob; invalid regex → error result | T1 | static `:low` |
| 5 | `create_file` (seen) | `create_file(path, content)` | edit | New file only (errors if it exists); creates parent dirs; atomic write (`_write_atomic`) | T1 | fn: `:medium` inside root, `:high` outside or protected; preview fn: path + content |
| 6 | `replace_string_in_file` (seen) | `replace_in_file(path, old, new)` | edit | Exactly one occurrence of `old` must exist, else error result naming the count; atomic write | T1 | fn: as `create_file`; preview fn: unified diff |
| 7 | `multi_replace_string_in_file` (seen) | `replace_in_files(edits::Vector{FileEdit})` with `struct FileEdit; path::String; old::String; new::String; end` | edit | Validates **all** edits first, then writes; nothing written if any edit fails | T1 | fn: highest level of its edits; preview fn: concatenated diffs |
| 8 | `create_directory` (seen, deferred) | `create_directory(path)` | edit | `mkpath` | T1 | fn: `:low` inside root, `:high` outside or protected |
| 9 | `run_in_terminal` | `run_shell(command, timeout_seconds = nothing)` | execute | Child process `sh -c` (Windows: `cmd /c`) in root, stdin = `devnull`, combined stdout/stderr + exit code, killed on timeout | T2 | static `:high`; preview = `command` |
| 10 | `get_errors` (seen) | `check_julia_syntax(path)` | read | JuliaSyntax parse of the file; every diagnostic with line:column and message. No semantic checks (JET not added, decision 32) | T1 | fn: `:low` inside root, `:high` outside |
| 11 | `vscode_listCodeUsages` (seen) — definition half | `julia_source_module(name)` | inspect | Source of a module definition (see "Source-definition tools") | T0 | static `:low` (always, even for files outside the root) |
| 11b | same | `julia_source_struct(name)` | inspect | Source of a `struct` / `abstract type` / `primitive type` definition | T0 | static `:low` |
| 11c | same | `julia_source_method(signature)` | inspect | Source of the one method a call signature dispatches to; argument form `"Mod.f(::T1, x::T2, y)"` | T0 | static `:low` |
| 11d | same | `julia_source_methods(name)` | inspect | Source of every method of a function | T0 | static `:low` |
| 12 | `get_vscode_api` (docs lookup) | `julia_docs(name)` | inspect | Docstring text for the resolved binding (`Docs.doc`, rendered as plain Markdown) | T0 | static `:low` |
| 13 | `search_workspace_symbols` | `find_julia_symbols(query, max_results = 50)` | inspect | Substring match over `names(m; all = false)` of loaded modules; returns `Module.name :: kind` | T0 | static `:low` |
| 14 | — (redesign #8) | `execute_julia_code(code)` | execute | See "execute_julia_code" below | T0 | static `:high` in both `"main"` and `"sandbox"`; preview = `code` (todo 5) |
| 15 | `runTests` / `test_failure` | `run_tests()` | execute | `julia --project=<root> -e 'using Pkg; Pkg.test()'` as a T2 child; full output returned | T2 | static `:high` (runs project code the model may have written) |
| 16 | `get_changed_files` | `git_changes(diff = true)` | read | System `git` (`Sys.which`): `git -C <root> status --porcelain=v1` and `git diff --no-ext-diff --no-textconv` (no shell; flags stop repo config from running external programs) | T2 | static `:low` |
| 17 | `install_python_packages` / `notebook_install_packages` analogue | `pkg_status()` | inspect | `Pkg.status(io = buf)` of the active project | T0 | static `:low` |
| 18 | same | `pkg_add(packages::Vector{String})` | execute | `Pkg.add` into the active project (in-process: it is meant to change the REPL's environment) | T0 | static `:high`; preview = `packages` |
| 19 | `fetch_webpage` | `fetch_url(url)` | web | HTTP GET, no size cap, `text/html` → text via Gumbo.jl and a text walker (drops `script`/`style`), others as text if textual; result prefixed `Untrusted content from <url>:` | Net | fn: `:medium` for `https` to a public host on the default port; `:high` for `http`, IP literals, `localhost`, private/link-local/loopback addresses after DNS resolution, other ports, or unparsable URLs. Redirects followed manually, each hop re-checked; a hop that would be `:high` is refused |
| 20 | `terminal_last_command` (seen, deferred) | `repl_history(n = 20)` | inspect | Last `n` REPL inputs (from the REPL history provider or history file — internal API, verify on Julia 1.12) | T0 | static `:medium` (history can hold secrets) |
| 21 | `terminal_selection` (seen, deferred) | `last_result()` | inspect | `repr(MIME"text/plain", Main.ans)` | T0 | static `:medium` |
| 22 | `vscode_askQuestions` | `ask_user(question, options::Union{Nothing,Vector{String}} = nothing)` | interact | Free-text `readline`, or a `RadioMenu` (already used in `src/select.jl`) when options are given; uses the tool context's prompt hook so `}`/`&` clear their status line first | T0 | static `:low`; never needs approval, whatever `tool_approval` or `tool_auto_approvals` say (decision 32 amendment) |

Group names avoid `.` (in the TOML `tool_auto_approvals` table `a.b.tool = true` nests and fails
validation) and `"global"` (user tools' default). Built-ins and user tools can share a group
name; a user tool registered into `read` is approved along with it.

### Source-definition tools (redesign #8 `*_source_def`; decision 32 G3)

Ported from the owner's `src_helpers_claude.jl` (JuliaSyntax-based: `parseall(SyntaxNode, …)`,
`_collect!`, `_lines`, `_is_signature`, `_is_method_def`, `_def_text`, `_is_type_def`) into
`src/builtin_tools/source.jl` as internal `_src_def_*`. The `@src_def_method` macro is not
needed. The root-level `src_helpers_claude.jl` is the owner's file; the implementer leaves it
in place for the owner to delete.

**Name resolution (no `eval`):** `Meta.parse` the string and accept only a `Symbol`,
`a.b` (`Expr(:., …, QuoteNode)`, including `Base.:+`), and — in type positions — `T{…}` whose
parameters are resolvable names or literals (built with `Core.apply_type`). Each name is looked
up with `isdefined`/`getglobal`, starting in the calling session's evaluation module (`Main`, or
its sandbox via `tool_context()`), then `Main`. Anything else (calls, `where`, interpolation) is
an error result.

| Tool | Helper it ports | Changes needed over the helper |
|---|---|---|
| `julia_source_method(signature)` | `src_def_method(f, argtypes)` | Parse `"Mod.f(::T1, x::T2, y)"` into `f` and `Tuple{T1,T2,Any}` (untyped = `Any`; `where` unsupported), then `which` → `functionloc` → `_def_text`. No-match / ambiguity → error result with `which`'s message |
| `julia_source_methods(name)` | `src_def_methods(f)` | Dedupe by `(file, line)` (a method with optional arguments yields several methods with one definition); a method whose file is missing (REPL-defined, `REPL[n]`) gets a one-line note instead of aborting the whole call as the helper does; each definition headed `# file:line` |
| `julia_source_struct(name)` | `src_def_struct(T)` | Helper takes `first(methods(T))`, which fails for abstract/primitive types and types without constructors, and may hit an outer constructor in another file. Try each method's location until `_def_text(…, _is_type_def)` returns a definition whose name matches; else search the `.jl` files under `pkgdir(parentmodule(T))` for a type definition with that name |
| `julia_source_module(name)` | `src_def_module(M)` | Helper reads only `pathof(M)` (the package's root file), so submodules defined in included files are missed: also search the `.jl` files under `pkgdir(M)`. `Main` and REPL-created modules → error result. Returns the whole `module … end` text (no cap, decision 31) |

Every result starts with `# <file>:<line>` so the model can follow up with `read_file` (which is
`:high` for files outside the root, e.g. Base sources).

### Deferred (relevant, but blocked on another design)

| VS Code tool | JAIL equivalent | Blocked on |
|---|---|---|
| `view_image` (seen) | `view_image(path)` returning an image part | `ToolResult.content::String` must become content parts. Provider evidence that images are allowed in tool results: Anthropic `RequestToolResultBlock.content` = string or `RequestTextBlock`/`RequestImageBlock` (`artifacts/provider_docs/anthropic/api_spec.yaml#L4926-L4960`); OpenAI Responses `FunctionCallOutputItemParam.output` = string or `InputTextContentParam`/`InputImageContentParamAutoParam`/`InputFileContentParam` (`artifacts/provider_docs/openapi/api_spec.yaml#L81074-L81110`); Google Interactions `FunctionResultStep.result` = `ImageContent`/`TextContent` array, object or string (`artifacts/provider_docs/google/interactions.openapi.json#L5239-L5275`). Chat Completions and Google `generateContent` not reviewed. Needs its own provider-docs review + decision |
| `manage_todo_list` | `update_todos(items)` | Where agent state lives (not on `Session`, per guardrail) — `&` mode plan |
| `runSubagent` | `run_subagent(prompt, tools)` — a nested `Session` with a restricted tool set; returns its final text | `&` mode plan; `Session` always self-registers today |
| `tool_search` (seen) | `find_tools(query)` — adds a group to the running tool set (feasible: `tools(s)` is re-read each round) | `&` mode plan (tool context comes from Stage 1 here) |
| `session_store_sql` (seen) | `search_sessions(query)` over persisted session files (`src/persistence.jl`) | `&` mode plan; privacy level |
| `get_terminal_output`, `kill_terminal` | background `run_shell(...; background = true)` + `shell_output(id)` / `kill_shell(id)` | A process registry; follow-up after Stage 5 |
| `github_repo` | GitHub code search via its REST API | Credentials Preference; follow-up of `fetch_url` |
| `create_new_workspace`, `get_project_setup_info` | `create_package(name)` via `Pkg.generate` | Low value; follow-up |

### Not relevant in a Julia session

| VS Code tool | Why not |
|---|---|
| `semantic_search` (seen) | Needs an embeddings index; JAIL's ontology has no embeddings API. Revisit if it gains one |
| `vscode_renameSymbol` (seen), `vscode_listCodeUsages` usages half | Needs a language server; text search (`grep_files`) + edits cover it crudely |
| `run_vscode_command`, `install_extension`, `vscode_searchExtensions_internal`, `open_simple_browser` | Drive the VS Code UI |
| `create_new_jupyter_notebook`, `edit_notebook_file`, `run_notebook_cell`, `read_notebook_cell_output`, `copilot_getNotebookSummary`, `configure_notebook` (notebook tools; several seen as deferred) | VS Code notebook UI; `execute_julia_code` is the REPL analogue |
| `run_task`, `create_and_run_task`, `get_task_output` (seen) | VS Code tasks; `run_shell`/`run_tests` cover the use |
| `configure_python_environment` and other Python-extension tools | Python-specific |

## Sandboxing tiers

| Tier | Where it runs | Containment | Tools |
|---|---|---|---|
| T0 | In-process, no file IO beyond reflection/Pkg | None beyond approval. Reflection tools resolve names **without `eval`**, so `:low` is safe. `execute_julia_code` in `"sandbox"` gets its own module, which separates names only | `julia_source_*`, `julia_docs`, `find_julia_symbols`, `pkg_*`, `repl_history`, `last_result`, `ask_user`, `execute_julia_code` |
| T1 | In-process file IO | Path rule in the security function (outside/protected as defined above the catalogue); search tools never leave the root and don't follow symlinks | `read`/`edit` file tools, `check_julia_syntax` |
| T2 | Child process (`Base.run` on a `Cmd`, no shell for fixed commands) | `dir = root`; stdin `devnull`; stdout+stderr to a pipe drained by a task (avoids a full-pipe deadlock); `Timer` kills the process on timeout; environment without variables whose names end, case-insensitively, in `_KEY`, `_CREDENTIALS` or `_CREDENTIAL`, nor those in the `scrub_env_vars` Preference (compared case-insensitively); no output cap | `run_shell`, `git_changes`, `run_tests` |
| Net | In-process HTTP (`HTTP.jl`, existing dep) | URL/host rules in the security function, DNS-resolved address checks (`Sockets`), manual redirects; no body cap | `fetch_url` |
| T3 (future) | T2 wrapped in an OS sandbox | macOS `sandbox-exec`, Linux `bwrap`/user namespaces; read-only FS outside root, no network | Opt-in later; out of scope |

**Protected paths** (decision 32 + amendment): defaults `LocalPreferences.toml`, `Project.toml`,
`.git` and JAIL's `storage_dir` (Preference, default `.jail`), plus entries of the
`protected_paths` Preference. Every entry is **root-relative**: a bare name is the file or
folder directly in the root (`Project.toml` protects `<root>/Project.toml` only;
`docs/Project.toml` needs its own entry), and a folder entry protects everything inside it.
An absolute `storage_dir` outside the root is already `:high` by the outside rule. Only
**writes** are raised to `:high` — without this a `:medium` edit could set
`tool_approval = "yolo"` in `LocalPreferences.toml`; reads keep the tool's normal level.

**General rule:** any tool that *executes* project files is `:high`, because the `edit` group
can write project files at `:medium` (write-then-run would otherwise bypass the high-level gate).

### execute_julia_code (redesign #8, todo 5)

- Parse/evaluate with `include_string(mod, code, "jail_tool")` inside `Base.invokelatest`.
  `mod` comes from the Preference `julia_code_module`: `"main"` (default) →
  `Main`; `"sandbox"` → a module created on first use for the calling session (found with
  `tool_context()`), kept in an internal `Dict{UUID,Module}` keyed by session id (not a
  `Session` field), lost on restart/restore. Outside a tool call (no context), `"sandbox"`
  falls back to a module shared by context-less calls.
- Capture: `redirect_stdout`/`redirect_stderr` to pipes drained by tasks; a
  `TextDisplay(buffer)` pushed on the display stack for `display` calls; a `Logging`
  `SimpleLogger` on the buffer (`with_logger`) for `@info`/`@warn`.
- Result text sections: output, then `=> <repr text/plain of the value>` (or nothing for
  `nothing`/trailing `;`); never truncated.
- On an exception, throw an internal `_JuliaEvalError` whose `showerror` prints the captured
  output plus the error and a backtrace trimmed to frames inside the evaluated code — so
  `_run_tool` produces an `is_error` result that still contains the output.
- `security = :high, preview = "code", group = "execute", label = "Julia code"` (todo 5).
- Ctrl-C interrupts the evaluation and, via the existing `InterruptException` rethrow, rolls
  back the whole turn (existing behaviour; document it). No in-process timeout is possible.

## Design Sketch (names confirmed in decision 32's amendment)

```julia
# Public (exported)
register_builtin_tools!("read", "inspect")      # groups or tool names -> Vector{ToolSpec}
register_builtin_tools!(:execute_julia_code)
builtin_tools() -> Vector{ToolSpec}             # every built-in, registered or not
unregister_tool!("read_file")                   # existing; removes an opted-in built-in

struct ToolContext                              # set by the tool loop around each call
    session::Session
    call::ToolCall
end
tool_context() -> Union{ToolContext,Nothing}    # nothing outside a tool call

# A user tool can use it too (decision 32, G6 = b)
"""Name of the session that called this tool."""
session_name() = tool_context().session.name
```

```toml
[JAIL]
builtin_tools = ["read", "inspect"]  # groups registered when JAIL loads; default []
julia_code_module = "main"           # "main" | "sandbox"
protected_paths = ["secrets", "docs/Project.toml"]   # root-relative; added to the defaults
scrub_env_vars = ["GITHUB_TOKEN"]    # removed from child processes, besides *_KEY etc.
```

```julia
# Internals
const _BUILTINS = Dict{String,ToolSpec}()           # never in _TOOLS until opted in
const _TOOL_CONTEXT = Base.ScopedValues.ScopedValue{Union{Nothing,ToolContext}}(nothing)
_workspace_root() = pwd()
_resolve(path) -> (abs::String, inside::Bool, protected::Bool)
_run_cmd(cmd::Cmd; timeout) -> (output::String, exitcode::Int, timed_out::Bool)
_child_env() -> Dict{String,String}
```

The prompt hook for `ask_user` (`}` clears its status line, like `_Confirming`) is an internal
field or a second internal `ScopedValue`; it is not part of the public `ToolContext`.

## Stages

Order: Stage 1 is required by all others; after it, Stages 2–8 can go in the listed order
(3 reuses 2's file helpers; 5 reuses 4's name resolver). Each stage ends with the package loading
(`julia --project -e 'using JAIL'`) and, where docs change, a 0-warning docs build
(`julia --project=docs docs/make.jl`). Any test that writes Preferences restores them and
compares `LocalPreferences.toml` byte-for-byte (as in `work_history/24_TOOLS_security_approval.md`).
Dependencies are added with `Pkg.add` + `Pkg.compat`, never by editing `Project.toml`.

### Stage 1 — Shared infrastructure, opt-in, tool context

- Deliverable: `src/builtin_tools/common.jl`: `_workspace_root`, `_resolve` (normpath, `..`,
  whole-component prefix, symlink walk below the root, protected matching incl. the
  Preference), `_run_cmd` (cwd, stdin `devnull`, drained pipe, timeout kill, `_child_env`),
  `_BUILTINS`, `register_builtin_tools!`, `builtin_tools()`, the `builtin_tools` Preference
  applied in `__init__`; `ToolContext`/`tool_context()` set in `_tool_loop!` with
  `Base.ScopedValues.with`. No tools yet (a dummy built-in may be used for the checks and
  removed).
- Files: `src/JAIL.jl` (include after `session.jl`, exports, `__init__`),
  `src/builtin_tools/common.jl` (new), `src/chat.jl` (`_tool_loop!` sets the context),
  `examples/LocalPreferences.toml` (`builtin_tools`, `protected_paths`, `scrub_env_vars`),
  `docs/src/guide/tools.md` ("Built-in tools" section: opt-in, path rules, env scrubbing,
  tool context), `docs/src/reference.md`.
- Verification:
  ```
  julia --project -e 'using JAIL
      @assert isempty(filter(t -> t.name == "read_file", tools()))   # not registered at load
      R(p) = JAIL._resolve(p)
      @assert R("src/JAIL.jl").inside && R("./src").inside && R(joinpath(pwd(), "src")).inside
      @assert !R("/etc/hosts").inside && !R("../x").inside && !R("src/../../x").inside
      @assert !R(pwd() * "x/y").inside                    # not a whole-component prefix
      @assert R("Project.toml").protected && R(".git/config").protected && R(".jail/x.json").protected
      @assert !R("docs/Project.toml").protected     # bare names are root-only
      mktempdir() do d; symlink(d, "tmp_link"); try @assert !R("tmp_link/a").inside finally rm("tmp_link") end; end
      out = JAIL._run_cmd(`sleep 5`; timeout = 1); @assert out.timed_out
      out = JAIL._run_cmd(`sh -c "head -c 200000 /dev/zero | tr \\\\0 x"`; timeout = 10)
      @assert length(out.output) == 200_000   # no deadlock, no cap
      withenv("FAKE_KEY" => "a", "fake_api_key" => "b", "GOOGLE_APPLICATION_CREDENTIALS" => "c", "MY_CREDENTIAL" => "d") do
          env = JAIL._child_env()
          @assert !any(haskey(env, k) for k in ("FAKE_KEY", "fake_api_key", "GOOGLE_APPLICATION_CREDENTIALS", "MY_CREDENTIAL"))
      end
      @assert tool_context() === nothing'
  ```
  Plus: `scrub_env_vars = ["GITHUB_TOKEN"]` and `protected_paths = ["secrets/"]` set with
  `JAIL._save_pref!`, then `_child_env()` lacks `GITHUB_TOKEN` and `R("secrets/a").protected`;
  with `builtin_tools = ["read"]` saved, a fresh `julia --project -e 'using JAIL; ...'` has the
  dummy built-in in `tools()`; a user tool returning `tool_context().session.name`, driven by
  `chat!` against a scripted local server (pattern of `examples/tool_security.jl`), returns the
  session's name.

### Stage 2 — `read` file tools

- Deliverable: `read_file`, `list_dir`, `find_files` (glob translator, `git ls-files` list),
  `grep_files`, with the levels in the catalogue.
- Files: `src/builtin_tools/files.jl` (new), `src/builtin_tools/glob.jl` (new),
  `src/JAIL.jl`, `docs/src/guide/tools.md`.
- Verification:
  ```
  julia --project -e 'using JAIL; register_builtin_tools!("read")
      c(n, a) = ToolCall("c", n, a)
      @assert security_level(c("read_file", Dict("path" => "src/JAIL.jl"))) == :low
      @assert security_level(c("read_file", Dict("path" => "/etc/hosts"))) == :high
      @assert security_level(c("read_file", Dict("path" => "../JAIL.jl/src/JAIL.jl"))) == :high
      r = JAIL._run_tool(c("grep_files", Dict("query" => "module JAIL")), tools("read"); approval = "yolo")
      @assert occursin("src/JAIL.jl:1", r.content) && !r.is_error
      r = JAIL._run_tool(c("find_files", Dict("pattern" => "src/**/*.jl")), tools("read"); approval = "yolo")
      @assert occursin("src/tools.jl", r.content) && !occursin("docs/build", r.content)   # gitignored'
  ```
  Plus glob unit checks on the translator: `*` doesn't cross `/`, `**` does, `?`, `[ab]`,
  `{a,b}`.
  Plus a `read_file` of a > 10 MB generated file through `chat!` against a scripted server, to
  observe the no-cap behaviour end to end (risk check).

### Stage 3 — `edit` file tools

- Deliverable: `create_file`, `create_directory`, `replace_in_file`, `replace_in_files`
  (`FileEdit` struct), unified-diff preview helper, all-or-nothing multi-edit.
- Files: `src/builtin_tools/files.jl`, `docs/src/guide/tools.md`, `examples/builtin_tools.jl`
  (new; works in a `mktempdir()` root and restores Preferences like `examples/tool_security.jl`).
- Verification (in a temp root, approval `"yolo"`): create → second create errors; replace with
  0 and 2 matches errors and leaves the file byte-identical; a 2-edit batch with one bad edit
  writes nothing; a write to an absolute path outside the temp root is `:high`; writes to
  `Project.toml`, `.git/x`, `.jail/x` and a `protected_paths` entry (e.g. `sub/Project.toml`)
  are `:high`, while `sub/Project.toml` without that entry is `:medium`; `read_file` of
  `Project.toml` stays `:low`;
  `tool_preview` of `replace_in_file` contains `-old`/`+new` lines.

### Stage 4 — Source-definition and inspection tools

- Deliverable: `julia_source_module`, `julia_source_struct`, `julia_source_method`,
  `julia_source_methods` (ported helper + the changes in "Source-definition tools"), the safe
  name/signature resolver, `julia_docs`, `find_julia_symbols`, `check_julia_syntax`.
- Dependencies: `JuliaSyntax`, `InteractiveUtils` (decision 32).
- Files: `Project.toml`/`Manifest.toml` via `Pkg.add`, `src/builtin_tools/source.jl` (new),
  `src/builtin_tools/julia.jl` (new), `src/JAIL.jl`, `docs/src/guide/tools.md`,
  `examples/builtin_tools.jl`.
- Verification:
  ```
  julia --project -e 'using JAIL; register_builtin_tools!("inspect", "read")
      run(n, a) = JAIL._run_tool(ToolCall("c", n, a), [tools("inspect"); tools("read")]; approval = "yolo")
      r = run("julia_source_methods", Dict("name" => "JAIL.register_tool!")); @assert occursin("function register_tool!", r.content) && count("# ", r.content) >= 1
      r = run("julia_source_method", Dict("signature" => "Base.sum(::Vector{Int})")); @assert !r.is_error && occursin("sum", r.content)
      r = run("julia_source_struct", Dict("name" => "JAIL.ToolSpec")); @assert occursin("struct ToolSpec", r.content)
      r = run("julia_source_struct", Dict("name" => "JAIL.AbstractProvider")); @assert occursin("abstract type AbstractProvider", r.content)
      r = run("julia_source_module", Dict("name" => "JAIL")); @assert startswith(strip(split(r.content, "\n"; limit = 2)[2]), "module JAIL")
      r = run("julia_source_methods", Dict("name" => "rm(\"x\")")); @assert r.is_error   # no eval
      r = run("check_julia_syntax", Dict("path" => "src/JAIL.jl")); @assert !r.is_error'
  ```
  Plus: a method defined in the REPL yields the `REPL[n]` note, not an exception; a broken temp
  file gives a line:column diagnostic.

### Stage 5 — `execute_julia_code`

- Deliverable: as specified in "execute_julia_code", with the `julia_code_module` Preference.
- Dependencies: `Logging`.
- Files: `src/builtin_tools/julia.jl`, `src/JAIL.jl`, `examples/LocalPreferences.toml`
  (`julia_code_module = "main"`), `docs/src/guide/tools.md`, `examples/builtin_tools.jl`.
- Verification:
  ```
  julia --project -e 'using JAIL; register_builtin_tools!("execute")
      run(a) = JAIL._run_tool(ToolCall("c", "execute_julia_code", a), tools("execute"); approval = "yolo")
      r = run(Dict("code" => "println(\"hi\"); @info \"note\"; 1 + 1")); @assert occursin("hi", r.content) && occursin("note", r.content) && occursin("2", r.content)
      r = run(Dict("code" => "println(\"before\"); error(\"boom\")")); @assert r.is_error && occursin("before", r.content) && occursin("boom", r.content)
      @assert security_level(ToolCall("c", "execute_julia_code", Dict("code" => "1"))) == :high'
  ```
  `"sandbox"`: two sessions each run `x = 1` / `x = 2` through `chat!` against a scripted
  server; each session's module holds its own `x` and `isdefined(Main, :x)` stays `false`.
  Plus a mock-server tool round per provider using `execute_julia_code` (todo 5 acceptance
  criterion), reusing the scripted local server pattern from `examples/tool_security.jl`.

### Stage 6 — shell, git, package tools

- Deliverable: `run_shell`, `git_changes`, `run_tests`, `pkg_status`, `pkg_add`.
- Dependencies: `Pkg`.
- Files: `src/builtin_tools/process.jl` (new), `Project.toml`/`Manifest.toml` via `Pkg.add`,
  `src/JAIL.jl`, docs, example.
- Verification: `run_shell("echo \$OPENAI_API_KEY")` returns an empty line; `run_shell("sleep 5", 1)` reports a timeout; `git_changes()` in this repo lists the
  working-tree state; levels: `run_shell`/`run_tests`/`pkg_add` `:high`, `git_changes`/
  `pkg_status` `:low`.

### Stage 7 — `web` tool

- Deliverable: `fetch_url` with the URL security function, DNS-resolved private-address check,
  manual redirects, Gumbo-based HTML → text, untrusted-content prefix.
- Dependencies: `Gumbo`, `Sockets`.
- Files: `src/builtin_tools/web.jl` (new), `Project.toml`/`Manifest.toml` via `Pkg.add`,
  `src/JAIL.jl`, docs, example.
- Verification: levels — `https://julialang.org` `:medium`; `http://example.com`,
  `https://127.0.0.1`, `https://localhost:8080`, `https://169.254.169.254/` `:high`; a local
  `HTTP.serve` returning a 302 to `http://127.0.0.1/...` is refused on the hop. No live call is
  required for acceptance.

### Stage 8 — REPL introspection and `interact` tools

- Deliverable: `repl_history`, `last_result` (`inspect`), `ask_user` (`interact`); the internal
  prompt hook so `}` clears its status line before `ask_user`; `ask_user` exempt from
  approval (decision 32 amendment) via an internal exemption set checked first in `_run_tool`
  and `_confirmation_needed` (no new `ToolSpec` field or public option), so it is never
  confirmed under `"all"` or with a `false` entry in `tool_auto_approvals`, and
  `needs_confirmation` returns `false` for it.
- Files: `src/builtin_tools/repl.jl` (new), `src/tools.jl` (exemption), `src/chat.jl`,
  `src/repl/chat_mode.jl`, `src/JAIL.jl`, docs (`docs/src/guide/tools.md`: approval section
  notes the exemption).
- Verification: `ask_user` with piped stdin returns the typed answer; with options and a
  non-TTY input falls back to numbered `readline`; `repl_history` returns `[]`-like text when no
  REPL is active instead of throwing; `needs_confirmation(ToolCall("c", "ask_user",
  Dict("question" => "q")); approval = "all") == false`, also after
  `set_tool_auto_approval!("ask_user", false)` (restore Preferences afterwards).

## Open Questions

Settled: decision 31 (D1–D5, D7, D9), decision 32 (G1–G7) and its amendment (G8 names,
G9 levels, `a = always` allowed for `:high`, `ask_user` never needs approval). No open
questions remain.

## Risks

- In-process tools have full user privileges; a mis-set `tool_auto_approvals` or `"yolo"`
  removes the only barrier. Cheapest check: Stage 1 protected-path test for
  `LocalPreferences.toml`.
- Pipe deadlock or lost output when capturing large outputs — Stage 1 `_run_cmd` test with
  > 64 KB output.
- REPL-history access relies on REPL internals that may change across Julia versions — verify
  on the project's Julia (compat `1.12`) before Stage 8.
- Built-in names colliding with user tools (e.g. a user `read_file`): with plain names, opting
  in replaces the user's tool (existing warning on re-registration).
- No output cap (decision 31): a huge result can exceed a provider limit and roll back the turn;
  check with a `read_file` of a > 10 MB file against a scripted server in Stage 2.
- Large tool catalogues cost tokens on every request — opt-in (decision 31) mitigates for `}`.
- Prompt injection through `read_file`/`fetch_url` content steering the model into `:high`
  calls; mitigated by `:high` approval under `"auto"` and the untrusted-content prefix, not
  eliminated.
