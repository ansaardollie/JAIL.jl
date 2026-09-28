# Decision: Tool definitions, the tool registry and `@tool`

| Field | Value |
|-------|-------|
| Artifact | `17_TOOLS_definitions_and_registry.md` |
| Category | design_decisions |
| Subject | `TOOLS` |
| Date | 2026-09-28 |
| Area/Purpose scope | core ontology, public API |
| Related | `12_MESSAGES_types_and_chat.md`, `9_SESSION_session_type.md` |
| Status | accepted |
| Decided by | user (all public choices below); agent (schema mapping, method selection, docstring cleanup) |

## Context

First tools step: define tools and keep them in a registry; no wire format or call loop yet.
User request: "a `register_tool(f::Function)` function which takes a function input and
reads/reflect on the function to extract the parameters/arguments needed as well the description
from docs and then creates a metadata object and adds it to a central registry in the module of
all tools available. There should also be a `@tool` macro ... `@tool func_name1 func_name2
func_name3`". Redesign #8 asked for docstrings *inside* the function body.

Verified in the REPL (Julia 1.13): an in-body string literal is dropped by lowering
(`code_lowered` shows no trace), so a `Function` object only exposes its standard docstring.

All three providers describe a tool as name + description + JSON Schema for the arguments:
OpenAI `FunctionTool` (`artifacts/provider_docs/openapi/api_spec.yaml#L79526-L79575`), Anthropic
`Tool` (`artifacts/provider_docs/anthropic/api_spec.yaml#L5059-L5103`, name pattern
`^[a-zA-Z0-9_-]{1,64}$`), Google Interactions `Function`
(`artifacts/provider_docs/google/interactions.openapi.json#L5093-L5115`).

## Questions and Answers

| Question | Options | Chosen |
|---|---|---|
| Description source | A standard docstring; B in-body docstring via re-parsing the source file; C both (`@tool function ... end` form) | **A** (B fails for REPL-defined functions; C can be added later) |
| Registration function name | `register_tool!`; `register_tool` | **`register_tool!`** (matches `register_provider!`) |
| Metadata type | `Tool`; `ToolSpec`; `ToolDefinition` | **`ToolSpec`** |
| Per-argument descriptions | parse the `# Arguments` docstring section; none | **parse `# Arguments`** |
| Untyped (`::Any`) arguments | error; any JSON value; treat as string | **any JSON value** (empty schema) |
| Keyword arguments | error; ignore with a warning | **ignore with a warning** |
| Names containing `!` | error; strip; replace with `_bang` | **replace with `_bang`** (`save!` → `save_bang`) |
| Registry accessors | `tools()`; `unregister_tool!(name)`; none | **`tools()` and `unregister_tool!`** |

## Decision

```julia
struct ToolParameter          # not exported
    name::String; type::Type; schema::Dict{String,Any}
    description::Union{Nothing,String}; required::Bool
end
struct ToolSpec
    name::String; description::String; parameters::Vector{ToolParameter}; f::Function
end
register_tool!(f::Function) -> ToolSpec      # replaces a tool of the same name
@tool f1 f2 Mod.f3                           # -> Vector{ToolSpec}
tools() -> Vector{ToolSpec}                  # sorted by name
unregister_tool!(name_or_function) -> ToolSpec
```

Agent-decided details:

- Registry: module-level `Dict{String,ToolSpec}` keyed by tool name. Re-registering the same
  name replaces the entry (Revise-friendly); a *different* function taking the name warns.
- Method selection: the method with the most positional arguments. Every other method must be
  a prefix of it in both argument types and names (the shape `f(a, b = 1)` produces); arguments
  beyond the shortest method are optional. Varargs, zero methods, or unrelated methods throw.
- Tool name: `string(nameof(f))` with `!` → `_bang`, validated against the Anthropic pattern.
  Invalid names (anonymous functions, Unicode) throw.
- Description: all docstrings of the function's binding, joined; a leading indented signature
  block and the `# Arguments` section are removed. No docstring → empty description + warning.
- Schema mapping: `Any` → `{}`; `Bool` → boolean; `Integer` → integer; `Real` → number;
  `AbstractString`/`Symbol` → string; `Enum` → string enum; `AbstractVector{T}` → array;
  `AbstractDict{<:Union{String,Symbol},V}` → object with `additionalProperties`;
  `Union{Nothing,T}` → `anyOf [T, null]`; other unions → `anyOf`; concrete structs → object
  (fields containing `Nothing` not required). Anything else throws naming the argument.
- Schemas are provider-agnostic JSON Schema; per-provider conversion (e.g. OpenAI `strict`)
  happens in the provider layer later.

## Rejected

- In-body docstrings (redesign #8): not recoverable from a `Function`; re-parsing source breaks
  for REPL/eval'd definitions.
- Erroring on untyped arguments / kwargs / `!` names: user preferred permissive behavior.

## Consequences

- Tool-call execution maps JSON arguments back to Julia values using `ToolParameter.type`.
- A `name =` override is not available; functions with invalid names must be renamed.

## Revisit Trigger

A request for in-body docstrings or `@tool function ... end`, a provider rejecting the empty
schema used for untyped arguments, or a need for per-session tool sets separate from the registry.
