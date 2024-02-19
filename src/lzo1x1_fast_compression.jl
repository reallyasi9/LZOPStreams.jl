"""
    LZO1X1FastCompressorCodec(level::Int=5) <: TranscodingStreams.Codec

A struct that compresses data according to the 1X1 version of the LZO algorithm.

The LZO 1X1 algorithm is a Lempel-Ziv lossless compression algorithm defined by:
- A lookback dictionary implemented as a hash map with a maximum of size of `1<<12 = 4096` elements;
- A 4-byte history lookup window that scans the input with a skip distance that increases linearly with the number of misses;
- A maximum lookback distance of `0b11000000_00000000 - 1 = 49151` bytes;

The C implementation of LZO defined by liblzo2 requires that all compressable information be loaded in working memory at once, and is therefore not adaptable to streaming as required by TranscodingStreams. The C library version claims to use only a 4096-byte hash map as additional working memory, but it also requires that a continuous space in memory be available to hold the entire output of the compressed data, the length of which is not knowable _a priori_ but can be larger than the uncompressed data by a factor of roughly 256/255. This implementation needs to keep 98310 bytes of input history in memory in addition to the 4096-byte hash map, and also caches literal copies in an array that expands as necessary during compression.
"""
struct LZO1X1FastCompressorCodec <: TranscodingStreams.Codec
    buffer::Vector{UInt8}

    LZO1X1FastCompressorCodec() = new(Vector{UInt8}())
end


const LZOFastCompressor = LZO1X1FastCompressorCodec
const LZOFastCompressorStream{S} = TranscodingStream{LZO1X1FastCompressorCodec,S} where {S<:IO}
LZOFastCompressorStream(stream::IO, kwargs...) = TranscodingStream(LZOFastCompressor(), stream; kwargs...)

function TranscodingStreams.expectedsize(::LZO1X1FastCompressorCodec, input::Memory)
    return length(input) ÷ 2
end

function TranscodingStreams.minoutsize(::LZO1X1FastCompressorCodec, input::Memory)
    return 5
end

function TranscodingStreams.initialize(::LZO1X1FastCompressorCodec)
end

function TranscodingStreams.finalize(::LZO1X1FastCompressorCodec)
end

function TranscodingStreams.stratproc(::LZO1X1FastCompressorCodec, ::Symbol, ::Error)
    return :ok
end

function TranscodingStreams.process(codec::LZO1X1FastCompressorCodec, input::Memory, output::Memory, error::Error)
    # If end of input, write out the encoded data
    if length(input) == 0
        # wait for a large enough output memory
        if length(output) < LibLZO.max_compressed_length(LZO1X_1, length(codec.buffer))
            return 0, 0, :ok
        end
        bytes_written = 0
        try
            bytes_written = unsafe_compress!(LZO1X_1, output.ptr, length(output), pointer(codec.buffer), length(codec.buffer))
        catch e
            error[] = e
            return 0, 0, :error
        end
        return 0, bytes_written, :end
    end

    # load up the buffer and wait for EOS
    append!(codec.buffer, input)

    return length(input), 0, :ok
end
