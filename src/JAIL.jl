module JAIL
using HTTP, JSON3, Markdown
using ReplMaker: initrepl

include("models.jl")
include("brain.jl")

const DEFAULT_PROMPT = "if the answer contains code, only output the raw code in julia"

const PROVIDERS = ["gemini", "ollama", "openai", "openai-compatible", "anthropic"]

const CONFIG_HELP = """
JAIL is not configured. Set these environment variables before `using JAIL`:

| Variable | Meaning |
|---|---|
| `JAIL_PROVIDER` | one of $(join("`" .* PROVIDERS .* "`", ", ")) |
| `JAIL_MODEL` | model name, e.g. `gemini-2.0-flash`, `qwen2.5:72b`, `gpt-4o-mini` |
| `JAIL_BASE_URL` | server URL; optional for `ollama` (`http://localhost:11434`) and `openai` (`https://api.openai.com`) |
| `JAIL_API_KEY` | API key; optional for local servers. OpenAI providers also read `OPENAI_API_KEY`, then `OPENAPI_API_KEY`; `gemini` reads `GEMINI_API_KEY`; `anthropic` reads `ANTHROPIC_API_KEY` |
| `JAIL_CHAT_COMPLETIONS` | `true` to use `/v1/chat/completions` instead of the default `/v1/responses` API (`openai`, `openai-compatible` only) |

or configure it at runtime, where omitted keywords fall back to the variables above:
```julia
JAIL.setapi("ollama", "qwen2.5:72b")
JAIL.setapi("openai-compatible", "gpt-oss-20b"; url = "http://localhost:8000", api = "local-key")
JAIL.setapi("anthropic", "claude-3-5-sonnet-20241022"; api = "your-api-key")
```
"""

const Brain = AIBrain(model = NotConfigured(), prompt = DEFAULT_PROMPT)

function __init__()
    try
        if haskey(ENV, "JAIL_PROVIDER")
            setapi(ENV["JAIL_PROVIDER"], get(ENV, "JAIL_MODEL", ""))
        elseif haskey(ENV, "JAIL_config")
            @warn "ENV[\"JAIL_config\"] is deprecated, set JAIL_PROVIDER, JAIL_MODEL, JAIL_BASE_URL and JAIL_API_KEY instead."
            setapi(ENV["JAIL_config"])
        else
            display(Markdown.parse(CONFIG_HELP))
        end
    catch err
        @error "JAIL configuration from the environment failed; call JAIL.setapi to configure it." exception = err
    end

    isinteractive() || return
    initrepl(s -> :($(@__MODULE__).Brain($s));
             prompt_text="ask ai> ",
             prompt_color=104,
             start_key='}',
             mode_name=:askai,
            )

end


"""
```julia
setapi(provider, model; url = nothing, api = nothing, chat_completions = nothing)
```
Configure the provider and clear the conversation (see `reset`). `url` and `api` that are `nothing` fall back to `ENV["JAIL_BASE_URL"]`
and `ENV["JAIL_API_KEY"]`; OpenAI providers then use `OPENAI_API_KEY` or `OPENAPI_API_KEY` (see `JAIL.CONFIG_HELP`). `openai`/`openai-compatible` use the Responses API;
`chat_completions = true` switches to chat completions, and `nothing` falls back to `ENV["JAIL_CHAT_COMPLETIONS"]`, default `false`.
```julia
setapi("ollama", "qwen2.5:72b")
setapi("gemini", "gemini-2.0-flash"; api = "your-key")
setapi("openai", "gpt-4o-mini")  # reads OPENAI_API_KEY
setapi("openai-compatible", "gpt-oss-20b"; url = "http://localhost:8000")
setapi("openai-compatible", "gpt-oss-20b"; url = "http://localhost:8000", chat_completions = true)
setapi("anthropic", "claude-3-5-sonnet-20241022")  # reads ANTHROPIC_API_KEY
```
"""
function setapi(provider::AbstractString, model::AbstractString; url = nothing, api = nothing, chat_completions = nothing)
    provider = lowercase(strip(provider))
    provider in PROVIDERS || throw(ArgumentError("unknown provider \"$(provider)\", expected one of: $(join(PROVIDERS, ", "))"))
    model = String(strip(model))
    url = String(something(url, get(ENV, "JAIL_BASE_URL", provider == "openai" ? get(ENV, "OPENAI_BASE_URL", "") : "")))
    api = String(something(api, get(ENV, "JAIL_API_KEY",
        provider in ("openai", "openai-compatible") ? get(ENV, "OPENAI_API_KEY", get(ENV, "OPENAPI_API_KEY", "")) :
        provider == "gemini" ? get(ENV, "GEMINI_API_KEY", "") :
        provider == "anthropic" ? get(ENV, "ANTHROPIC_API_KEY", "") : "")))
    if provider == "gemini"
        Brain.model = Gemini(model, api)
    elseif provider == "ollama"
        Brain.model = Ollama(model, isempty(url) ? "http://localhost:11434" : url)
    elseif provider == "anthropic"
        Brain.model = Anthropic(model=model, url=isempty(url) ? "https://api.anthropic.com" : url, api=api)
    else
        isempty(url) && provider == "openai" && (url = "https://api.openai.com")
        chat_completions = something(chat_completions, lowercase(strip(get(ENV, "JAIL_CHAT_COMPLETIONS", ""))) in ("1", "true", "yes"))
        Brain.model = OpenAICompatible(model=model, url=url, api=api, chat_completions=chat_completions)
    end
    reset()
    return nothing
