
# Overview

AskAI.jl, as its name suggests, is a straightforward tool for querying Large Language Models.
It supports Ollama, Google's Gemini API, and OpenAI-compatible chat-completions APIs, including locally hosted models. It is designed to be simple and direct: send prompts and questions to an AI provider, and optionally execute the included code within a sandboxed "playground" to avoid affecting the main scope.

The main macro, `@ai`, retrieves results from a large language model, while `@AI` executes the code within the "playground" scope and displays the output(or any errors.)

a REPL mode was also support. Press `}` to enter and backspace to exit


![AskAI](./overview.png)


!!! note
    AskAI is configured with the environment variables `ASK_AI_PROVIDER` (`gemini`, `ollama`, `openai` or `openai-compatible`), `ASK_AI_MODEL`, `ASK_AI_BASE_URL` (optional for `ollama` and `openai`) and `ASK_AI_API_KEY` (optional for local servers; `openai` also reads `OPENAI_API_KEY`, `gemini` reads `GEMINI_API_KEY`). Alternatively call `setapi(provider, model; url, api)`, where omitted keywords fall back to those variables. The old `ENV["AskAI_config"] = "provider|model|key@url"` form is deprecated. Please also add a module called `playground`: `module playground end` in your main scope if you want to use the `@AI` macro.

!!! note
    A local OpenAI-compatible server must expose `/v1/models` and `/v1/chat/completions`. The URL may be a full URL (with or without `/v1`) or a bare hostname.

    ```julia
    ENV["ASK_AI_PROVIDER"] = "openai-compatible"
    ENV["ASK_AI_MODEL"] = "gpt-oss-20b"
    ENV["ASK_AI_BASE_URL"] = "http://localhost:8000"
    using AskAI

    available_models()
    @ai "Reply with one sentence about Julia."
    AskAI.Brain.stream = false # optional: disable streaming
    ```

    AskAI includes the current terminal rows and columns in each prompt and asks the model to
    wrap output to the available width (`AskAI.Brain.terminal_hint = false` disables this). This is guidance for the model, not a hard output limit.
    Oversized Markdown tables are also converted to wrapped labeled entries before display.

!!! note
    A convenient way is to put below code in your Julia `startup.jl` configuration file.
    ```
    ENV["ASK_AI_PROVIDER"] = "ollama"
    ENV["ASK_AI_MODEL"] = "qwen2.5:72b"
    module playground end
    using AskAI
    ```
    then you can use the AskAI in every session by default


it starts as my persional AI tool in julia REP and only support the Gemini model currently. have fun with it and I welcome your suggestions and input for AskAI.jl!!!

# installation

```julia
(@v1.10) pkg> add https://github.com/AIBioLab/AskAI 
julia> using AskAI
# now you can configure it with your AI model provider; eg ollama
julia> setapi("ollama", "glm4:latest")
# or Gemini
julia> setapi("gemini", "gemini-2.0-flash"; api = "your API key")
# or a local OpenAI-compatible server
julia> setapi("openai-compatible", "gpt-oss-20b"; url = "http://localhost:8000", api = "your-local-api-key")
```

!!! note
   by default the response mode is stream, it should work well, however you can always change it by set `AskAI.Brain.stream = false`.

# quickly example
Here's an example of using AskAI to generate scatter and histogram plots and perform basic statistical calculations.
```julia 
@AI "tell me the current date, use the pacakge when in need"
@AI "create a new project in /tmp, name it as demo + date, activate it"
@AI "load my data as df, the data file is in /tmp/celldata.csv"
@AI "tell me the data size"
@AI "does the data contain columns named geneX and  geneY??"
@AI "install the package to support figure display in the terminal"
@AI "plot a scatter plot of geneX and geneY, I want the geneX on axis Y"
@AI "please also label the axis"
@AI "calculate the correlation of geneX and geneY"
@AI "keep only 3 digits"
@AI "generate a histogram to show the distribution of geneX "
@AI "do the same to geneY"
@AI "fit a linear model to predict value of geneY from geneX,using GLM"
@AI "give me the coef of geneX in this model,keep 5 digits"
```


## Output Results are here 

!!! details 
    ![result1](./result1.png)
    ![result2](./result2.png)
    ![result3](./result3.png)

!!! note
    some time you may get the wrong result from the LLM, LLM results aren't always perfect, so please double-check. You can use `@ai` instead of `@AI` for code checks. then use `AskAI.run_code()` to perform the code. Often the case I met is the necessary packages aren't installed.
    ```julia
    @ai "tell me the current date,install the package if it needs"
    AskAI.run_code(ans)
    ```

to review the conversation history
```julia
AskAI.Brain.history["ask"] 
AskAI.Brain.history["ans"] 

# review the last response 
AskAI.Brain.history["ans"][end] |> AskAI.MD
```


you can also try the stream mode under terminal
```julia
AskAI.Brain.stream = true
@ai "why the sky is blue"
```


# function and macro
```@autodocs
Modules = [AskAI]
Pages   = ["AskAI.jl", "brain.jl"]
```

