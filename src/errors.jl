const Optional{T} = Union{T,Nothing}

struct LZOException <: Exception
    code::Int
end
struct OutOfMemoryException <: Exception
    input_index::Optional{Int}
    output_index::Optional{Int}
end
struct NotCompressibleException <: Exception
end
struct InputOverrunException <: Exception
    input_index::Optional{Int}
    input_length::Optional{Int}
    command::Optional{Vector{UInt8}}
end
struct OutputOverrunException <: Exception
    input_index::Optional{Int}
    output_index::Optional{Int}
    output_length::Optional{Int}
    command::Optional{Vector{UInt8}}
end
struct LookbehindOverrunException <: Exception
    input_index::Optional{Int}
    output_index::Optional{Int}
    command::Optional{Vector{UInt8}}
end
struct EndOfStreamNotFoundException <: Exception
end
struct InputNotConsumedException <: Exception
    input_index::Optional{Int}
    input_length::Optional{Int}
end

function Base.showerror(io::IO, e::LZOException)
    print(io, "code ", e.code, ": generic exception")
end

function Base.showerror(io::IO, e::OutOfMemoryException)
    print(io, "code -2: out of memory exception")
    isnothing(e.input_index) || print(io, " reading input byte ", e.input_index)
    isnothing(e.output_index) || print(io, " writing output byte ", e.output_index)
end

function Base.showerror(io::IO, ::NotCompressibleException)
    print(io, "code -3: input not compressible exception")
end

function Base.showerror(io::IO, e::InputOverrunException)
    print(io, "code -4: input overrun exception")
    isnothing(e.input_index) || print(io, " reading input byte ", e.input_index)
    isnothing(e.input_length) || print(io, " from input of length ", e.input_length)
    isnothing(e.command) || print(io, " while processing command ", e.command)
end

function Base.showerror(io::IO, e::OutputOverrunException)
    print(io, "code -5: output overrun exception")
    isnothing(e.input_index) || print(io, " reading input byte ", e.input_index)
    isnothing(e.output_index) || print(io, " writing output byte ", e.output_index)
    isnothing(e.output_length) || print(io, " to output of length ", e.output_length)
    isnothing(e.command) || print(io, " while processing command ", e.command)
end

function Base.showerror(io::IO, e::LookbehindOverrunException)
    print(io, "code -6: lookbehind overrun exception")
    isnothing(e.input_index) || print(io, " reading input byte ", e.input_index)
    isnothing(e.output_index) || print(io, " copying from output byte ", e.output_index)
    isnothing(e.command) || print(io, " while processing command ", e.command)
end

function Base.showerror(io::IO, ::EndOfStreamNotFoundException)
    print(io, "code -7: end of stream not found exception")
end

function Base.showerror(io::IO, e::InputNotConsumedException)
    print(io, "code -8: input not consumed exception")
    isnothing(e.input_index) || print(io, " finishing at input byte ", e.input_index)
    isnothing(e.input_length) || print(io, " from input of length ", e.input_length)
end