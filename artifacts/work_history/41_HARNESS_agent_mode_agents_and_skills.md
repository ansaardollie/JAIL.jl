# Agent mode (`&`, `agent!`), text-only chat, agents and skills

| Field | Value |
|-------|-------|
| Artifact | `41_HARNESS_agent_mode_agents_and_skills.md` |
| Category | work_history |
| Subject | `HARNESS` — agentic harness |
| Date | 2026-10-06 |
| Area/Purpose scope | core loop, providers, Session, persistence, REPL, docs, examples |
| Related | `implementation_plans/2_HARNESS_agent_mode_agents_and_skills.md` (all 8 stages), `design_decisions/46_HARNESS_agent_mode_agents_and_skills.md` (+ amendment), `todos/pending/5_TOOLS_builtin_tools.md` (item 4 done), `todos/pending/12_HARNESS_live_checks_and_gates.md` |

## Scope of This Unit of Work

Follows `40_TOOLS_parallel_line_separator.md`. Owner asked to plan, then implement, the agentic
harness: text-only chat mode, agent mode (`agent!`, `&`), agent files, skills, `|` commands.

## What Changed

| File | Change |
|-------|--------|
| `src/ontology/requests.jl`, `src/providers/{openai,openai_compatible,anthropic,google}.jl`, `src/tokens.jl` | `_Request.tool_choice` (`:auto`/`:none`); "none" sent per provider (citations in code and plan) |
| `src/chat.jl` | `_Mode` / `_ChatMode` / `_AgentMode`, `_turn_system`, `_turn_tools`; `chat!` text only (history tools + `tool_choice` none; stray calls answered with an error); `agent!`, `_agent!`; `max_tool_rounds` default 50 |
| `src/harness/frontmatter.jl` (new) | `_frontmatter` (YAML.jl, ordered via `JSON.Object`; flat `key: value` fallback), `_name_list`, alias table `_TOOL_ALIASES`, `_resolve_tool_refs`, `_ref_names` |
| `src/harness/discovery.jl` (new) | `Agent`, `Skill`, `SkillArgument`, `agents()`, `skills()`, folders, `julia` built-in/reserved, `_by_name` + `_CHOOSER` menu hook |
| `src/harness/agent.jl` (new) | `_AGENT_BOILERPLATE`, `_AgentTurn`, `_AGENT_TURN`, `use_agent!`, `current_agent`, system composition (root `AGENTS.md`/`CLAUDE.md`), `_turn_verdict`, `_turn_pool` |
| `src/harness/skills.jl` (new) | catalogue, `activate_skill`, `read_skill_related_file`, `_SkillTool` (`skill_<name>`), `_substitute`, argument parsing/prompting, `run_skill!` |
| `src/harness/authoring.jl` (new) | `new_agent`, `edit_agent`, `new_skill`, `edit_skill`, templates, `_EDITOR` hook |
| `src/repl/agent_mode.jl` (new), `src/repl/install.jl` | `&` mode: prompt `(<agent>) agent> `, `/<skill>`, `/clear`, `/help`, completion |
| `src/repl/model_mode.jl` | `agents`, `agent select\|new\|edit`, `skills`, `skill new\|edit`, completion |
| `src/repl/chat_mode.jl` | `_display_turn(...; mode)`, box title `Agent (<agent>): <session>` |
| `src/tools.jl`, `src/builtin_tools/{repl,tool_search}.jl` | turn verdicts (deny / auto) in `_prepare_tool` and `_confirmation_needed`; skill tools never confirmed; `tool_search`/`tool_load` see turn tools |
| `src/session.jl`, `src/persistence.jl` | `Session.agent`, `Session.agent_path`, saved/restored; `agent:` status row |
| `src/system_prompt.jl` | tool-search line moved to the agent boilerplate |
| `Project.toml` | `YAML` dep, compat `0.4` (via `Pkg.add` + `Pkg.compat`) |
| docs | new `guide/agents.md`; chat/tools/repl/sessions/providers/index/reference/builtin_tools updated; `size_threshold_warn = 150 KiB` in `docs/make.jl` |
| examples | new `examples/agents.jl`; tool examples moved to `agent!`; `LocalPreferences.toml` (`max_tool_rounds = 50`, `stream`, `storage_dir` comments) |

