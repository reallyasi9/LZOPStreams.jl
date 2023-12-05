const LZO_E_OK = 0
const LZO_E_ERROR = -1
const LZO_E_INPUT_OVERRUN = -4
const LZO_E_OUTPUT_OVERRUN = -5
const LZO_E_EOF_NOT_FOUND = -7
const LZO_E_INPUT_NOT_CONSUMED = -8

"""
    LZO1X1FastCompressorCodec <: TranscodingStreams.Codec

A struct that compresses data using the liblzo2 version version of the LZO 1X1 algorithm.

The LZO 1X1 algorithm is a Lempel-Ziv lossless compression algorithm defined by:
- A lookback dictionary implemented as a hash map with a maximum of size of `1<<12 = 4096` elements;
- A 4-byte history lookup window that scans the input with a skip distance that increases linearly with the number of misses;
- A maximum lookback distance of `0b11000000_00000000 - 1 = 49151` bytes;

The C implementation of LZO defined by liblzo2 requires that all compressable information be loaded in working memory at once. The C library version claims to use only a 4096-byte hash map as additional working memory, but it also requires that a continuous space in memory be available to hold the entire output of the compressed data, the length of which is not knowable _a priori_ but can be larger than the uncompressed data by a factor of roughly 256/255. This implementation uses an expanding input buffer that waits until all input is available before processing, eliminating the usefulness of the TranscodingStreams interface.
"""
mutable struct LZO1X1FastCompressorCodec <: TranscodingStreams.Codec
    input_buffer::Vector{UInt8}
    working_memory::Vector{UInt8}

    LZO1X1FastCompressorCodec() = new(UInt8[], zeros(UInt8, 1 << 16))
end

const LZOFastCompressorCodec = LZO1X1FastCompressorCodec
const LZOFastCompressorStream{S} = TranscodingStream{LZO1X1FastCompressorCodec,S} where {S<:IO}
LZOFastCompressorStream(stream::IO, kwargs...) = TranscodingStream(LZOFastCompressorCodec(), stream; kwargs...)

function TranscodingStreams.initialize(::LZO1X1FastCompressorCodec)
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

function TranscodingStreams.minoutsize(::LZO1X1FastCompressorCodec, input::Memory)
    # The worst-case scenario is a super-long literal, in which case the input has to be emitted in its entirety 
    # plus the appropriate commands to start a long literal or match and end the stream.
    # CMD + LITERAL_RUN + LITERAL_REMAINDER + LITERAL + EOS + buffer
    return 1 + length(input) ÷ 255 + 1 + length(input) + 3
end

function TranscodingStreams.expectedsize(::LZO1X1FastCompressorCodec, input::Memory)
    # Usually around 2.4:1 compression ratio with a minimum of 24 bytes (see https://morotti.github.io/lzbench-web)
    return max(length(input) ÷ 2, 24)
end

function TranscodingStreams.startproc(codec::LZO1X1FastCompressorCodec, ::Symbol, ::Error)
    empty!(codec.input_buffer)
    fill!(codec.input_buffer, zero(UInt8))
    return :ok
end

function lzo_compress(a::Vector{UInt8}, working_memory::Vector{UInt8}, output::Memory)
    size_ptr = Ref{Csize_t}()
    @ccall liblzo2.lzo1x_1_compress(a::Ptr{Cuchar}, sizeof(a)::Csize_t, output.ptr::Ptr{Cuchar}, size_ptr::Ptr{Csize_t}, working_memory::Ptr{Cvoid})::Cint
    return size_ptr[]
end

function TranscodingStreams.process(codec::LZO1X1FastCompressorCodec, input::Memory, output::Memory, ::Error)

    input_length = length(input)
    if input_length == 0
        n_written = lzo_compress(codec.input_buffer, codec.working_memory, output)
        return 0, n_written % Int, :end
    end

    append!(codec.input_buffer, unsafe_wrap(Vector{UInt8}, input.ptr, input.size))
    return input.size % Int, 0, :ok
end

function TranscodingStreams.finalize(codec::LZO1X1FastCompressorCodec)
    empty!(codec.input_buffer)
    fill!(codec.working_memory, zero(UInt8))
    return
end