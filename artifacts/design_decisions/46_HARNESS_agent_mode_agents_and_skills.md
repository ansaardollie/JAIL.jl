# Decision: Agent mode (`&`, `agent!`), text-only chat mode, agents and skills

| Field | Value |
|-------|-------|
| Artifact | `46_HARNESS_agent_mode_agents_and_skills.md` |
| Category | design_decisions |
| Subject | `HARNESS` — the agentic harness (agent mode, agent files, skills). `AGENT` is already used for the Copilot planning agent (decisions 22, 23), so a separate tag |
| Date | 2026-10-06 |
| Area/Purpose scope | public API, core ontology (Session), tool loop, providers (tool_choice), Preferences, REPL, dependencies |
| Related | `implementation_plans/2_HARNESS_agent_mode_agents_and_skills.md`, `18_TOOLS_session_tools_and_call_loop.md` (superseded in part), `42_TOOLS_tool_search_and_loaded_tools.md` (superseded in part), `14_REPL_chat_mode.md`, `13_SESSION_default_system_prompt.md`, `24_SESSION_persistence.md`, `30_TOOLS_auto_approvals.md`, `31_TOOLS_builtin_tools_policy.md`, `todos/pending/5_TOOLS_builtin_tools.md` (item 4), redesign notes #5, #7, #8 |
| Status | accepted |
| Decided by | user (requirements message + two question rounds, 2026-10-06); agent (details marked "agent-decided") |

## Context

Redesign note #5 reserves `}` for asking (text) and `&` for agentic work (tools, code-gen).
Decision 18 let the `}` mode and `chat!` run the tool loop, so today chat and agent behaviour are
merged. The owner's request (2026-10-06), in their words:

- "Chat mode refers to setup where only text prompt/responses are allowed. Agent mode refers to
  setup where tools and agentic workflows are allowed."
- "tool use as an entire feature set should be removed from `chat>` repl and chat!() functions."
- "there will now be an agent repl mode (&) as well as an imperative `agent!()` function which
  will add a prompt to the active session and will loop … until no more tool calls are made".
- "Session as ontological concept should be mode agnostic as it represents the provider API state
  with the current/selected context." Chat mode: default/provided system prompt and zero tools.
  Agent mode: system prompt and tools determined by the selected agent and skill definitions.
- Agents: `*.agent.md` / `AGENTS.md` / `CLAUDE.md` in `./.github/agents/`, `./.claude/agents/`,
  `./.copilot/agents/`, `~/.claude/agents/`, `~/.agents/`, `~/.copilot/agents/`,
  `<storage_dir>/agents/`. Skills: the same base folders under `skills/`, plus
  `<storage_dir>/skills/`.
- Applying an agent appends to the system prompt: a short "you are an agent" boilerplate, the
  agent's instructions (body without YAML front matter), and a catalogue (name + description,
  plus `when_to_use`) of skills without `arguments` whose `disable-model-invocation` is not true.
- Built-in tools `activate_skill(name)` (returns SKILL.md body without front matter) and
  `read_skill_related_file(skill, path)` (path relative to the skill folder).
- Agent `tools` → auto-approved while the agent is applied; agent `disallowedTools` → removed
  from the request while applied.
- Activating a skill (by model or user) auto-approves its tools until the next agent turn and
  denies its disallowed tools (not removed from the session).
- Skills with `arguments` are structured tools: added to the session as deferred tools.
- `|` mode: agent `select` / `new` / `edit`, skill `new` / `edit`; new files go in
  `<storage_dir>/agents/<name>.agent.md` and `<storage_dir>/skills/<name>/SKILL.md` from a
  template, then opened with `edit()`.
- `&` prompt `(<agent name>) agent>`; `/<skill name>` commands for user-invocable skills, with
  arguments from the line (space-separated, quotes allowed) or prompted one by one with hints;
  the substituted skill body (`{{argument_name}}`, `\{`/`\}` escapes) becomes the user message.

