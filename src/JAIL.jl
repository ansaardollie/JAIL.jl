module JAIL

using Dates: Dates, DateTime
using HTTP: HTTP
using JSON: JSON
using Markdown: Markdown
using Preferences: load_preference, set_preferences!, delete_preferences!
using REPL: REPL
using REPL.TerminalMenus: TerminalMenus, RadioMenu, request
using ReplMaker: initrepl, FunctionCompletionProvider
using UUIDs: UUID, uuid7, uuid_version

export AbstractProvider, AbstractOpenAIProvider, OpenAI, OpenAICompatible, Anthropic, Google, GoogleEnterprise
export AbstractModel, Model
export configure_provider!, register_provider!, providers
export set_default_model!, default_model, list_models, select_model!
export AbstractMessage, Session, set_model!, use_provider!
export AbstractContentPart, TextPart, ReasoningPart, UserMessage, AssistantMessage, Usage, chat!
export sessions, active_session, new_session!, use_session!, delete_session!, restore_session!
export ToolSpec, register_tool!, @tool, tools, unregister_tool!, set_tools!
export tool_approval, set_tool_approval!, security_level, needs_confirmation, tool_preview
export tool_auto_approvals, set_tool_auto_approval!
export ToolCall, ToolResult, ToolResultMessage

include("preferences.jl")
include("ontology/providers.jl")
include("ontology/models.jl")
include("ontology/messages.jl")
include("ontology/tools.jl")
include("ontology/requests.jl")
include("http.jl")
include("gcp_auth.jl")
include("providers/openai.jl")
include("providers/openai_compatible.jl")
include("providers/anthropic.jl")
include("providers/google.jl")
include("configuration.jl")
include("system_prompt.jl")
include("tools.jl")
include("session.jl")
include("persistence.jl")
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