# Agents and skills

JAIL talks to a model in two modes over the same [`Session`](@ref):

| | Chat mode | Agent mode |
|---|---|---|
| Julia | [`chat!`](@ref) | [`agent!`](@ref), [`run_skill!`](@ref) |
| REPL | `}` (`chat> `) | `&` (`(julia) agent> `) |
| System prompt | the session's `system` | the session's `system`, then the agent-mode additions below |
| Tools | none | the session's tools, shaped by the agent and active skills |

The history is shared, so a conversation can move between the modes. Chat turns after agent
turns send the tools named in the history only so the provider accepts the replayed calls,
with `tool_choice` set to "none" (see [Chat](chat.md)).

## Agent turns

[`agent!`](@ref) sends a prompt and runs the model's tool calls until a reply calls none (at
most `max_tool_rounds` rounds, default 50). Approval, parallel calls and tool search work as
described in [Tools](tools.md).

```julia
s = Session("anthropic/claude-sonnet-4-5")
agent!(s, "Find where `chat!` is defined and summarise what it does.")
agent!(s, "Now add a docstring example to it."; stream = true)
```

The system prompt of an agent turn is, in order:

1. the session's `system` instructions;
2. a short preamble saying the model is working as an agent (keep going with tools until done,
   adapt to declined calls, use tool search);
3. `AGENTS.md` and `CLAUDE.md` in the current directory, if present, without YAML front matter
   (project instructions for every agent);
4. the applied agent's instructions;
5. the list of skills the model can activate (name, description and `when_to_use`).

## Agents

An agent is a Markdown file with optional YAML front matter. [`agents`](@ref) finds them, fresh
on every call, in:

| Where | Folders |
|---|---|
| workspace (current directory) | `.github/agents/`, `.claude/agents/`, `.copilot/agents/` |
| JAIL's `storage_dir` | `<storage_dir>/agents/` |
| home | `~/.claude/agents/`, `~/.agents/`, `~/.copilot/agents/` |

Files named `*.agent.md`, `AGENTS.md` or `CLAUDE.md` are agents. The name is the front matter
`name`, else the file name without `.agent.md` / `.md`. Names may repeat across folders;
choosing one by name then shows a menu. `julia` is the built-in agent (no instructions, no tool
keys) used when a session has none; a file agent named `julia` is ignored with a warning.

```markdown
---
name: reviewer
description: Reviews changes before they are committed
tools: [read_file, grep_files, git_changes]   # loaded, and run without asking
disallowedTools: [run_shell]                   # left out of the session's tools
---

Review the uncommitted changes. Point out bugs first, style last. Never edit files.
```

Apply one with [`use_agent!`](@ref) (or `agent select` in the `|` mode). It stays with the
session (and is saved with it) until changed; the file is read again on every turn, so edits
apply at once.

```julia
use_agent!(s, "reviewer")     # a menu when several files are named "reviewer"
current_agent(s)              # Agent("reviewer", workspace)
agent!(s, "Review my changes.")
use_agent!(s, nothing)        # back to `julia`
```

While an agent is applied:

- `tools`: these tools are loaded (the model sees them in full) and run without asking,
  whatever their security level, except that the built-in path tools still ask for paths
  outside the workspace (unless in `path_allow_list`) and for writes to protected paths. They
  must be among the session's tools (see [`set_tools!`](@ref)).
- `disallowedTools`: these tools are left out of the request.

`agent select` prints both lists, since an agent file from a cloned repository can approve
tools such as `run_shell`.

## Skills

A skill is a folder with a `SKILL.md` file, found by [`skills`](@ref) in the `skills/` folder of
the same places: `.github/skills/`, `.claude/skills/`, `.copilot/skills/`,
`<storage_dir>/skills/`, `~/.claude/skills/`, `~/.agents/skills/`, `~/.copilot/skills/`. The
name is the front matter `name`, else the folder name.