## Questions and Answers

| # | Question | Options offered | Chosen |
|---|---|---|---|
| H1 | Where "agent X applied to session S" lives | A `Session.agent` name, persisted, file re-read per turn; B internal registry, not persisted; C parsed snapshot on Session | **A** |
| H2 | `&`/`agent!` with no agent applied | built-in default agent `agent`; error; Preference `default_agent` | **free text: "Built in default agent named `julia`"** |
| H3 | `chat!`/`}` on a session whose history has tool calls/results | A flatten tool parts to text; B send the tools used in history with `tool_choice: none`; C lock session to one mode; D no conversion | **B** |
| H4 | YAML front matter parsing | YAML.jl dependency; in-house subset parser | **YAML.jl** |
| H5 | Shape of a skill's `arguments` | A name: description, all required strings; B string or `{description, required, default}`; C fully typed | **C fully typed** |
| H6 | Agent `tools`: also loaded? | yes (auto-approved + loaded); no (auto-approved only) | **yes** |
| H7 | Non-JAIL tool names (`Read`, `Bash(git:*)`, `edit`, …) | JAIL names/groups only; also a built-in alias table | **alias table** (table below accepted as proposed) |
| H8 | Skill approval key | `available-tools` + `allowed-tools`; only `available-tools` | **free text: "Only `allowed-tools` - my message was a mistype"** |
| H9 | Agent names; workspace-root `AGENTS.md`/`CLAUDE.md` | name rule; root files ignored / appended as always-on project instructions | **name rule + root `./AGENTS.md` and `./CLAUDE.md` appended for every agent** |
| H10 | Same name in two folders | workspace > storage_dir > home; storage_dir > workspace > home; menu each time | **menu each time** |
| H11 | `agent!` tool-round limit | keep default 10; raise default to 50; unlimited | **Preference + kwarg, default 50** |
| H12 | Public API (sketch below) | accept; change | **accept as proposed** |
| H13 | Persisted agent name vs duplicate menu | A menu at selection, remember the path; B menu every turn | **A** |
| H14 | Duplicate skill names seen by the model | A menu once at turn start, reused; B menu at call time; C qualified names | **A** |
| H15 | A file agent named `julia` | overrides built-in; joins the menu; reserved, ignored with warning | **reserved: ignored with a warning** |
| H16 | Alias table | accept; change | **accept** |
| H17 | Skill-tool name equals a registered tool | skip with warning; always prefix `skill_<name>`; replace while applied | **always prefix `skill_<name>`** |

## Decision

### Public API (H12)

```julia
agent!(s::Session, prompt; max_tokens = nothing, stream = false, max_tool_rounds = nothing,
       thinking_effort = nothing, temperature = nothing, show_reasoning = nothing) -> AssistantMessage
agent!(prompt; kwargs...)                    # active session
agents() -> Vector{Agent}                    # fresh discovery on every call
skills() -> Vector{Skill}
use_agent!(s, name_or_nothing) -> Union{Agent,Nothing}    # nothing removes the agent
use_agent!(name_or_nothing)                  # active session
current_agent(s) -> Union{Agent,Nothing}
new_agent(name; description) -> String       # <storage_dir>/agents/<name>.agent.md, opened with edit()
edit_agent(name)
new_skill(name; description) -> String       # <storage_dir>/skills/<name>/SKILL.md, opened with edit()
edit_skill(name)
run_skill!(s, name, args...; kwargs...)      # what `/name args` does in `&`

chat!(s, prompt; max_tokens, stream, thinking_effort, temperature, show_reasoning)  # no max_tool_rounds, no tool loop
```

`|` mode: `agents` (list), `agent select [name|none]`, `agent new [name]`, `agent edit [name]`,
`skills` (list), `skill new [name]`, `skill edit [name]`. `&` mode: prompt
`(<agent name>) agent> `, `/<skill name> [args…]`, plus `/clear`, `/help`.

