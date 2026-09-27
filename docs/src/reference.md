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
Base.empty!(::Session)
sessions
active_session
new_session!
use_session!
delete_session!
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
```