| Front matter key | Meaning |
|---|---|
| `name`, `description` | What the model and the user see |
| `when_to_use` | Added to the description in the model's skill list |
| `allowed-tools` | Tools that run without asking once the skill is active, until the turn ends (path tools still ask outside the workspace and for protected writes) |
| `disallowed-tools` | Tools refused (with an error result) once the skill is active, until the turn ends |
| `arguments` | Typed arguments (below); makes the skill a tool for the model |
| `argument-hint` | A hint per argument (a mapping), or one hint string for `/help` |
| `user-invocable` | `false` hides `/name` in the `&` mode (unless `argument-hint` is set) |
| `disable-model-invocation` | `true` hides the skill from the model |

The model uses skills through tools JAIL adds to agent turns (never confirmed):

- `activate_skill(name)`: for skills without `arguments`, listed in the system prompt. Returns
  the skill's folder, its other files and its instructions (without front matter), and makes it
  active.
- `read_skill_related_file(skill, path)`: a file inside the skill's folder (`path` relative to
  it; paths leaving the folder are refused).
- `skill_<name>(...)`: one per skill with `arguments`, found through tool search. Returns the
  instructions with the arguments filled in, and makes the skill active.

### Arguments

```markdown
---
name: review
description: Review one file
arguments:
  path:  {type: string, description: "File to review"}
  depth: {type: integer, description: "How deep", required: false, default: 1}
argument-hint:
  path: src/foo.jl
allowed-tools: read_file, grep_files
---

Review {{path}} to depth {{depth}}. Write \{\{literal braces\}\} like this.
```

Types are `string` (default), `integer`, `number` and `boolean`; `required` defaults to `true`.
`{{name}}` is replaced by the argument's value (an omitted optional one by its `default`, else
nothing); `\{` and `\}` are literal braces.

### Running a skill yourself

In the `&` mode, `/review src/chat.jl 2` runs the skill: its filled-in instructions are sent as
the prompt of an agent turn, with the skill active. Arguments are separated by spaces;
`"..."` or `'...'` keep spaces. With no arguments, each is asked for on the terminal (empty
input keeps an optional one's default); with some, only the missing required ones are. For a
skill without `arguments`, any text after `/name` is added after its instructions. From Julia:

```julia
run_skill!(s, "review", "src/chat.jl", 2)
```

## Writing agents and skills

[`new_agent`](@ref) and [`new_skill`](@ref) (or `agent new` / `skill new` in the `|` mode)
create a file from a template in `storage_dir` and open it with `edit` (your `JULIA_EDITOR`);
[`edit_agent`](@ref) and [`edit_skill`](@ref) open an existing one.

```julia
new_agent("reviewer"; description = "Reviews changes")   # .jail/agents/reviewer.agent.md
new_skill("review"; description = "Review one file")      # .jail/skills/review/SKILL.md
edit_skill("review")
```

## Tool names in front matter

`tools`, `disallowedTools`, `allowed-tools` and `disallowed-tools` take a YAML list or a
comma-separated string of JAIL tool names, `group:<group>` entries, or the Claude Code /
VS Code names below. `Tool(pattern)` (e.g. `Bash(git:*)`) uses just the tool; the pattern is
ignored with a warning. Unknown names are ignored with a warning.

| Name | JAIL |
|---|---|
| `Read`, `read`, `read/readFile`, `readFile` | `read_file` |
| `LS`, `listDirectory` | `list_dir` |
| `Glob`, `fileSearch`, `search/fileSearch` | `find_files` |
| `Grep`, `textSearch`, `search/textSearch` | `grep_files` |
| `search`, `codebase`, `search/codebase` | the `read` group |
| `Write`, `createFile`, `edit/createFile` | `create_file` |
| `Edit` | `replace_in_file` |
| `MultiEdit` | `replace_in_files` |
| `edit`, `editFiles`, `edit/editFiles` | the `edit` group |
| `Bash`, `runCommands`, `runInTerminal`, `execute/runInTerminal` | `run_shell` |
| `execute` | the `execute` group |
| `runTests`, `execute/runTests` | `run_tests` |
| `WebFetch`, `fetch`, `web/fetch` | `fetch_url` |
| `web` | the `web` group |
| `problems`, `read/problems` | `check_julia_syntax` |
| `changes`, `search/changes` | `git_changes` |
| `askQuestions`, `vscode/askQuestions`, `AskUserQuestion` | `ask_user` |