### Session and modes (H1, H2, H3, H13, H15)

- `Session` gains `agent::Union{Nothing,String}` (the name) and the remembered file path of the
  chosen agent; both are saved in the session JSON. Each agent turn re-reads that path; if it is
  gone, the name is resolved again (menu if ambiguous).
- No agent applied → the built-in agent `julia` (boilerplate only). `julia` is reserved: a
  discovered agent file named `julia` is ignored with a warning.
- Chat mode (`chat!`, `}`): system = `s.system`; no tools offered. When the session's history
  holds tool calls (from agent turns), chat requests send the definitions of the tools named in
  that history with `tool_choice` "none", so providers accept the replayed calls/results and the
  model cannot call them.
- Agent mode (`agent!`, `&`): system = `s.system` + boilerplate + root `./AGENTS.md` /
  `./CLAUDE.md` (front matter stripped) + agent instructions + skill catalogue; tools = the
  session's tools minus the agent's `disallowedTools`, with the agent's `tools` loaded and
  auto-approved, plus skill tools (deferred) and `activate_skill` / `read_skill_related_file`.
- `max_tool_rounds` moves from `chat!` to `agent!`; Preference default becomes 50 (H11).

### Agents and skills (H4–H10, H14, H16, H17)

- Front matter parsed with YAML.jl (new dependency).
- Agent name: front matter `name`, else the file stem without `.agent` (`reviewer.agent.md` →
  `reviewer`, `AGENTS.md` → `AGENTS`, `CLAUDE.md` → `CLAUDE`).
- Same name in several folders → terminal menu each time a name is resolved by the user
  (selection, edit, `/name`); for model-facing skills, once at the start of the agent turn, the
  choice reused for the turn and remembered for the session.
- Skill per-skill approvals key: `allowed-tools`; denials: `disallowed-tools`.
- Skill `arguments` (fully typed):

  ```yaml
  arguments:
    path:  {type: string, description: "File to review", required: true}
    depth: {type: integer, description: "How deep", required: false, default: 1}
  argument-hint:
    path: "src/foo.jl"
  ```

  Types: `string`, `integer`, `number`, `boolean`.
- A skill with `arguments` is offered to the model as a deferred tool named `skill_<name>`.
- Tool names in `tools` / `disallowedTools` / `allowed-tools` / `disallowed-tools` may be JAIL
  tool names, `group:<g>`, or aliases from this table (`Tool(pattern)` keeps the tool name; the
  pattern is ignored with a one-time warning):

  | Alias | JAIL |
  |---|---|
  | `Read`, `read`, `read/readFile`, `readFile` | `read_file` |
  | `LS`, `listDirectory` | `list_dir` |
  | `Glob`, `fileSearch`, `search/fileSearch` | `find_files` |
  | `Grep`, `textSearch`, `search/textSearch` | `grep_files` |
  | `search`, `codebase`, `search/codebase` | `group:read` |
  | `Write`, `createFile`, `edit/createFile` | `create_file` |
  | `Edit` | `replace_in_file` |
  | `MultiEdit` | `replace_in_files` |
  | `edit`, `editFiles`, `edit/editFiles` | `group:edit` |
  | `Bash`, `runCommands`, `runInTerminal`, `execute/runInTerminal` | `run_shell` |
  | `execute` | `group:execute` |
  | `runTests`, `execute/runTests` | `run_tests` |
  | `WebFetch`, `fetch`, `web/fetch` | `fetch_url` |
  | `web` | `group:web` |
  | `problems`, `read/problems` | `check_julia_syntax` |
  | `changes`, `search/changes` | `git_changes` |
  | `askQuestions`, `vscode/askQuestions`, `AskUserQuestion` | `ask_user` |
  | `NotebookEdit`, `TodoWrite`, `Task`, `WebSearch`, `todos`, `agent`, `vscode/*`, `github/*`, MCP names | none: warned once, ignored |

