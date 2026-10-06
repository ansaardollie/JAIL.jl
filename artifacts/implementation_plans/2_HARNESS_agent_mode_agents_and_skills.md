# Plan: Agent mode (`&`, `agent!`), text-only chat mode, agents and skills

| Field | Value |
|-------|-------|
| Artifact | `2_HARNESS_agent_mode_agents_and_skills.md` |
| Category | implementation_plans |
| Subject | `HARNESS` |
| Date | 2026-10-06 |
| Area/Purpose scope | public API, core tool loop, Session data model, providers (`tool_choice`), persistence, REPL (`}`, `&`, `\|`), Preferences, dependencies, docs, examples |
| Related | `design_decisions/46_HARNESS_agent_mode_agents_and_skills.md` (H1–H17, the controlling decision), `design_decisions/18_TOOLS_session_tools_and_call_loop.md` and `design_decisions/42_TOOLS_tool_search_and_loaded_tools.md` (both superseded in part by 46), `design_decisions/13_SESSION_default_system_prompt.md`, `design_decisions/14_REPL_chat_mode.md`, `design_decisions/24_SESSION_persistence.md`, `design_decisions/30_TOOLS_auto_approvals.md`, `design_decisions/36_STREAMING_boxed_turn_display.md`, `design_decisions/45_TOOLS_parallel_tool_calls.md`, `implementation_plans/1_TOOLS_builtin_tools_catalogue.md` (deferred "`&` mode plan" items), `todos/pending/5_TOOLS_builtin_tools.md` (item 4: the `&` mode), `todos/pending/2_REPL_real_terminal_check.md`, `todos/pending/1_TESTS_test_suite_setup.md`, `work_history/40_TOOLS_parallel_line_separator.md` (latest), redesign notes #5, #7, #8, #11 |
| Status | done — Stages 1–8 implemented in one session, see `work_history/41_HARNESS_agent_mode_agents_and_skills.md`; live checks and G1–G3 in `todos/pending/12_HARNESS_live_checks_and_gates.md` |

## Goal

`chat!` and the `}` mode are text-only: they offer the model no tools and run no tool loop.
Agentic work goes through a new `agent!` function and a new `&` REPL mode, which run the
existing tool loop (built-ins, approvals, tool search, parallel calls) on the same `Session`.
Agent mode reads agent files (`*.agent.md`, `AGENTS.md`, `CLAUDE.md`) and skills (`SKILL.md`)
from the workspace, home and `storage_dir` folders. It builds the system prompt and tool set from
the applied agent (or the built-in `julia` agent), exposes skills to the model (`activate_skill`,
`read_skill_related_file`, `skill_<name>` tools) and to the user (`/<skill>` in `&`,
`run_skill!`), and lets the user create and edit agents and skills from `|` or Julia. Each
behaviour has a verification script.

## Non-Goals

