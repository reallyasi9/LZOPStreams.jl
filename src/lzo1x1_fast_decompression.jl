
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

function TranscodingStreams.initialize(::LZO1X1FastDecompressorCodec)
    # The LZO library initialization method takes parameters that check that the following values are consistent between the compiled library and the code calling it:
    # 1. the version of the library (must be != 0)
    # 2. sizeof(short)
    # 3. sizeof(int)
    # 4. sizeof(long)
    # 5. sizeof(lzo_uint32_t) (required to be 4 bytes, irrespective of machine architecture)
    # 6. sizeof(lzo_uint) (required to be 8 bytes, irrespective of machine architecture)
    # 7. lzo_sizeof_dict_t (size of a pointer)
    # 8. sizeof(char *)
    # 9. sizeof(lzo_voidp) (size of void *)
    # 10. sizeof(lzo_callback_t) (size of a complex callback struct)
    # If any of these arguments except the first is -1, the check is skipped.
    e = ccall((:__lzo_init_v2, liblzo2), Cint, (Cuint, Cint, Cint, Cint, Cint, Cint, Cint, Cint, Cint, Cint), 1, sizeof(Cshort), sizeof(Cint), sizeof(Clong), sizeof(Culong), sizeof(Culonglong), sizeof(Ptr{Cchar}), sizeof(Ptr{Cchar}), sizeof(Ptr{Cvoid}), -1)
    if e != LZO_E_OK
        throw(ErrorException("initialization of liblzo2 failed: $e"))
    end
    return
end

function TranscodingStreams.expectedsize(::LZO1X1FastDecompressorCodec, input::Memory)
    # Usually around 2.4:1 compression ratio with a minimum around 20 bytes (see https://morotti.github.io/lzbench-web)
    return min(length(input) * 3, 20)
end

function TranscodingStreams.startproc(codec::LZO1X1FastDecompressorCodec, ::Symbol, ::Error)
    empty!(codec.input_buffer)
    empty!(codec.output_buffer)
    return :ok
end

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