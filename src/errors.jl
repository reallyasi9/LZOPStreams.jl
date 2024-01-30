const Optional{T} = Union{T,Nothing}

struct LZOException <: Exception
    code::Int
    message::String
end
struct OutOfMemoryException <: Exception
    input_index::Optional{Int}
    output_index::Optional{Int}
end
OutOfMemoryException() = OutOfMemoryException(nothing, nothing)
struct NotCompressibleException <: Exception
end
struct InputOverrunException <: Exception
    input_index::Optional{Int}
    input_length::Optional{Int}
    command::Optional{AbstractVector{UInt8}}
end
InputOverrunException() = InputOverrunException(nothing, nothing, nothing)
struct OutputOverrunException <: Exception
    input_index::Optional{Int}
    output_index::Optional{Int}
    output_length::Optional{Int}
    command::Optional{AbstractVector{UInt8}}
end
OutputOverrunException() = OutputOverrunException(nothing, nothing, nothing, nothing)
struct LookbehindOverrunException <: Exception
    input_index::Optional{Int}
    output_index::Optional{Int}
    command::Optional{AbstractVector{UInt8}}
end
LookbehindOverrunException() = LookbehindOverrunException(nothing, nothing, nothing)
struct EndOfStreamNotFoundException <: Exception
end
struct InputNotConsumedException <: Exception
    input_index::Optional{Int}
    input_length::Optional{Int}
end
InputNotConsumedException() = InputNotConsumedException(nothing, nothing)
struct CommandEncodeException <: Exception
    message::String
    command::Optional{AbstractVector{UInt8}}
end
CommandEncodeException(message::AbstractString) = CommandEncodeException(message, nothing)
struct CommandDecodeException <: Exception
    message::String
    data::Optional{AbstractVector{UInt8}}
end
CommandDecodeException(message::AbstractString) = CommandDecodeException(message, nothing)

function Base.showerror(io::IO, e::LZOException)
    print(io, "code ", e.code, ": ", e.message)
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

function Base.showerror(io::IO, e::CommandEncodeException)
    print(io, "command encode exception")
    isnothing(e.command) || print(io, " while encoding command ", e.command)
    print(io, ": ", e.message)
end

function Base.showerror(io::IO, e::CommandDecodeException)
    print(io, "command decode exception")
    isnothing(e.data) || print(io, " while decoding data ", e.data)
    print(io, ": ", e.message)
end