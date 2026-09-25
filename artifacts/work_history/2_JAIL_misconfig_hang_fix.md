# Fix hang on queries with missing or invalid config

| Field | Value |
|-------|-------|
| Artifact | `2_JAIL_misconfig_hang_fix.md` |
| Category | work_history |
| Subject | `JAIL` — request error handling, streaming reader |
| Date | 2026-09-25 |
| Area/Purpose scope | `src/brain.jl`, `src/models.jl` |
| Related | `1_JAIL_package_overview.md` |

## Scope of This Unit of Work

Bug report: with an unset or invalid `JAIL_config`, a query in the `}` REPL mode hung with no error, and Ctrl+C killed the whole Julia process. Goal: any such query raises a clear error.

## Root Causes

1. **Infinite busy loop in the streaming reader** (`src/brain.jl`, `(m::AIBrain)(question)`). The loop condition was `while (EOF_signal > 10) || !eof(io)`, which is inverted. A bad-key error response is a multi-line JSON body. Every line maps to `""` through `getAnswer`, so the repeat counter `EOF_signal` passes 10 and the loop never exits. `readavailable` on an exhausted stream does not yield, so the scheduler is starved. This is why Ctrl+C could not interrupt cleanly.
2. **Errors in the `@async` request task were silent.** The channels were never closed, so `take!(channel)` in `showStreamStringFromChannel` blocked forever.
3. **HTTP.jl 2.8 is resolved** (`Project.toml` has no HTTP compat bound). The old calls used `timeout=` and `headers=` keywords, which 2.x rejects with a `MethodError`. So every request failed, and the failure was then swallowed by (2).
4. **The non-stream path swallowed errors**: it ran `@error ...` and then returned `Brain`.

## What Changed

| File | Change |
|-------|--------|
| `src/models.jl` | Added `checkConfig(m::modelProvider)`. It errors if the model/api/url is empty or still set to the `__init__` placeholders (`noModel` / `noAPI`). |
| `src/brain.jl` | `AIBrain` call now runs `checkConfig(m.model)` first. |
| `src/brain.jl` | Streaming: the async body is wrapped in `try/catch`. On failure it calls `close(channel, ex)` and `close(channel2, ex)` so `take!` rethrows in the caller. After `startread`, `r.status == 200 \|\| error("HTTP $(r.status): <body>")`. Loop condition fixed to `EOF_signal <= 10 && !eof(io)`. |
| `src/brain.jl` | Non-stream: the catch now throws `error("JAIL request failed, please check the config ...: <cause>")`. |
| `src/brain.jl` | HTTP calls use the 2.x forms: `HTTP.open(:POST, url, headers; read_idle_timeout, connect_timeout, retry=false)` and `HTTP.post(url, headers, body; ...)`. The deprecated `readtimeout` was replaced because it printed a warning. |

## Design Decisions Made

- Status check inside the do-block: HTTP 2.x raises `StatusError` only after the do-block returns, which is too late because the reader loop runs first.
- `close(ch, ex)` was chosen over a sentinel value. It needs no changes in `showStreamStringFromChannel` or `streamToMemory`.
- Rejected: adding an HTTP `[compat]` bound. It changes dependencies and was left for the user to decide.

## Verification

Local fake servers (`HTTP.serve!`) plus a real Gemini call, in the REPL:

```
JAIL is not configured. Set ENV["JAIL_config"] before loading, or call JAIL.setapi("provider|model|apiOrURL").
JAIL request failed, please check the config (provider|model|apiOrURL): HTTP 400: {"error": "bad key"} ...
JAIL request failed, please check the config (provider|model|apiOrURL): http connect error to 127.0.0.1:1: connect tcp -> 127.0.0.1:1: SystemError: connect: Connection refused
JAIL request failed, please check the config (provider|model|apiOrURL): http status error: 400 for POST http://127.0.0.1:18765/api/generate
"# Final Output\n\ntok1 tok2 tok3 tok4 tok5 \n"          # happy-path streaming still works
JAIL request failed, please check the config (provider|model|apiOrURL): HTTP 400: { "error": { "code": 400, "message": "API key not valid. ..."
```

The user confirmed that in the interactive `}` mode the error now appears and nothing hangs.

## Known Limitations

- There is no HTTP `[compat]` entry. The new keywords (`read_idle_timeout`) are 2.x-specific, so HTTP 1.x would likely break. The fix is `Pkg.compat("HTTP", "2")`.
- `setapi` with fewer than three `|`-separated parts fails with an unhelpful `BoundsError`.
- `checkMemory!` references the undefined `AI_API_KEY` and will throw once `m.memory` passes 3000 chars. This bug predates this work.
- On a failed streaming query, the question has already been pushed to `m.history["ask"]` and `m.memory`, so `ask`/`ans` lengths get out of sync.
- No automated tests exist; verification was manual.

## Todos

- Completed: none
- Created: none

## Next Steps

1. Decide on and add an HTTP compat bound: `using Pkg; Pkg.compat("HTTP", "2")`.
2. Fix `checkMemory!` (`AI_API_KEY` is undefined; build the temp brain from `m.model`).
3. Validate the `setapi` input format with a clear error.
4. Add a `test/` suite using `HTTP.serve!` fake servers, reusing the cases above.