### Agent-decided details

- `/<name>` is offered for a skill when `argument-hint` is set or `user-invocable` is not
  `false` (owner's rule, read literally). Built-in `/clear` and `/help` win over a skill of the
  same name (reachable with `run_skill!`).
- A skill with `disable-model-invocation: true` is neither in the catalogue nor a `skill_<name>`
  tool.
- A skill tool name longer than 64 characters (tool-name limit, `src/tools.jl` `_TOOL_NAME`) is
  not offered; warned once.
- Skill name: front matter `name`, else the folder name. Only `SKILL.md` is read.
- `activate_skill`, `read_skill_related_file` and `skill_<name>` tools are never registered,
  never confirmed (like `tool_search`), and cannot be denied. They are loaded only when at least
  one model-invocable skill exists.
- Deny wins over every approval: a call to a tool in an activated skill's `disallowed-tools` gets
  an error result naming the skill.
- The agent's `tools` must also be in the session's tools (`set_tools!` restriction wins);
  names outside it are warned once.
- The "Tool search is available…" line moves from the chat instructions (`_REPL_INSTRUCTIONS`)
  to the agent boilerplate. Sessions created earlier keep their stored text.
- If a chat reply still contains tool calls, they get error results ("tools are off in chat
  mode; use agent!") so history stays valid.

## Rejected

- H1 B/C: an unpersisted registry loses the agent on restore; a snapshot hides file edits.
- H3 A (flattening to text): changes what the provider sees vs. what is stored; C: contradicts
  "session is mode agnostic"; D: Anthropic is believed to reject tool blocks without `tools`.
- H4 in-house parser: nested `arguments` maps make a subset parser fragile.
- H10 fixed precedence orders.
- H15 overriding or joining the menu: `julia` stays a stable fallback.
- H17 skip/replace: prefixing avoids collisions with every current and future tool.

## Consequences

- Supersedes decision 18's "`}` mode uses session tools" and its `chat!` tool loop, and decision
  42's "every `}`/`chat!` session offers all built-ins" (built-ins stay registered; only agent
  mode offers them).
- `chat!(...; max_tool_rounds)` is removed: a breaking change; examples and docs that drive tools
  through `chat!` move to `agent!`.
- Providers gain a `tool_choice` "none" request field. Anthropic's local OpenAPI `ToolChoice`
  (`artifacts/provider_docs/anthropic/api_spec.yaml#L5468-L5480`) lists only auto/any/tool, while
  the docs show `{"type": "none"}` (`artifacts/provider_docs/anthropic/claude-docs/claude-docs-25-define-tools.md#L557`).
- New dependency YAML.jl.
- Sessions with an agent depend on files outside JAIL (agent/skill files); a deleted file falls
  back to name resolution.

## Amendment (2026-10-06, agent-decided during implementation)

- Front matter that is not valid YAML but is one `key: value` per line (e.g. the owner's
  `~/.copilot/agents/julia-programmer.agent.md`, whose `description` contains `: `) is read
  as flat text values instead of skipping the file. Lists/maps in such a block still fail.
- User-invoked skills: with no arguments on the `/name` line (or `run_skill!` call), every
  argument is prompted; with some, only missing required ones are, optionals take their default.
- `agent select` prints the tools the agent auto-approves and leaves out (plan risk R6); a
  user-invoked skill prints its auto-approved tools before the turn.
- `use_agent!(s, "julia")` / `agent select julia` store no agent (`nothing`), same as `none`.
- Skill-tool parameters list required arguments first; an omitted optional followed by a given
  one is an error result (existing `_call_args` rule).

## Revisit Trigger

A provider rejecting `tool_choice` "none" with replayed tool history; agent/skill front matter
formats (Claude Code, VS Code, Agent Skills) adding keys the owner wants; the alias table
missing names seen in practice; the duplicate-name menus becoming a nuisance.
