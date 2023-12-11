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
- A lookback dictionary implemented as a hash map with a maximum of size of `1<<16 = 65536` elements;
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

function compress_minoutsize(input_len::Integer)
    # The worst-case scenario is a super-long literal, in which case the input has to be emitted in its entirety 
    # plus the appropriate commands to start a long literal and end the stream.
    # CMD(1) + LITERAL_RUN + LITERAL_REMAINDER(1) + LITERAL + EOS(3)
    return input_len ÷ 255 + input_len + 5
end

TranscodingStreams.minoutsize(::LZO1X1FastCompressorCodec, input::Memory) = compress_minoutsize(length(input))

function TranscodingStreams.expectedsize(::LZO1X1FastCompressorCodec, input::Memory)
    # Usually around 2.4:1 compression ratio (see https://morotti.github.io/lzbench-web)
    return max(length(input) ÷ 2, length(input) + 4)
end

function TranscodingStreams.startproc(codec::LZO1X1FastCompressorCodec, ::Symbol, ::Error)
    empty!(codec.input_buffer)
    fill!(codec.input_buffer, zero(UInt8))
    return :ok
end

"""
    unsafe_lzo_compress!(dest::Vector{UInt8}, src, [working_memory=zeros(UInt8, 1<<12)])::Int

Compress `src` to `dest` using the LZO 1X1 algorithm.

The method is "unsafe" in that it does not check to see if the compressed output can fit into `dest` before proceeding, and may write out of bounds or crash your program if the number of bytes required to compress `src` is larger than the number of bytes available in `dest`. The method returns the number of bytes written to `dest`, which may be greater than `length(dest)`.

Pass `working_memory`, a `Vector{UInt8}` with `length(working_memory) >= 1<<12`, to reuse pre-allocated memory required by the algorithm.
"""
function unsafe_lzo_compress!(dest::Union{Vector{UInt8}, Ptr{UInt8}}, src::AbstractVector{UInt8}, working_memory::Vector{UInt8} = zeros(UInt8, 1 << 16))
    @boundscheck checkbounds(working_memory, 1<<16)
    fill!(working_memory, UInt8(0))
    size_ptr = Ref{Csize_t}()
    @ccall liblzo2.lzo1x_1_compress(src::Ptr{Cuchar}, sizeof(src)::Csize_t, dest::Ptr{Cuchar}, size_ptr::Ptr{Csize_t}, working_memory::Ptr{Cvoid})::Cint # always returns LZO_E_OK
    return size_ptr[]
end

unsafe_lzo_compress!(dest, src::AbstractString, working_memory::Vector{UInt8} = zeros(UInt8, 1 << 16)) = unsafe_lzo_compress!(dest, Base.CodeUnits(src), working_memory)

"""
    lzo_compress!(dest::Vector{UInt8}, src, [working_memory=zeros(UInt8, 1<<12)])

Compress `src` to `dest` using the LZO 1X1 algorithm.

The destination vector `dest` will be resized to fit the compressed data if necessary. Returns the modified `dest`.

Pass `working_memory`, a `Vector{UInt8}` with `length(working_memory) >= 1<<12`, to reuse pre-allocated memory required by the algorithm.
"""
function lzo_compress!(dest::Vector{UInt8}, src::AbstractVector{UInt8}, working_memory::Vector{UInt8} = zeros(UInt8, 1 << 16))
    old_size = length(dest)
    min_size = compress_minoutsize(length(src))
    if old_size < min_size
        resize!(dest, min_size)
    end

    new_size = unsafe_lzo_compress!(dest, src, working_memory)
    resize!(dest, max(new_size, old_size))
    return dest
end

lzo_compress!(dest::Vector{UInt8}, src::AbstractString, working_memory::Vector{UInt8} = zeros(UInt8, 1 << 16)) = lzo_compress!(dest, Base.CodeUnits(src), working_memory)

"""
    lzo_compress(src, [working_memory=zeros(UInt8, 1<<12)])::Vector{UInt8}

Compress `src` using the LZO 1X1 algorithm.

Returns a compressed version of `src`.

Pass `working_memory`, a `Vector{UInt8}` with `length(working_memory) >= 1<<12`, to reuse pre-allocated memory required by the algorithm.
"""
function lzo_compress(src::AbstractVector{UInt8}, working_memory::Vector{UInt8} = zeros(UInt8, 1 << 16))
    dest = UInt8[]
    return lzo_compress!(dest, src, working_memory)
end

lzo_compress(src::AbstractString, working_memory::Vector{UInt8} = zeros(UInt8, 1 << 16)) = lzo_compress(Base.CodeUnits(src), working_memory)

function TranscodingStreams.process(codec::LZO1X1FastCompressorCodec, input::Memory, output::Memory, ::Error)

    input_length = length(input)
    if input_length == 0
        n_written = unsafe_lzo_compress!(output.ptr, codec.input_buffer, codec.working_memory)
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