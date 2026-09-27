# Interactive model selection and the `|` model REPL mode

| Field | Value |
|-------|-------|
| Artifact | `2_REPL_model_selection_mode.md` |
| Category | work_history |
| Subject | `REPL` |
| Date | 2026-09-27 |
| Area/Purpose scope | public API, REPL surface |
| Related | `1_PROVIDER_providers_and_model_selection.md`, `design_decisions/7_MODEL_interactive_selection.md`, `design_decisions/8_REPL_model_mode.md` |

## Scope of This Unit of Work

The user asked for `select_model!()` (TerminalMenus: provider, then model) and a Pkg-style model
REPL mode built with ReplMaker. Builds on work_history 1 (providers, `list_models`, default model).

## What Changed

| File | Change |
|-------|--------|
| `Project.toml` | via Pkg: added `REPL` stdlib; removed the standalone `TerminalMenus` v0.1.0 that had appeared in `[deps]` (the user chose the stdlib) |
| `src/JAIL.jl` | imports `REPL`, `REPL.TerminalMenus`, `ReplMaker`; exports `select_model!`; includes `select.jl`, `repl/model_mode.jl`, `repl/install.jl` |
| `src/select.jl` | `select_model!()`, `select_model!(p)`; internal `_select_model!(…, term)`, `_pick`, `_provider_labels`, `_key_note`, `_fetch_models` (+ `_MODEL_ID_CACHE`), `_print_error`, `_menu_terminal` |
| `src/repl/model_mode.jl` | `_model_prompt`, `_model_command` + `_MODEL_COMMANDS` table (`status/st`, `providers`, `models`, `select`, `use`, `help/?`), `_model_mode_parser`, `_complete_model_mode` |
| `src/repl/install.jl` | `__init__` → `_try_install_repl_modes` (now, or via `atreplinit`), `repl_modes` Preference opt-out, `_REPL_INSTALLED` guard |
| `examples/model_selection.jl` | menus behind `const INTERACTIVE = false`; REPL-mode transcript in comments; missing-key misuse |

## Design Decisions Made

See `7_MODEL_interactive_selection.md` and `8_REPL_model_mode.md`. Agent-level:
`_select_model!` takes the terminal as an argument so menus can be driven by a fake terminal;
the REPL layer only parses and prints, and every command calls a public function.

## Verification

REPL, Julia 1.13.0:

- After `using JAIL`: `_REPL_INSTALLED[] == true`; the mode prompts include `"(no model) model> "`;
  `'|'` bound in the julia-mode keymap.
- Commands against a local `HTTP.serve!` stub registered as `OpenAICompatible("stub", …)`:
  `help`, `st`, `providers`, `models stub` (3 models), `use stub/llama-3.1-8b` → prompt became
  `(stub/llama-3.1-8b) model> `, `models` marked `* llama-3.1-8b`.
- Misuse output (stderr): `ERROR: expected "provider/model" …`, `unknown provider "nope" …`,
  ``select` opens a menu; … use `use stub/qwen3:8b` ``, `unknown command `frobnicate`; type `help``,
  `usage: `models [provider]``, `no model selected; name a provider, e.g. `models anthropic``.
- Menus with a fake `TTYTerminal` fed `BufferStream` keys: provider pick (index 4 = stub), model
  pick, `q` → `nothing` with default unchanged, cursor starts on the current default, two-step
  `_select_model!(term)` flow, missing-key provider → error printed, `nothing`.
- Completion: `c("s") == (["select","st","status"], "s")`, `c("use an") == (["anthropic/"], "an")`,
  `c("use stub/ll") == (["stub/llama-3.1-8b"], "stub/ll")`, no candidates for uncached providers.
- `repl_modes = false` + restart → not installed, `'|'` unbound.
- `examples/model_selection.jl` ran in a fresh REPL; it caught `TerminalMenus.terminal` being
  undefined on Julia 1.13 (fixed with `_menu_terminal()` → `default_terminal()`).

Not verified: a real keyboard session in the `|` mode or the real-terminal menus (the tool REPL
cannot take keystrokes); live provider listing.

## Known Limitations

- OpenAI's list includes non-chat models (embeddings, TTS, images); no filtering.
- Model-id completion only works after a provider's models have been listed in this process.
- No REPL commands for `register_provider!` / `configure_provider!` yet.
- The `repl_modes` opt-out is all-or-nothing and read only at load time.

## Todos

- Completed: none
- Created: none

## Next Steps

1. Owner tries `|` mode and `select_model!()` in a real terminal.
2. Decide the test-suite layout and port the fake-terminal and command checks into tests.
3. Session type design (the `}` and `&` modes need it).
