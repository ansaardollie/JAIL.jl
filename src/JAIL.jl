module JAIL

using HTTP: HTTP
using JSON: JSON
using Markdown: Markdown
using Preferences: load_preference, set_preferences!, delete_preferences!
using REPL: REPL
using REPL.TerminalMenus: TerminalMenus, RadioMenu, request
using ReplMaker: initrepl, FunctionCompletionProvider

export AbstractProvider, AbstractOpenAIProvider, OpenAI, OpenAICompatible, Anthropic, Google
export AbstractModel, Model
export configure_provider!, register_provider!, providers
export set_default_model!, default_model, list_models, select_model!
export AbstractMessage, Session, set_model!, use_provider!
export AbstractContentPart, TextPart, UserMessage, AssistantMessage, Usage, chat!
export sessions, active_session, new_session!, use_session!, delete_session!
export ToolSpec, register_tool!, @tool, tools, unregister_tool!, set_tools!
export ToolCall, ToolResult, ToolResultMessage

include("preferences.jl")
include("ontology/providers.jl")
include("ontology/models.jl")
include("ontology/messages.jl")
include("ontology/tools.jl")
include("ontology/requests.jl")
include("http.jl")
include("providers/openai.jl")
include("providers/openai_compatible.jl")
include("providers/anthropic.jl")
include("providers/google.jl")
include("configuration.jl")
include("system_prompt.jl")
include("tools.jl")
include("session.jl")
include("chat.jl")
include("select.jl")
include("repl/model_mode.jl")
include("repl/chat_mode.jl")
include("repl/install.jl")

function __init__()
    _start_default_session!()
    _init_repl_modes()
end

end