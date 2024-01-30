
"""
    LZO1X1FastDecompressorCodec <: TranscodingStreams.Codec

A struct that decompresses data using liblzo1 library version of the LZO 1X1 algorithm.

The LZO 1X1 algorithm is a Lempel-Ziv lossless compression algorithm. Compressed streams consist of alternating encoded instructions and sequences of literal values. The encoded instructions tell the decompressor to either:
1. copy a sequence of bytes of a particular length directly from the input to the output (literal copy), or
2. look back a certain distance in the already returned output and copy a sequence of bytes of a particular length from the output to the output again.

The C implementation of LZO defined by liblzo2 requires that all decompressed information be available in working memory at once, and therefore does not take advantage of the memory savings allowed by TranscodingStreams. The C library version claims to use no additional working memory, but it requires that a continuous space in memory be available to hold the entire output of the compressed data, the length of which is not knowable _a priori_ but can be larger than the compressed data by a factor of roughly 255. This implementation reports a very large memory requirement with `TranscodingStreams.minoutsize` to account for this.
"""
mutable struct LZO1X1FastDecompressorCodec <: TranscodingStreams.Codec
    input_buffer::Vector{UInt8}
    output_buffer::Vector{UInt8}
    
    LZO1X1FastDecompressorCodec() = new(UInt8[], UInt8[])
end

const LZOFastDecompressorCodec = LZO1X1FastDecompressorCodec
const LZOFastDecompressorStream{S} = TranscodingStream{LZO1X1FastDecompressorCodec,S} where S<:IO
LZOFastDecompressorStream(stream::IO, kwargs...) = TranscodingStream(LZOFastDecompressorCodec(), stream; kwargs...)

function TranscodingStreams.expectedsize(::LZO1X1FastDecompressorCodec, input::Memory)
    # Usually around 2.4:1 compression ratio (see https://morotti.github.io/lzbench-web)
    return max(length(input) * 3, length(input) - 4)
end

function TranscodingStreams.startproc(codec::LZO1X1FastDecompressorCodec, ::Symbol, ::Error)
    empty!(codec.input_buffer)
    empty!(codec.output_buffer)
    return :ok
end


"""
    unsafe_lzo_decompress!(dest::Vector{UInt8}, src)::Int

Decompress `src` to `dest` using the LZO 1X1 algorithm.

The method is "unsafe" in that it does not check to see if the decompressed output can fit into `dest` before proceeding, and may write out of bounds or crash your program if the number of bytes required to decompress `src` is larger than the number of bytes available in `dest`. The method returns the number of bytes written to `dest`, which may be greater than `length(dest)`.
"""
function unsafe_lzo_decompress!(dest::Vector{UInt8}, src::AbstractVector{UInt8})
    return GC.@preserve dest unsafe_lzo_decompress!(pointer(dest), src)
end

function unsafe_lzo_decompress!(dest::Ptr{UInt8}, src::AbstractVector{UInt8})
    working_memory = UInt8[] # no working memory needed to decompress
    size_ptr = Ref{Csize_t}()
    @ccall liblzo2.lzo1x_decompress(src::Ptr{Cuchar}, sizeof(src)::Csize_t, dest::Ptr{Cuchar}, size_ptr::Ptr{Csize_t}, working_memory::Ptr{Cvoid})::Cint # always returns LZO_E_OK or crashes!
    return size_ptr[]
end

unsafe_lzo_decompress!(dest, src::AbstractString) = unsafe_lzo_decompress!(dest, Base.CodeUnits(src))

"""
    lzo_decompress!(dest::Vector{UInt8}, src)

Decompress `src` to `dest` using the LZO 1X1 algorithm.

The destination vector `dest` will be resized to fit the decompressed data if necessary. Returns the modified `dest`.
"""
function lzo_decompress!(dest::Vector{UInt8}, src::AbstractVector{UInt8})
    old_size = length(dest)
    if old_size < length(src) # just a guess
        resize!(dest, length(src))
    end

    working_memory = UInt8[] # no working memory needed to decompress
    size_ptr = Ref{Csize_t}(length(dest))
    while true
        e = @ccall liblzo2.lzo1x_decompress_safe(src::Ptr{Cuchar}, length(src)::Csize_t, dest::Ptr{Cuchar}, size_ptr::Ptr{Csize_t}, working_memory::Ptr{Cvoid})::Cint
    
        if e == LZO_E_OUTPUT_OVERRUN
            resize!(dest, length(dest)*2)
            size_ptr[] = length(dest)
        elseif e == LZO_E_INPUT_NOT_CONSUMED
            throw(InputNotConsumedException())
        elseif e == LZO_E_EOF_NOT_FOUND
            throw(EndOfStreamNotFoundException())
        elseif e == LZO_E_INPUT_OVERRUN
            throw(InputOverrunException())
        elseif e != LZO_E_OK
            throw(LZOException(e, "liblzo2 decompression error: $e"))
        else
            break
        end
    end

    resize!(dest, max(size_ptr[], old_size))
    return dest
end

lzo_decompress!(dest::Vector{UInt8}, src::AbstractString) = lzo_decompress!(dest, Base.CodeUnits(src))

"""
    lzo_decompress(src)::Vector{UInt8}

Decompress `src` using the LZO 1X1 algorithm.

Returns a decompressed version of `src`.
"""
function lzo_decompress(src::AbstractVector{UInt8})
    dest = UInt8[]
    return lzo_decompress!(dest, src)
end

lzo_decompress(src::AbstractString) = lzo_decompress(Base.CodeUnits(src))


function lzo_decompress(a::Vector{UInt8}, b::Vector{UInt8})
    working_memory = UInt8[] # no working memory needed to decompress
    if isempty(b)
        resize!(b, 256)
    end
    size_ptr = Ref{Csize_t}(length(b))
    while true
        e = ccall((:lzo1x_decompress_safe, liblzo2), Cint, (Ptr{Cuchar}, Csize_t, Ptr{Cuchar}, Ptr{Csize_t}, Ptr{Cvoid}), a, sizeof(a), b, size_ptr, working_memory)
    
        if e == LZO_E_OUTPUT_OVERRUN
            resize!(b, length(b)*2)
            size_ptr[] = length(b)
        elseif e != LZO_E_OK
            throw(ErrorException("liblzo2 decompression error: $e"))
        else
            break
        end
    end
    resize!(b, size_ptr[])
    return size_ptr[]

end

function TranscodingStreams.process(codec::LZO1X1FastDecompressorCodec, input::Memory, output::Memory, error::Error)

    input_length = length(input)
    if input_length == 0
        if isempty(codec.output_buffer)
            try
                lzo_decompress(codec.input_buffer, codec.output_buffer)
            catch e
                error[] = e
                return 0, codec.n_written[], :error
            end
        end
        to_copy = min(length(codec.output_buffer), length(output))
        copyto!(output, 1, codec.output_buffer, 1, to_copy)
        splice!(codec.output_buffer, 1:to_copy)
        if isempty(codec.output_buffer)
            return 0, to_copy, :end
        else
            return 0, to_copy, :ok
        end
    end

    append!(codec.input_buffer, unsafe_wrap(Vector{UInt8}, input.ptr, input.size))
    return input.size % Int, 0, :ok
end

function TranscodingStreams.finalize(codec::LZO1X1FastDecompressorCodec)
    empty!(codec.input_buffer)
    empty!(codec.output_buffer)
    return
end