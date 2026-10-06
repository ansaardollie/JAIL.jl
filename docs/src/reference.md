# Reference

```@meta
CurrentModule = JAIL
```

## Providers

```@docs
AbstractProvider
AbstractOpenAIProvider
OpenAI
Anthropic
Google
GoogleEnterprise
OpenAICompatible
configure_provider!
register_provider!
providers
```

## Models

```@docs
AbstractModel
Model
list_models
select_model!
set_default_model!
default_model
```

## Sessions

```@docs
Session
set_model!
use_provider!
set_thinking_effort!
set_temperature!
Base.empty!(::Session)
sessions
active_session
new_session!
use_session!
delete_session!
restore_session!
```

## Messages and chat

```@docs
chat!
AbstractMessage
UserMessage
AssistantMessage
Usage
AbstractContentPart
TextPart
ReasoningPart
ToolSearchPart
ToolCall
ToolResult
ToolResultMessage
```

## Token counting

```@docs
count_tokens
TokenCount
```

## Tools

```@docs
ToolSpec
ToolParameter
register_tool!
@tool
tools
tools(::Session)
set_tools!
load_tools!
unload_tools!
tool_status
unregister_tool!
tool_approval
set_tool_approval!
tool_auto_approvals
set_tool_auto_approval!
security_level
needs_confirmation
tool_preview
builtin_tools
register_builtin_tools!
ToolContext
tool_context
```

The built-in tools themselves are documented in [Built-in tools](builtin_tools.md).
