"""
    AbstractMessage

One entry in a conversation's history. Concrete message types come with the request/response
work; a [`Session`](@ref) stores them as `Vector{AbstractMessage}`.
"""
abstract type AbstractMessage end
