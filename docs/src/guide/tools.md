# Tools

A tool is an ordinary Julia function that a model may ask JAIL to call. Registering a function
reflects on it and stores a [`ToolSpec`](@ref) in JAIL's tool registry. Every session offers
the registered tools to its model, and [`chat!`](@ref) runs the calls the model makes.

## Defining a tool

Write a normal, documented function and register it with [`register_tool!`](@ref):

```@example tools
using JAIL

"""
    get_weather(city, days = 3)

Get the weather forecast for a city.

# Arguments
- `city`: the city name, e.g. "Cape Town"
- `days`: how many days to forecast
"""
get_weather(city::String, days::Int = 3) = "Sunny for $days days in $city"

register_tool!(get_weather)
```

What the model sees comes from the function:

| Part | Source |
|------|--------|
| name | the function name; `!` becomes `_bang` (`save!` → `save_bang`) |
| description | the docstring, without its signature line and `# Arguments` section |
| parameters | the positional arguments; ones with default values are optional |
| parameter descriptions | the entries of the docstring's `# Arguments` section |

Keyword arguments are not exposed (JAIL warns). Functions with several unrelated methods,
varargs, or anonymous functions can't be tools.

The description is read from the ordinary docstring *above* the function. A string placed
inside the function body is discarded by Julia when the function is compiled, so JAIL can't
see it.

## Argument types

Argument types become JSON Schema:

| Julia type | JSON Schema |
|------------|-------------|
| `Bool` | `boolean` |
| `Integer` | `integer` |
| `Real` | `number` |
| `AbstractString`, `Symbol` | `string` |
| `@enum` types | `string` with `enum` of the instance names |
| `AbstractVector{T}` | `array` of `T` |
| `AbstractDict{String,V}` | `object` with values of `V` |
| `Union{Nothing,T}` | `T` or `null` |
| concrete structs | `object` with one property per field |
| untyped (`Any`) | any JSON value |

Other types (e.g. `IO`, `Function`) throw an `ArgumentError` naming the argument.

## Several at once

[`@tool`](@ref) registers each named function:

```@example tools
"Add an item to the to-do list."
add_todo!(title::String, tags::Vector{String} = String[]) = "added $title"

"Return whatever value the model sends."
echo(value) = value

@tool add_todo! echo
```

## The registry

Tools are keyed by name. Registering a name again replaces the earlier tool.
[`tools`](@ref) lists them and [`unregister_tool!`](@ref) removes one, by name or function:

```@example tools
tools()
```

```@example tools
unregister_tool!("echo")
unregister_tool!(add_todo!)
tools()
```

## Tools on a session

A session offers every registered tool, including ones registered after it was created.
[`tools(session)`](@ref tools(::Session)) lists them; [`set_tools!`](@ref) restricts the
session to a subset (by function or name), `[]` gives it none, and `nothing` goes back to all:

```@example tools
s = Session("anthropic/claude-sonnet-4-5"; name = "weather")
set_tools!(s, [get_weather])
```

```@example tools
set_tools!(s, nothing)
s
```

`Session(model; tools = [...])` and `new_session!(; tools = [...])` restrict from the start. In
the `|` REPL mode, `tools use`, `tools add`, `tools drop`, `tools all` and `tools none` do the
same for the active session (see [REPL modes](repl.md)).

## The tool loop

When a reply contains [`ToolCall`](@ref)s (`stop_reason = :tool_use`), `chat!`:

1. runs each call in order, converting the JSON arguments to the parameter types (omitted
   optional arguments use the function's defaults);
2. appends a [`ToolResultMessage`](@ref) with one [`ToolResult`](@ref) per call;
3. sends the history again, and repeats until a reply calls no tools.

Every step stays in `session.messages` and the last reply is returned. Problems the model can
fix are sent back as error results instead of being thrown: an unknown tool, invalid
arguments, or an exception inside the tool (its message is included). If a request fails, the
whole turn is removed from the history.

A tool's return value becomes text for the model: strings as they are, plain data (numbers,
vectors, dictionaries, structs without a custom `show`) as JSON, anything else as its
`text/plain` display.

```julia
s = Session("anthropic/claude-sonnet-4-5"; tools = [get_weather])
reply = chat!(s, "Should I pack an umbrella for Paris?")
s.messages   # UserMessage, AssistantMessage (get_weather call), ToolResultMessage, AssistantMessage
chat!(s, "And Rome?"; stream = true)   # also prints → call and ← result lines
```

## Preferences

- `max_tool_rounds` (default 10): tool rounds per `chat!` call. When it is reached, further
  calls are answered with "not run" error results and the last reply is returned with
  `stop_reason = :tool_use`. `chat!(...; max_tool_rounds = n)` overrides it for one call.
- `confirm_tools` (default `false`): ask `Run get_weather(city = "Paris")? [y/N]` on the
  terminal before each call; a declined call is reported to the model.

```toml
[JAIL]
max_tool_rounds = 5
confirm_tools = true
```
