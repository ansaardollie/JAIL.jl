"""
    ToolParameter

One argument of a [`ToolSpec`](@ref): its `name`, Julia `type`, JSON Schema `schema`, optional
`description` (from the docstring's `# Arguments` section) and whether it is `required`.
"""
struct ToolParameter
    name::String
    type::Type
    schema::Dict{String,Any}
    description::Union{Nothing,String}
    required::Bool
end

"""
    ToolSpec

A function the model may call: the tool `name` the model sees, a `description`, the ordered
positional `parameters`, the function `f` itself, the `group` it is filed under (default
`"global"`), the `label` shown for its calls in the REPL and in `agent!`'s streamed output
(default: the function name as written), its `security` level (`:low`, `:medium`, `:high`, or a
function of the call's arguments returning one), its argument `preview` (`nothing`, one
argument name, several, or a function of the arguments) and whether its calls may run
`concurrent`ly with the other calls of a reply. Build one with [`register_tool!`](@ref)
or [`@tool`](@ref).
"""
struct ToolSpec
    name::String
    description::String
    parameters::Vector{ToolParameter}
    f::Function
    group::String
    label::String
    security::Union{Symbol,Function}
    preview::Union{Nothing,String,Vector{String},Function}
    concurrent::Bool
end

function _signature(io::IO, t::ToolSpec)
    print(io, t.name, "(")
    for (i, p) in enumerate(t.parameters)
        i > 1 && print(io, ", ")
        print(io, p.name)
        p.type === Any || print(io, "::", p.type)
        p.required || print(io, " = …")
    end
    print(io, ")")
end

Base.show(io::IO, t::ToolSpec) = (print(io, "ToolSpec("); _signature(io, t); print(io, ")"))

function Base.show(io::IO, ::MIME"text/plain", t::ToolSpec)
    print(io, "ToolSpec "); _signature(io, t)
    print(io, "\n  group: ", t.group, ", label: ", repr(t.label), ", security: ",
          t.security isa Symbol ? t.security : "by arguments")
    t.preview === nothing ||
        print(io, ", preview: ", t.preview isa Function ? "custom" : join(t.preview isa String ? [t.preview] : t.preview, ", "))
    t.concurrent || print(io, ", runs alone")
    isempty(t.description) || print(io, "\n  ", replace(t.description, "\n" => "\n  "))
    for p in t.parameters
        print(io, "\n  • ", p.name, "::", p.type, p.required ? "" : " (optional)")
        p.description === nothing || print(io, ": ", p.description)
    end
end
