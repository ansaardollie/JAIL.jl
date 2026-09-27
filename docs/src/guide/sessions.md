# Sessions

A [`Session`](@ref) holds one conversation: a `name`, the active `model`, optional `system`
instructions, and the typed message history in `messages`.

!!! note
    Sending messages isn't implemented yet, so `messages` is always empty for now.

## The default session

When JAIL loads it starts a session called `"default"` and makes it the **active session**.
Its model is the saved default model. If none is saved (or the saved one can't be used), it
starts with no model.

These docs are built with no default model saved when JAIL loads, so:

```@example sessions
using JAIL

active_session()
```

Saving a default doesn't change sessions that already exist; it applies to new sessions, and
to `"default"` the next time JAIL loads:

```@example sessions
set_default_model!("openai/gpt-5")
active_session()
```

## Creating sessions

```@example sessions
s = Session("anthropic/claude-sonnet-4-5"; name = "review", system = "Be terse.")
```

The detailed display:

```@example sessions
show(stdout, MIME"text/plain"(), s)
```

Without a model, the saved default is used. It's an error if none is saved.

```@example sessions
Session()
```

Every session is **registered**, so the REPL can list it and switch to it.
- A session without a name is called `"session"`.
- A name that's already taken gets a suffix.
- Names may contain letters, digits, `.`, `_` and `-`.

```@example sessions
Session("anthropic/claude-sonnet-4-5"; name = "review")
```

```@example sessions
sessions()
```

Sessions stay registered, and in memory, until [`delete_session!`](@ref).

## Changing a session's model

[`set_model!`](@ref) switches the model and keeps the history. Other sessions and the saved
default are unaffected:

```@example sessions
set_model!(s, "google/gemini-3.8-flash")
s
```

```@example sessions
default_model()
```

`empty!(s)` clears the history and keeps the model and system instructions. To pick a model
from menus, use `select_model!(s)` (see [Models](models.md)).

## The active session

The REPL modes and session-less calls such as `select_model!()` act on the
[`active_session`](@ref).

```@example sessions
w = new_session!("work"; model = "anthropic/claude-sonnet-4-5")   # create and activate
active_session() === w
```

```@example sessions
use_session!("review")        # by name, or pass the Session
active_session().name
```

```@example sessions
use_session!("default");
delete_session!("review-2")
[x.name for x in sessions()]
```

## Common errors

```@example sessions
try
    delete_session!(active_session())
catch e
    showerror(stdout, e)
end
```

```@example sessions
try
    use_session!("nope")
catch e
    showerror(stdout, e)
end
```

```@example sessions
try
    Session("openai/gpt-5"; name = "my work")
catch e
    showerror(stdout, e)
end
```

```@example sessions
try
    s.messages = AbstractMessage[]    # history can be emptied, not replaced
catch e
    showerror(stdout, e)
end
```
