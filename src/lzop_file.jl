struct LZOPFileSource{T <: IO} <: IO
    header::LZOPFileHeader
    io::T
end

Base.isreadonly(::LZOPFileSource) = true
Base.iswritable(::LZOPFileSource) = false
Base.isreadable(::LZOPFileSource) = true

function Base.read(source::LZOPFileSource, ::Type{T}) where {T}
    # I need an LZOPCodec here
end

struct LZOPFileSink{T <: IO} <: IO
    header::LZOPFileHeader
    io::T
end

Base.isreadonly(::LZOPFileSink) = false
Base.iswritable(::LZOPFileSink) = true
Base.isreadable(::LZOPFileSink) = false

function Base.open(sink::LZOPFileSink; kwargs...) end
function Base.open(f::F, sink::LZOPFileSink; kwargs...) where {F <: Function}
    io = open(sink; kwargs...)
    val = f(io)
    close(io)
    return val
end