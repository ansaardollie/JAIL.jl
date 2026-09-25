module AskAI
using HTTP, JSON3, Markdown
using ReplMaker: initrepl

include("models.jl")
include("brain.jl")

prompt_to_get_code = "if the answer contains code, only output the raw code in julia"

AskAI_config="provider|model|apiOrURL"

# AI_API_KEY = "API key not set"

function __init__()
    global AI_Provider,AI_Model,AI_URL_Or_API

    ######################################
    # check for the required AI_API_KEY  #
    ######################################
    if haskey(ENV, "AskAI_config")
        setapi(ENV["AskAI_config"])
    else
        msg = """
AskAI_config is needed. please set it as an environment variable, follow the rule: "provider|model|api" :
```julia
# for Gemini
ENV["AskAI_config"]="Gemini|gemini-2.0-flash|1234567890abcdef1234567890abcdef"

# for ollama
ENV["AskAI_config"]="ollama|qwen2.5:72b|http://localhost:11434"

# for a local OpenAI-compatible server
ENV["AskAI_config"]="openai-compatible|gpt-oss-20b|your-local-api-key@http://localhost:8000"
# A URL-only third field uses ENV["AskAI_key"] as a backward-compatible fallback.

```

or set it through function `setapi()`
```julia
$(@__MODULE__).setapi("Gemini|gemini-2.0-flash|1234567890abcdef1234567890abcdef")
# or
$(@__MODULE__).setapi("ollama|qwen2.5:72b|http://localhost:11434")
# or a local OpenAI-compatible server using key@url in the third field
$(@__MODULE__).setapi("openai-compatible|gpt-oss-20b|your-local-api-key@http://localhost:8000")
```
"""
        setapi("Gemini|noModel|noAPI|")
        display(Markdown.parse(msg))
    end

    isinteractive() || return
    initrepl(s -> Main.eval(Meta.parse("AskAI.@ai \"$s\""));
             prompt_text="ask ai> ",
             prompt_color=104,
             start_key='}',
             mode_name=:askai,
            )

end


"""
```julia
setapi("ollama|modelName|URL")
setapi("gemini|modelName|api")
setapi("openai-compatible|modelName|key@URL")
```
"""
function setapi( api::String )
    provider, model, apiOrURL = split(api,"|")
    provider = lowercase(provider)
    @assert lowercase(provider) in ["gemini", "ollama", "openai", "openai-compatible"]
    if provider == "gemini"
        global Brain = AIBrain( model = Gemini(model,apiOrURL), prompt = prompt_to_get_code  )
    elseif provider == "ollama"
        global Brain = AIBrain( model = ollama(model,apiOrURL), prompt = prompt_to_get_code  )
    else
        config = split(apiOrURL, "@"; limit=2)
        api = length(config) == 2 ? config[1] : get(ENV, "AskAI_key", "")
        baseurl = length(config) == 2 ? config[2] : apiOrURL
        global Brain = AIBrain( model = OpenAICompatible(model=model, baseurl=baseurl, api=api), prompt = prompt_to_get_code  )
    end
end


"""
Reset the AskAI, it will remove the conversation history, memory, prompt... and everything as default defined
```julia
AskAI.reset()
```
"""
function reset()
   global Brain = AIBrain(model = Brain.model,prompt = Brain.prompt)

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
    if isa(expr,String)
        return  :(Brain($expr))
    end

    # Create a list to hold the concatenated parts
    parts = []

    # Iterate over the arguments of the expression
    for arg in expr.args
        # Push each argument to the parts list
        push!(parts, esc(arg))
    end

    # Create the expression to call f with the concatenated string
    return :(Brain(string($(Expr(:call, Symbol("string"), parts...)))))
end


"""
execute the string as code

```julia
"1 + 1" |> AskAI.exe

(@ai "1 + 1") |> AskAI.exe
```
"""
exe(x) = include_string(Main.playground,replace(string(x), "```julia" => "", "```" => ""))


"""
similar to `@ai`,

send the question to AI but @AI perform the code directly and only return the result, or error :(


the conversation history will stored in the `AskAI.Brain.history`
## example:
```julia
@AI "tell me the current time, used the package you need"
```
"""
macro AI(expr)
    if !isdefined(Main, :playground)
        msg = """
please run
```julia
module playground end
```
to add the module to the Main scope, which will be used by @AI to call julia code
"""
        Markdown.parse(msg) |> display
    else
        # does not support stream mode
        # tmp = Brain.stream
        Brain.stream = false
        :( exe($(@ai($(expr)))))
        # Brain.stream = tmp; # recover the stream setting
        # res
    end
end

export setAPI, @ai, @AI, avaliableModels, changeModels!
end
