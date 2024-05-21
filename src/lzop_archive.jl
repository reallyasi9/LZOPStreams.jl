const LZOP_MAGIC_NUMBER = (0x89, 0x4c, 0x5a, 0x4f, 0x00, 0x0d, 0x0a, 0x1a, 0x0a)

struct LZOPArchiveSource{T <: IO}
    headers::Vector{Pair{Int,LZOPFileHeader}}
    io::BufferedInputStream{T}
end

function Base.iterate(source::LZOPArchiveSource, state::Int = 0)
    return state + 1, next_file(source)
end
Base.IteratorSize(::Type{LZOPArchiveSource}) = Base.SizeUnknown()
Base.IteratorEltype(::Type{LZOPArchiveSource}) = Base.HasEltype()
Base.eltype(::Type{LZOPArchiveSource{T}}) where {T} = LZOPFileSource{T}
Base.isdone(source::LZOPArchiveSource) = eof(source.io)

function next_file(source::LZOPArchiveSource)
    if isempty(source.headers)
        # check for magic number
        magic = zeros(UInt8, length(LZOP_MAGIC_NUMBER))
        n = readbytes!(source.io, magic)
        if n != length(LZOP_MAGIC_NUMBER)
            throw(ErrorException("failed to read LZOP magic number from beginning of archive: expected $(length(LZOP_MAGIC_NUMBER)) bytes, only read $n"))
        end
        if any(magic .!= LZOP_MAGIC_NUMBER)
            throw(ErrorException("failed to read LZOP magic number from beginning of archive: expected $(LZOP_MAGIC_NUMBER), read $(tuple(magic...))"))
        end
    end
    start = position(source.io)
    header = read(source.io, LZOPFileHeader)
    push!(source.headers, start => header)
    return LZOPFileSource(header, io)
end

function next_file(f::F, source::LZOPArchiveSource) where {F <: Function}
    io = next_file(source)
    val = f(io)
    close(io)
    return val
end

struct LZOPArchiveSink{T <: IO}
    headers::Vector{Pair{Int,LZOPFileHeader}}
    io::BufferedOutputStream{T}
end

function create_file(sink::LZOPArchiveSink, name::AbstractString = ""; kwargs...)
    header = LZOPFileHeader() # TODO: make header from kwargs
    if isempty(sink.headers)
        # write magic number
        write(sink.io, LZOP_MAGIC_NUMBER)
    end
    start = position(sink.io)
    push!(sink.headers, start => header)
    return LZOPFileSink(header, io)
end

function create_file(f::F, sink::LZOPArchiveSink, name::AbstractString = ""; kwargs...) where {F <: Function}
    io = create_file(sink, name; kwargs...)
    val = f(io)
    close(io)
    return val
end