end

"""
Deprecated `"provider|model|apiOrURL"` form; for OpenAI-compatible providers the third field is `key@url`.
"""
function setapi(config::AbstractString)
    Base.depwarn("setapi(\"provider|model|apiOrURL\") is deprecated, use setapi(provider, model; url, api).", :setapi)
    parts = split(config, "|")
    length(parts) == 3 || throw(ArgumentError("expected \"provider|model|apiOrURL\", got $(length(parts)) field(s)"))
    provider, model, apiOrURL = String.(strip.(parts))
    provider = lowercase(provider)
    if provider == "gemini"
        return setapi(provider, model; url = "", api = apiOrURL)
    elseif provider == "ollama"
        return setapi(provider, model; url = apiOrURL, api = "")
    end
    config = split(apiOrURL, "@"; limit=2)
    api = length(config) == 2 ? String(config[1]) : get(ENV, "JAIL_key", "")
    url = length(config) == 2 ? String(config[2]) : apiOrURL
    return setapi(provider, model; url = url, api = api)
end


"""
Clear the conversation: history, memory and RAG context. The provider, prompt, and
`stream`/`timeout` settings are kept.
```julia
JAIL.reset()
```
"""
function reset()
    Brain.memory = ""
    Brain.rag = ""
    foreach(empty!, values(Brain.history))
    return nothing
end


"""
get the answer from the AI
## example
```julia
@ai "fit a linear model"
# or you can concatenate your question
@ai "fit a" + "linear model"
```
"""
macro ai(expr)
    return :(Brain($(_question_expr(expr))))
end

# `@ai "a" + "b"` concatenates the parts; anything else is converted with `string`
function _question_expr(expr)
    if Meta.isexpr(expr, :call) && expr.args[1] == :+
        return :(string($(esc.(expr.args[2:end])...)))
    end
    return :(string($(esc(expr))))
end


"""
execute the string as code in `Main.playground`

```julia
"1 + 1" |> JAIL.run_code

(@ai "1 + 1") |> JAIL.run_code
```
"""
run_code(x) = include_string(Main.playground,replace(string(x), "```julia" => "", "```" => ""))


"""
similar to `@ai`,

send the question to AI but @AI perform the code directly and only return the result, or error :(


the conversation history will stored in the `JAIL.Brain.history`
## example:
```julia
@AI "tell me the current time, used the package you need"
```
"""
macro AI(expr)
    return :(_ask_and_run($(_question_expr(expr))))
end

function _ask_and_run(question::AbstractString)
    if !isdefined(Main, :playground)
        msg = """
please run
```julia
module playground end
```
to add the module to the Main scope, which will be used by @AI to call julia code
"""
        Markdown.parse(msg) |> display
        return nothing
    end
    stream = Brain.stream
    Brain.stream = false # the code is executed, not displayed, so streaming is pointless
    try
        Brain(question)
    finally
        Brain.stream = stream
    end
    return run_code(Brain.history["ans"][end])
end

@deprecate avaliableModels(args...; kws...) available_models(args...; kws...)
@deprecate changeModels!(m, model) change_model!(m, model)
@deprecate exe(x) run_code(x) false
Base.@deprecate_binding modelProvider ModelProvider false
Base.@deprecate_binding ollama Ollama false

export setapi, @ai, @AI, available_models, change_model!
end