## Design Decisions Made

Decision 46 (two question rounds) and its 2026-10-06 amendment (lenient front matter, argument
prompting rule, approval printing, `julia` = no agent). Decisions 18 and 42 marked superseded in part.

## Verification

Stage 1 (fresh REPL): `_request_body` asserts for OpenAI, compatible (chat completions),
Anthropic (none and auto+disable_parallel), Google Interactions and generateContent → `"stage 1 ok"`.

Stages 2–7 against a scripted Responses server (`HTTP.serve!`, bodies recorded), temp
`storage_dir`, temp `HOME`, `_workspace_root` pointed at a temp folder:
```
"stage 2 ok"   # chat: no tools; agent: tool loop + boilerplate; chat after agent: tools ["get_weather"], tool_choice none; MethodError for max_tool_rounds on chat!; stray chat tool call → error result
"stage 3 ok"   # names/sources, julia reserved, aliases ["read_file","run_shell","group:edit"], typed ordered arguments, duplicate menu, malformed file skipped
"stage 4 ok"   # use_agent!, AGENTS.md without front matter, agent instructions, read_file loaded, create_file removed, verdicts under "all", restore keeps agent, path re-resolution, "no longer found"
"stage 5 ok"   # catalogue + enum, activate_skill header/body, allowed read_file, run_shell "Denied: the skill `notes` does not allow `run_shell`.", related file ok / ../../x refused, approvals end with turn, client tool_search → tool_load → skill_review "Review src/x.jl to depth 1.", hosted defer_loading, disable-model-invocation hidden, menu once per session
"stage 6 ok"   # _split_args, prompt text, /review, prompting via IO, bad integer, /notes extra text, /clear, completion, run_skill!
"stage 7 ok"   # new_agent/new_skill paths + editor hook, name checks, agent select/none/menu, edit, agents/skills listings, completion
```
`LocalPreferences.toml` byte-identical after the checks and after each example.

Examples run offline: `examples/agents.jl`, `examples/tool_search.jl`,
`examples/parallel_tool_calls.jl`, `examples/tools.jl` (offline part). Excerpt of `agents.jl`:
```
chat request tools: none
current_agent(s) = Agent("reviewer", storage)
system prompt has the agent: true, lists the skill: true
loaded tools include read_file: true, run_shell sent: false
chat request: tools ["activate_skill"], tool_choice none
prompt sent: Review src/x.jl to depth 1.
misuse: ArgumentError: argument `depth` must be an integer, got "not-a-number"
```
Docs: `julia --project=docs docs/make.jl` → exit 0, no warnings.

Not verified: any live provider call (risk R1: Anthropic `tool_choice` none with replayed tool
blocks); the `&` mode on a real terminal; `examples/tool_security.jl` and
`examples/builtin_tools.jl` (need terminal answers).

## Known Limitations

- `count_tokens` / `| tokens` count the chat-era tool set (`_request_tools`), not an agent turn (gate G1).
- Skill-tool labels show the raw name (`activate_skill`) in tool lines; `_tool_label` only knows registered tools.
- Front matter fallback handles only flat `key: value` blocks.
- `.github/agents/jail-planner.agent.md` shows as modified in git; not changed by this work.

## Todos

- Completed: `5_TOOLS_builtin_tools.md` (item 4, the `&` mode; moved to `todos/completed/`).
- Created: `12_HARNESS_live_checks_and_gates.md`.

## Next Steps

- Live check per provider: `agent!` one tool turn, then `chat!` on the same session.
- Owner: answer G1–G3 (plan "Open Questions").
- Real-terminal check of `&` (prompt, `/` completion, menus, streaming).