- Sub-agents, todo-list tools, session search (catalogue plan's other deferred items).
- MCP servers, hooks, or agent `model:` front matter selecting a model (not requested).
- Mapping Claude `Bash(git:*)` patterns to command allow-lists (pattern ignored, decision 46).
- Images in tool results.
- Ollama-native anything.
- A test suite (`todos/pending/1_TESTS_test_suite_setup.md`); verification is by
  `julia --project -e` scripts and scripted local servers, as in earlier plans.

## Prerequisites

- Read decision 46 in full (it is the source of every API name and rule below).
- Read: `src/chat.jl` (`_complete`, `chat!`, `_request_tools`, `_chat!`, `_tool_loop!`,
  `_run_calls`, `_run_calls_concurrently`), `src/tools.jl` (`_prepare_tool`, `_auto_approval`,
  `_confirmation_needed`), `src/builtin_tools/tool_search.jl`, `src/builtin_tools/repl.jl`
  (`_never_confirm`), `src/builtin_tools/common.jl` (`ToolContext`, `_PROMPT_HOOK`, `_resolve`,
  `_real_path`, `_under`), `src/session.jl`, `src/persistence.jl` (`_session_json`,
  `_load_session` L300), `src/system_prompt.jl`, `src/repl/{chat_mode,model_mode,install}.jl`,
  `src/select.jl` (`_pick` L35, `_menu_terminal` L68), `src/ontology/requests.jl`.
- Scripted-server pattern for verification: `HTTP.serve!` mock in
  `examples/parallel_tool_calls.jl` (L81) / `examples/tool_search.jl` (L79).
- Dependencies are added with `Pkg.add` + `Pkg.compat` (never by editing `Project.toml`).
  Any check that writes Preferences restores them and compares `LocalPreferences.toml`
  byte-for-byte (as in `work_history/24_TOOLS_security_approval.md`).

## Facts the design rests on (current code, 2026-10-06)

- `chat!` → `_chat!` → `_tool_loop!` (`src/chat.jl` L203–L362): every request carries
  `_request_tools(s, p)` (session tools, loaded vs deferred, client `tool_search`/`tool_load`),
  and `s.system`. `_complete` builds `_Request` positionally (`request(ms, id)` closure);
  `src/tokens.jl` `_count_tokens` builds `_Request` too.
- `_Request` (`src/ontology/requests.jl` L3–L20) has no `tool_choice`. Anthropic already sends
  `tool_choice: {"type": "auto", "disable_parallel_tool_use": true}` when parallel calls are off
  (`src/providers/anthropic.jl` ≈L90).
- `_REPL_INSTRUCTIONS` (`src/system_prompt.jl`) ends with the tool-search line from decision 42;
  `s.system` stores the full text captured at creation (decision 13).
- Approvals: `_prepare_tool` (`src/tools.jl` ≈L789) takes the runnable `specs` as an argument
  (so unregistered specs work), then `_never_confirm(t)` → `_auto_approval(t)` →
  `_security_level`. `_never_confirm` (`src/builtin_tools/repl.jl` L92) lists `ask_user`,
  `tool_search`, `tool_load`.
- `tool_search` / `tool_load` read `tools(s)` and call `load_tools!`, which validates names
  against `_TOOLS` (strict) — so non-registered turn tools (skill tools) are invisible to them
  today.
- `_display_turn` (`src/repl/chat_mode.jl` L210) is shared by `}` and `chat!(...; stream = true)`;
  its outer box is titled `Chat: <session>` (decision 36).
- `_storage_dir()` (`src/persistence.jl` L19) = `abspath` of the Preference (default `.jail`);
  `_workspace_root()` = `pwd()`.
- No YAML dependency; JSON.jl 1.x is a dependency and its `JSON.Object` is an ordered dict.
- `InteractiveUtils` is a dependency (`edit`).

## Provider evidence for `tool_choice` "none" (decision 46, H3)

| Provider / wire format | Field | Evidence |
|---|---|---|
| OpenAI Responses | `tool_choice: "none"` | `ToolChoiceOptions` enum `none\|auto\|required`, `artifacts/provider_docs/openapi/api_spec.yaml#L74033-L74054` |
| OpenAI-compatible (Chat Completions) | `tool_choice: "none"` | `ChatCompletionToolChoiceOption`, `artifacts/provider_docs/openapi/api_spec.yaml#L41184-L41210` |
| Anthropic Messages | `tool_choice: {"type": "none"}` | DOCS-ONLY: `artifacts/provider_docs/anthropic/claude-docs/claude-docs-25-define-tools.md#L557`; allowed with manual thinking `claude-docs-21-thinking.md#L880`. **Conflict:** the local spec's `ToolChoice` lists only `auto`/`any`/`tool` (`artifacts/provider_docs/anthropic/api_spec.yaml#L5468-L5480`) |
| Google Interactions (Google; GoogleEnterprise `api = :interactions`) | `generation_config.tool_choice: "none"` | `GenerationConfig` (#L5314) `tool_choice` enum `auto\|any\|none\|validated`, `artifacts/provider_docs/google/interactions.openapi.json#L5362-L5390`. Vertex Interactions acceptance UNVERIFIED |
| GoogleEnterprise `api = :generate_content` | `toolConfig.functionCallingConfig.mode: "NONE"` | `GenerateContentRequest.toolConfig` `artifacts/provider_docs/google/ai-platform-spec.json#L63404` (field at #L63444) → `ToolConfig` #L69685-L69699 → `FunctionCallingConfig.mode` #L38424-L38455 |

## Design Sketch

### Public API (accepted in decision 46, H12)

```julia
# Modes
chat!(s, prompt; max_tokens = nothing, stream = false, thinking_effort = nothing,
      temperature = nothing, show_reasoning = nothing) -> AssistantMessage   # text only
agent!(s, prompt; max_tokens = nothing, stream = false, max_tool_rounds = nothing,
       thinking_effort = nothing, temperature = nothing, show_reasoning = nothing) -> AssistantMessage
agent!(prompt; kwargs...)                        # active session

# Agents and skills
agents() -> Vector{Agent}                        # discovered now, sorted by name, built-in `julia` included
skills() -> Vector{Skill}
use_agent!(s, "reviewer") ; use_agent!("reviewer") ; use_agent!(s, nothing)   # -> Union{Agent,Nothing}
current_agent(s) -> Union{Agent,Nothing}         # nothing = no agent applied (agent mode uses `julia`)
run_skill!(s, "review", "src/x.jl"; stream = true)   # = `/review src/x.jl` in `&`
new_agent("reviewer"; description = "Reviews diffs")  # -> path; opens edit()
edit_agent("reviewer")
new_skill("review"; description = "Review a file")    # -> path of SKILL.md; opens edit()
edit_skill("review")
```

```text
| mode:  agents | agent select [name|none] | agent new [name] | agent edit [name]
         skills | skill new [name] | skill edit [name]
& mode:  (reviewer) agent> fix the failing test
         (reviewer) agent> /review src/chat.jl 2
         (reviewer) agent> /clear | /help
```

### Types (exported: `Agent`, `Skill`, `SkillArgument`)

```julia
struct Agent
    name::String
    description::String
    instructions::String              # file body without front matter ("" for `julia`)
    tools::Vector{String}             # as written (aliases resolved at use)
    disallowed_tools::Vector{String}  # front matter `disallowedTools`
    path::Union{Nothing,String}       # nothing for the built-in `julia`
    source::Symbol                    # :workspace | :storage | :home | :builtin
    frontmatter::Dict{String,Any}
end

struct SkillArgument
    name::String
    type::Symbol                      # :string | :integer | :number | :boolean
    description::String
    required::Bool                    # default true
    default::Any                      # nothing when absent
    hint::Union{Nothing,String}       # from `argument-hint.<name>`
end

struct Skill
    name::String                      # front matter `name`, else folder name
    description::String
    when_to_use::Union{Nothing,String}
    body::String                      # SKILL.md without front matter
    dir::String
    arguments::Vector{SkillArgument}  # front matter order
    argument_hint::Union{Nothing,String}   # when `argument-hint` is a plain string
    user_invocable::Bool              # `argument-hint` set, or `user-invocable` not false
    model_invocable::Bool             # `disable-model-invocation` not true
    allowed_tools::Vector{String}
    disallowed_tools::Vector{String}
    source::Symbol
    frontmatter::Dict{String,Any}
end
```

### Session (decision 46, H1/H13)

```julia
mutable struct Session
    # … existing fields …
    agent::Union{Nothing,String}          # applied agent's name
    agent_path::Union{Nothing,String}     # file chosen at selection (internal; persisted)
end
```

Session JSON gains `"agent"` and `"agent_path"` (missing → `nothing`; format version unchanged).
`_show_details` (and `|` `status`) gains an `agent:` row.

### Internals

```julia
# Mode dispatch (types, not strings)
abstract type _Mode end
struct _ChatMode <: _Mode end
struct _AgentMode <: _Mode; turn::_AgentTurn; end

_turn_system(s, ::_ChatMode) = s.system
_turn_system(s, m::_AgentMode) = m.turn.system
# (loaded, deferred, runnable, tool_choice)
_turn_tools(s, p, ::_ChatMode)    # tools named in s.messages' ToolCalls (stub spec if unregistered), [], [], :none; empty → no tools, :auto
_turn_tools(s, p, m::_AgentMode)  # _request_tools minus disallowed, + agent tools loaded, + skill tools deferred,
                                  # + activate_skill/read_skill_related_file loaded (when ≥1 model skill), :auto

# One agent! call (ScopedValue; mutable under a lock: activations add approvals mid-turn)
mutable struct _AgentTurn
    agent::Agent
    skills::Dict{String,Skill}       # model-visible skills, duplicates resolved at turn start
    system::String
    auto::Set{String}                # agent tools ∪ activated skills' allowed-tools
    denied::Dict{String,String}      # tool => skill that disallows it
    extra::Vector{ToolSpec}          # activate_skill, read_skill_related_file, skill_<name>
    lock::ReentrantLock
end
const _AGENT_TURN = ScopedValue{Union{Nothing,_AgentTurn}}(nothing)
const _SKILL_CHOICES = Dict{UUID,Dict{String,String}}()   # session id => skill name => SKILL.md path

_frontmatter(text) -> (Dict{String,Any}, body::String)   # YAML.load(...; dicttype = JSON.Object{Any,Any})
_agent_dirs(), _skill_dirs() -> Vector{Tuple{Symbol,String}}
_resolve_tool_refs(names) -> Vector{String}              # aliases + group:<g>; one-time warnings
_substitute(body, values::Dict{String,Any}) -> String    # {{name}}; \{ \} escapes
_split_args(line) -> Vector{String}                      # spaces; "…" and '…' group
const _EDITOR = Ref{Any}(InteractiveUtils.edit)          # overridden in verification scripts
```

### System prompt composition (agent mode; decision 46)

```text
<s.system>

<_AGENT_BOILERPLATE: you are running as an agent in the user's Julia REPL (JAIL agent mode);
work with tools until the request is done, check results, finish with a short summary; tool
calls may be declined by the user; + the tool-search line moved from _REPL_INSTRUCTIONS>

## Project instructions (AGENTS.md)          # ./AGENTS.md and ./CLAUDE.md, each if present
<body without front matter>

## Agent: <name>                             # omitted for `julia`
<agent instructions>

## Skills                                    # omitted when no model-visible skill
Before a task, check whether a skill below covers it; if so call `activate_skill` with its name
and follow what it returns. Read files a skill refers to with `read_skill_related_file`.
- `<name>`: <description> When to use: <when_to_use>
```

Exact wording is agent-decided at implementation; the structure is fixed.

## Stages

Order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8. Stage 2 needs 1's `tool_choice`; 4 needs 3's
discovery; 5 needs 4's `_AgentTurn`; 6 needs 5's substitution; 7 needs 3 and 6 (`|` and `&`
completion); 8 documents everything. Every stage ends with `julia --project -e 'using JAIL'`
succeeding and, where docs change, a 0-warning `julia --project=docs docs/make.jl`. A stage
that exports a symbol adds it to `docs/src/reference.md` in the same stage.

### Stage 1 — `tool_choice` on requests

- Deliverable: `_Request.tool_choice::Symbol` (`:auto` default, `:none`), set as the last
  positional field; every `_Request(...)` call site updated. Request bodies: when
  `tool_choice === :none` and the request has tools, send the provider field from the evidence
  table (Anthropic: `{"type": "none"}` only, no `disable_parallel_tool_use`; OpenAI/compatible:
  no `parallel_tool_calls`); `:auto` sends exactly what is sent today. Each new line cites the
  evidence rows above in a comment, like existing provider code.
- Files: `src/ontology/requests.jl`, `src/chat.jl` (`_complete` gains `tool_choice` kwarg),
  `src/tokens.jl`, `src/providers/openai.jl`, `src/providers/openai_compatible.jl`,
  `src/providers/anthropic.jl`, `src/providers/google.jl` (Interactions and generateContent).
- Verification:
  ```
  julia --project -e 'using JAIL
      t = only(filter(x -> x.name == "read_file", builtin_tools()))
      ms = AbstractMessage[UserMessage("hi")]
      R(p, c; par = true) = JAIL._Request(Model(p, "m"), ms, nothing, 100, false, nothing, false, [t],
                                          nothing, nothing, false, ToolSpec[], par, c)
      B(p, c; kw...) = JAIL._request_body(p, R(p, c; kw...))
      @assert B(OpenAI(), :none)["tool_choice"] == "none"
      @assert !haskey(B(OpenAI(), :auto), "tool_choice")
      oc = OpenAICompatible("jail-tc-check", "http://127.0.0.1:1/v1")
      @assert B(oc, :none)["tool_choice"] == "none"
      @assert B(Anthropic(), :none; par = false)["tool_choice"] == Dict("type" => "none")
      @assert B(Anthropic(), :auto; par = false)["tool_choice"]["disable_parallel_tool_use"] == true
      @assert B(Google(), :none)["generation_config"]["tool_choice"] == "none"
      g = JAIL._request_body(JAIL._GenerateContentAPI(), Google(), R(Google(), :none))
      @assert g["toolConfig"]["functionCallingConfig"]["mode"] == "NONE"
      @assert !haskey(JAIL._request_body(JAIL._GenerateContentAPI(), Google(), R(Google(), :auto)), "toolConfig")'
  ```
  Plus `count_tokens` on a session with a model still works against a scripted server (no
  regression from the constructor change).

### Stage 2 — Split modes: text-only `chat!`, `agent!` with the tool loop

- Deliverable:
  - `_ChatMode`/`_AgentMode` dispatch; `_chat!(s, prompt, mode; …)` and
    `_tool_loop!(s, mode, limit, approval; …)` use `_turn_system`/`_turn_tools`. At this stage
    `_AgentMode` carries a minimal `_AgentTurn` for the built-in `julia` agent (boilerplate
    only, session tools as today) — no discovery yet.
  - `chat!`: no `max_tool_rounds`; system = `s.system`; tools = tools named in the history's
    `ToolCall`s with `tool_choice = :none` (a name no longer registered gets a stub spec: name,
    description "No longer available.", empty object schema); none when the history has no
    calls. A reply that still has calls gets error results "Tools are off in chat mode; use
    agent! for tool use." and is returned.
  - `agent!(s, prompt; …)`, `agent!(prompt; …)`: today's tool-loop behaviour (approvals,
    parallel calls, tool search, `stream` display) with system = `s.system` + boilerplate.
  - `_max_tool_rounds` default 50.
  - Move the tool-search line from `_REPL_INSTRUCTIONS` into `_AGENT_BOILERPLATE`
    (`src/system_prompt.jl`).
  - `_display_turn` takes the mode; the outer box is `Agent (<agent>): <session>` for agent
    turns, `Chat: <session>` for chat turns. `}` (`_chat_send`) calls the chat mode.
  - `count_tokens` keeps counting with `_request_tools(s, p)` (today's tool set, no agent
    additions) until gate G1 is answered.
  - Move tool-driving examples and doc snippets from `chat!` to `agent!`.
- Files: `src/chat.jl`, `src/system_prompt.jl`, `src/session.jl` (docstring only),
  `src/repl/chat_mode.jl`, `src/JAIL.jl` (export `agent!`), `src/tokens.jl` (if the
  `_request_tools` signature changes), `examples/LocalPreferences.toml` (`max_tool_rounds = 50`,
  comment "per agent! call"), `examples/tools.jl`, `examples/tool_ex1.jl`,
  `examples/builtin_tools.jl`, `examples/builtin_tools_prompts.jl`,
  `examples/parallel_tool_calls.jl`, `examples/tool_search.jl`, `examples/tool_security.jl`,
  `examples/reasoning.jl` (its tool turn), `examples/token_counting.jl` (its tool turn),
  `docs/src/guide/chat.md` (remove tool loop and `max_tool_rounds`; describe text-only and the
  "tools in history" rule), `docs/src/guide/tools.md` (tools run in `agent!`; L218, L569–L571,
  L604), `docs/src/guide/providers.md` (L212 `max_tool_rounds` row → `agent!`, default 50),
  `docs/src/guide/repl.md` (`}` is text-only), `docs/src/reference.md` (`agent!`).
- Verification (scripted Responses server recording request bodies, pattern of
  `examples/parallel_tool_calls.jl` L81; script replies: turn 1 a `get_weather` call then text;
  turn 2 text):
  ```
  julia --project -e 'using JAIL, HTTP, JSON
      # … server setup recording `bodies` …
      register_tool!(get_weather); s = Session(Model(scripted, "m")); load_tools!(s, get_weather)
      chat!(s, "hi")
      @assert !haskey(bodies[end], "tools") && !haskey(bodies[end], "tool_choice")
      @assert !occursin("Tool search is available", bodies[end]["instructions"])
      agent!(s, "weather in Paris?")
      @assert any(m -> m isa ToolResultMessage, s.messages)
      @assert occursin("Tool search is available", bodies[end]["instructions"])
      chat!(s, "thanks")
      @assert [t["name"] for t in bodies[end]["tools"]] == ["get_weather"] && bodies[end]["tool_choice"] == "none"
      @assert JAIL._max_tool_rounds(nothing) == 50
      @assert try chat!(s, "x"; max_tool_rounds = 1); false catch e; e isa MethodError end'
  ```
  Plus: a server that answers a chat turn with a tool call → reply returned, history ends with a
  `ToolResultMessage` whose result `is_error` and mentions `agent!`. `JAIL._chat_command("hi")`
  against the server prints no `→` lines. The scripted examples run unattended:
  `julia --project examples/tools.jl`, `examples/parallel_tool_calls.jl`,
  `examples/tool_search.jl`. Docs build: 0 warnings.
  **Live check (owner, with API keys; risk H3):** on Anthropic, OpenAI and Google, `agent!` one
  tool turn, then `chat!` on the same session must succeed (replayed tool blocks + `tool_choice`
  none).

### Stage 3 — Front matter, discovery, aliases

- Deliverable:
  - `Pkg.add("YAML")` + compat. `_frontmatter(text)`: a leading `---` … `---` block parsed with
    `YAML.load(…; dicttype = JSON.Object{Any,Any})` (keeps key order for `arguments`); no block
    → empty dict and the whole text. Invalid YAML → the file is skipped with a warning naming it.
  - `Agent`, `Skill`, `SkillArgument`; `agents()`, `skills()` (fresh scan per call).
    Folders (decision 46): agents in `./.github/agents`, `./.claude/agents`, `./.copilot/agents`,
    `<storage_dir>/agents`, `~/.claude/agents`, `~/.agents`, `~/.copilot/agents`, matching
    `*.agent.md`, `AGENTS.md`, `CLAUDE.md` (non-recursive); skills in `<base>/skills/<dir>/SKILL.md`
    for the same bases. `source` = `:workspace` / `:storage` / `:home`.
  - Agent `tools` / `disallowedTools` and skill `allowed-tools` / `disallowed-tools` accept a
    YAML list or a comma-separated string.
  - `arguments` parsed fully typed (H5): `type` ∈ string/integer/number/boolean (default
    string), `description`, `required` (default true), `default`; `argument-hint` as a string
    (stored on the skill) or a map (per-argument `hint`). Invalid entries → skill skipped with a
    warning.
  - Built-in `julia` agent (`source = :builtin`, empty instructions/tools); a discovered agent
    named `julia` is dropped with a warning (H15).
  - `_resolve_by_name(kind, name, candidates)`: one match → it; several → `_pick` menu listing
    source and path; cancel → `nothing`.
  - `_resolve_tool_refs`: the alias table of decision 46 (as a `const Dict`), `Tool(pattern)`
    stripped with a one-time warning, `group:<g>` kept, unknown names warned once.
- Files: `Project.toml`/`Manifest.toml` via `Pkg.add`, `src/harness/frontmatter.jl` (new),
  `src/harness/discovery.jl` (new), `src/harness/aliases.jl` (new), `src/JAIL.jl` (includes
  after `builtin_tools/common.jl`; exports `Agent`, `Skill`, `SkillArgument`, `agents`,
  `skills`), `docs/src/reference.md`.
- Verification (temp workspace and temp `HOME`):
  ```
  julia --project -e 'using JAIL
      mktempdir() do ws; mktempdir() do home; cd(ws) do; withenv("HOME" => home) do
          mkpath(".claude/agents"); mkpath(joinpath(home, ".agents/skills/review/ref"))
          write(".claude/agents/reviewer.agent.md", "---\nname: reviewer\ndescription: Reviews\ntools: [Read, \"Bash(git:*)\", group:edit]\ndisallowedTools: Write\n---\nBe strict.\n")
          write(".claude/agents/julia.agent.md", "---\nname: julia\n---\nx\n")
          write(joinpath(home, ".agents/skills/review/SKILL.md"), "---\nname: review\ndescription: Review a file\narguments:\n  path: {type: string, description: File}\n  depth: {type: integer, required: false, default: 1}\nargument-hint:\n  path: src/foo.jl\nallowed-tools: read_file, grep_files\n---\nReview {{path}} to depth {{depth}}.\n")
          as = agents(); r = only(filter(a -> a.name == "reviewer", as))
          @assert r.instructions == "Be strict.\n" && r.source === :workspace
          @assert count(a -> a.name == "julia", as) == 1 && only(filter(a -> a.name == "julia", as)).source === :builtin
          @assert JAIL._resolve_tool_refs(r.tools) == ["read_file", "run_shell", "group:edit"]
          @assert JAIL._resolve_tool_refs(r.disallowed_tools) == ["create_file"]
          sk = only(skills()); @assert sk.source === :home
          @assert [a.name for a in sk.arguments] == ["path", "depth"]
          @assert sk.arguments[2].type === :integer && !sk.arguments[2].required && sk.arguments[2].default == 1
          @assert sk.arguments[1].hint == "src/foo.jl" && sk.allowed_tools == ["read_file", "grep_files"]
      end end end end'
  ```
  Plus: a second `reviewer` under `<storage_dir>/agents` makes `JAIL._resolve_by_name` open the
  menu (check with a fake terminal as `src/select.jl` callers do, or piped stdin); a malformed
  YAML file is skipped with one warning; key order holds with 10 arguments (risk R2).

### Stage 4 — Applying agents to sessions

- Deliverable:
  - `Session.agent`, `Session.agent_path`; `use_agent!(s, name|nothing)`, `use_agent!(x)`,
    `current_agent(s)`; persistence (`_session_json`, `_load_session`), `_show_details` row.
  - `_agent_turn(s)`: re-read `s.agent_path`; if missing, resolve `s.agent` by name again (menu
    if ambiguous; none → error naming the agent and the `|` command to change it);
    `s.agent === nothing` → `julia`. Builds the system text (sketch above, without the skills
    section yet), reads `./AGENTS.md` and `./CLAUDE.md` with front matter stripped.
  - Tools: `_turn_tools(s, p, ::_AgentMode)` = `tools(s)` minus resolved `disallowedTools`
    (never removes `activate_skill`, `read_skill_related_file`, `tool_search`, `tool_load`);
    agent `tools` (resolved, intersected with `tools(s)`, others warned once) added to loaded
    and to `turn.auto`.
  - Approvals: an internal `_turn_verdict(t)` read from `_AGENT_TURN[]`, checked first in
    `_prepare_tool` and `_confirmation_needed`: denied → error result
    "Denied: the skill `<skill>` does not allow `<tool>`."; in `auto` → run without asking.
- Files: `src/session.jl`, `src/persistence.jl`, `src/harness/agent.jl` (new), `src/chat.jl`,
  `src/tools.jl`, `src/system_prompt.jl`, `src/repl/model_mode.jl` (`status` row only),
  `src/JAIL.jl` (exports `use_agent!`, `current_agent`), `docs/src/reference.md`,
  `docs/src/guide/sessions.md` (agent field, persistence).
- Verification (temp workspace as Stage 3; scripted Responses server recording bodies; Preference
  `tool_approval = "all"` saved then restored byte-for-byte; stdin `devnull` so any prompt
  declines):
  ```
  julia --project -e 'using JAIL …
      write("AGENTS.md", "---\nx: 1\n---\nProject rule.\n")
      s = Session(Model(scripted, "m")); use_agent!(s, "reviewer")
      @assert current_agent(s).name == "reviewer"
      agent!(s, "go")                    # server: one read_file call, then text
      b = bodies[end]
      @assert occursin("Project rule.", b["instructions"]) && occursin("Be strict.", b["instructions"])
      @assert !occursin("x: 1", b["instructions"])
      names = [t["name"] for t in b["tools"] if haskey(t, "name")]
      @assert "read_file" in names && !("create_file" in names)
      @assert !only(filter(m -> m isa ToolResultMessage, s.messages)).content[1].is_error   # ran without a prompt
      chat!(s, "plain"); @assert !occursin("Be strict.", bodies[end]["instructions"])
      use_agent!(s, nothing); @assert current_agent(s) === nothing'
  ```
  Plus: in a fresh process, `restore_session!(id)` gives a session with `agent == "reviewer"`;
  deleting the agent file then `agent!` resolves by name (or errors when no file is left);
  `|` `status` shows `agent:`.

### Stage 5 — Skills for the model

- Deliverable:
  - Turn start: model-visible skills (`model_invocable`), duplicates resolved via
    `_SKILL_CHOICES[s.id]` or a menu once (H14); the catalogue section lists those without
    `arguments`.
  - `activate_skill(name)` (parameter schema `enum` = catalogue names, built per turn): returns
    a header line (`Skill <name>; folder <dir>; related files: …`, relative paths, `SKILL.md`
    excluded) and the body; adds the skill's resolved `allowed-tools` to `turn.auto` and
    `disallowed-tools` to `turn.denied` for the rest of this `agent!` call.
  - `read_skill_related_file(skill, path)`: `path` relative; rejected when absolute, leaving the
    skill folder after `normpath`, or through a symlink leading outside (`_real_path` +
    `_under`); text only (binary refused like `read_file`).
  - `skill_<name>` tools for model-invocable skills with `arguments` (64-char limit, decision
    46): parameters from `SkillArgument`s, deferred (hosted: `_Request.deferred`; client:
    visible to `tool_search`); a call returns the substituted body and activates the skill.
  - `_substitute`: `{{name}}` → value (omitted optional → `default`, else empty); `\{`/`\}` →
    literal braces; unknown `{{x}}` left as is.
  - `tool_search` / `tool_load` and `load_tools!`'s validation read the turn's extra specs
    when `_AGENT_TURN[]` is set.
  - These three tool kinds join `_never_confirm`, `concurrent = false`, group `skills`, never
    registered.
- Files: `src/harness/skills.jl` (new), `src/harness/agent.jl`, `src/chat.jl`,
  `src/builtin_tools/tool_search.jl`, `src/builtin_tools/repl.jl` (`_never_confirm`),
  `src/session.jl` (`load_tools!` turn-awareness), `docs/src/guide/tools.md` (skill tools note).
- Verification (temp workspace with skill `review` from Stage 3 plus a skill `notes` without
  arguments, `allowed-tools: read_file`, `disallowed-tools: run_shell`, and a file
  `notes/ref/a.md`; scripted server; `tool_approval = "all"`, stdin `devnull`):
  ```
  julia --project -e 'using JAIL …
      @assert JAIL._substitute("{{p}} \\{\\{p\\}\\} {{q}}", Dict{String,Any}("p" => "x")) == "x {{p}} {{q}}"
      s = Session(Model(scripted, "m"))
      # server turn: activate_skill("notes") → read_file → run_shell → read_skill_related_file("notes","ref/a.md")
      #              → read_skill_related_file("notes","../../x") → text
      agent!(s, "use notes")
      b = bodies[1]
      @assert occursin("- `notes`", b["instructions"]) && !occursin("- `review`", b["instructions"])
      rs = [r for m in s.messages if m isa ToolResultMessage for r in m.content]
      @assert occursin("related files: ref/a.md", rs[1].content) && !occursin("allowed-tools", rs[1].content)
      @assert !rs[2].is_error                                      # read_file auto-approved by the skill
      @assert rs[3].is_error && occursin("notes", rs[3].content)   # run_shell denied
      @assert !rs[4].is_error && rs[5].is_error
      agent!(s, "again")   # server: read_file → declined now (approval scope ended)
      @assert occursin("declined", last([r for m in s.messages if m isa ToolResultMessage for r in m.content]).content)'
  ```
  Plus: hosted mode request has `skill_review` with `defer_loading: true`; client mode
  (`providers.openai.tool_search = "client"`, restored afterwards) finds it via `tool_search`
  and loads it via `tool_load`; a call `skill_review(path = "src/x.jl")` returns
  "Review src/x.jl to depth 1."; a skill with `disable-model-invocation: true` appears in
  neither the catalogue nor the tools.

### Stage 6 — User-invoked skills and the `&` REPL mode

- Deliverable:
  - `run_skill!(s, name, args...; kwargs...)`: resolves the skill by name (menu if ambiguous),
    requires `user_invocable`, converts positional `args` to argument types, prompts for the
    missing ones (string/number: `readline` showing the hint and default; boolean: `_pick`
    yes/no; bad conversion re-prompts), substitutes, activates the skill for the turn, and runs
    `agent!` with the result as the user message. A skill without `arguments` appends any
    extra text after the body, separated by a blank line.
  - `&` mode (`src/repl/agent_mode.jl`): `initrepl` with `start_key = '&'`,
    `mode_name = "jail_agent"`, prompt function `"(<agent>) agent> "` (`julia` when none),
    `_add_newline_keys!`, streaming per the `stream` Preference, Ctrl-C as in `}`.
    `/clear`, `/help` (lists user-invocable skills with `argument-hint`), `/<skill> [args]`
    through `_split_args` + `run_skill!`; anything else → `agent!`. Tab completes `/` commands
    and skill names.
- Files: `src/harness/skills.jl`, `src/repl/agent_mode.jl` (new), `src/repl/install.jl`,
  `src/JAIL.jl` (export `run_skill!`), `examples/LocalPreferences.toml` (`stream` comment:
  `}` and `&` modes), `docs/src/reference.md`, `docs/src/guide/repl.md` (`&` section).
- Verification:
  ```
  julia --project -e 'using JAIL
      @assert JAIL._split_args("a \"b c\" '\''d e'\'' f") == ["a", "b c", "d e", "f"]
      @assert JAIL._agent_prompt() == "(julia) agent> "'
  ```
  Plus (temp workspace + scripted server): `JAIL._agent_command("/review src/x.jl")` sends a
  user message "Review src/x.jl to depth 1."; `/review` with stdin piped `"src/y.jl\n\n"` prompts
  twice and uses the default for `depth`; `/review x notanint`-style bad conversion for a
  positional integer raises a clear error; `/clear` empties the session; `_complete_agent_mode("/re")`
  offers `/review`. Owner check on a real terminal (`todos/pending/2_REPL_real_terminal_check.md`):
  `&` enters the mode, prompt shows the agent, menus render.

### Stage 7 — Authoring and `|` commands

- Deliverable:
  - `new_agent(name = nothing; description = nothing)`: prompts for missing name/description,
    validates (letters, digits, `-`, `_`, ≤ 64 chars, not `julia`), refuses an existing file,
    writes `<storage_dir>/agents/<name>.agent.md` from a template (front matter: `name`,
    `description`, `tools: []`, `disallowedTools: []`; a body skeleton), calls `_EDITOR[](path)`,
    returns the path. `edit_agent(name = nothing)`: menu of agents when no name, `_EDITOR[]` on
    its file (`julia` → error, no file).
  - `new_skill` / `edit_skill`: same for `<storage_dir>/skills/<name>/SKILL.md` (template front
    matter: `name`, `description`, `when_to_use`, `allowed-tools: []`, `disallowed-tools: []`,
    commented `arguments`/`argument-hint` example).
  - `|` commands: `agents`, `agent select [name|none]` (no arg → menu of a fresh scan),
    `agent new [name]`, `agent edit [name]`, `skills`, `skill new [name]`, `skill edit [name]`;
    help text, `_nargs` usages, completion of subcommands and names.
- Files: `src/harness/authoring.jl` (new), `src/repl/model_mode.jl`, `src/JAIL.jl` (exports
  `new_agent`, `edit_agent`, `new_skill`, `edit_skill`), `docs/src/reference.md`,
  `docs/src/guide/repl.md` (`|` commands).
- Verification:
  ```
  julia --project -e 'using JAIL
      mktempdir() do ws; cd(ws) do
          opened = String[]; JAIL._EDITOR[] = p -> push!(opened, p)
          p = new_agent("rev"; description = "Reviews")
          @assert endswith(p, joinpath(".jail", "agents", "rev.agent.md")) && opened == [p]
          a = only(filter(x -> x.name == "rev", agents())); @assert a.description == "Reviews" && a.source === :storage
          @assert try new_agent("rev"; description = "x"); false catch e; e isa ArgumentError end
          @assert try new_agent("julia"; description = "x"); false catch e; e isa ArgumentError end
          q = new_skill("lint"; description = "Lint"); @assert isfile(q) && only(skills()).name == "lint"
          JAIL._model_command("agent select rev"); @assert active_session().agent == "rev"
          JAIL._model_command("agent select none"); @assert active_session().agent === nothing
      end end'
  ```
  Plus: `agent new` with piped stdin `"x\nA description\n"` creates `x.agent.md`; `agent edit`
  with no name opens the menu; `skills` lists sources.

### Stage 8 — Guide page, example, final sweep

- Deliverable: `docs/src/guide/agents.md` (modes, `agent!`, folders and precedence menu, agent
  and skill front matter keys, alias table, approvals and denials, `/skill` usage, authoring);
  `docs/make.jl` adds it after `guide/tools.md`; `docs/src/index.md` mentions `&`;
  `examples/agents.jl` (temp workspace + scripted server: agent, skill activation, `run_skill!`,
  approvals); a sweep that no doc or example drives tools through `chat!`.
- Files: `docs/src/guide/agents.md` (new), `docs/make.jl`, `docs/src/index.md`,
  `docs/src/guide/{chat,tools,repl,sessions}.md` (cross-links), `examples/agents.jl` (new).
- Verification: `julia --project=docs docs/make.jl` with 0 warnings;
  `julia --project examples/agents.jl` runs unattended; `grep -rn "max_tool_rounds" docs/src examples`
  shows only `agent!` usages.

## Open Questions

- **G1 (NON-BLOCKING until Stage 8; decision gate):** what `count_tokens(s)` and `|` `tokens`
  count once modes exist — the chat request (system, tools used in history), the agent request
  (with the applied agent or `julia`), or both via a new keyword. Until answered, Stage 2 keeps
  today's count (session tools, base system).
- **G2 (NON-BLOCKING):** Claude Code subagents are plain `*.md` files in `.claude/agents/`. The
  owner's rule (`*.agent.md`, `AGENTS.md`, `CLAUDE.md`) skips them. Should any `*.md` in the
  `.claude/agents` folders count as an agent? Plan follows the rule as written.
- **G3 (NON-BLOCKING):** should agents also accept `disallowed-tools` and skills
  `disallowedTools` (each other's spelling)? Plan reads the spellings as specified.

## Risks

- **R1 — providers rejecting `tool_choice` "none" with replayed tool history** (Anthropic
  spec/docs conflict; Vertex Interactions unverified). Cheapest check: the Stage 2 live check
  on each provider before Stages 3+.
- **R2 — YAML key order.** `arguments` order defines positional `/skill` args; if
  `YAML.load(...; dicttype = JSON.Object{Any,Any})` does not preserve order, Stage 3 must stop
  and ask the owner about an `OrderedCollections` dependency (new dependency = owner decision).
- **R3 — per-turn system prompt changes** (skills edited, agent switched) invalidate Anthropic
  prompt-cache prefixes (decision 43) and OpenAI chain reuse is unaffected; cost only.
- **R4 — menus mid-turn in non-interactive runs** (`julia script.jl`, piped stdin): `_pick`
  behaviour off a TTY must be checked in Stage 3; scripts can avoid menus by unique names.
- **R5 — concurrency:** `activate_skill` mutates `_AgentTurn` while parallel calls may run;
  `concurrent = false` plus the turn lock. Check with a parallel batch in Stage 5.
- **R6 — prompt injection via agent/skill files from home folders or a cloned repo's `.github/`**:
  agent `tools` and skill `allowed-tools` auto-approve tools, so a malicious repo file can
  pre-approve `run_shell`. Mitigation in scope: the `&` mode prints the agent's auto-approved
  tools when it is selected and when a skill is activated (`→ skill notes: auto-approves
  read_file`); not eliminated. Flag in the guide.
- **R7 — breaking change:** `chat!(...; max_tool_rounds)` callers get a `MethodError`; scripts
  that relied on `chat!` tools silently get text-only replies. Called out in the Stage 2 docs.
