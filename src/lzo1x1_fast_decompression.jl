"""
    LZO1X1FastDecompressorCodec(level::Int=5) <: TranscodingStreams.Codec

A struct that compresses data according to the 1X1 version of the LZO algorithm.

The LZO 1X1 algorithm is a Lempel-Ziv lossless compression algorithm defined by:
- A lookback dictionary implemented as a hash map with a maximum of size of `1<<12 = 4096` elements;
- A 4-byte history lookup window that scans the input with a skip distance that increases linearly with the number of misses;
- A maximum lookback distance of `0b11000000_00000000 - 1 = 49151` bytes;

The C implementation of LZO defined by liblzo2 requires that all compressable information be loaded in working memory at once, and is therefore not adaptable to streaming as required by TranscodingStreams. The C library version claims to use only a 4096-byte hash map as additional working memory, but it also requires that a continuous space in memory be available to hold the entire output of the compressed data, the length of which is not knowable _a priori_ but can be larger than the uncompressed data by a factor of roughly 256/255. This implementation needs to keep 98310 bytes of input history in memory in addition to the 4096-byte hash map, and also caches literal copies in an array that expands as necessary during compression.
"""
struct LZO1X1FastDecompressorCodec <: TranscodingStreams.Codec
    algo::LZO1X_1
    input_buffer::Vector{UInt8}
    output_buffer::Vector{UInt8}
    LZO1X1FastDecompressorCodec() = new(LZO1X_1(;working_memory=Vector{UInt8}()), Vector{UInt8}(), Vector{UInt8}())
end

const LZOFastDecompressor = LZO1X1FastDecompressorCodec
const LZOFastDecompressorStream{S} = TranscodingStream{LZO1X1FastDecompressorCodec,S} where {S<:IO}
LZOFastDecompressorStream(stream::IO, kwargs...) = TranscodingStream(LZOFastDecompressor(), stream; kwargs...)

function TranscodingStreams.expectedsize(::LZO1X1FastDecompressorCodec, input::Memory)
    return length(input) * 2
end

function TranscodingStreams.process(codec::LZO1X1FastDecompressorCodec, input::Memory, output::Memory, error::Error)

    r = 0
    w = 0

    # Try to push the output buffer to the output memory
    if !isempty(codec.output_buffer)
        w = min(length(codec.output_buffer), length(output)) % Int
        unsafe_copyto!(output.ptr, pointer(codec.output_buffer), w)
        circshift!(codec.output_buffer, -w)
        resize!(codec.output_buffer, length(codec.output_buffer)-w)
    end

    # If end of input, done!
    if length(input) == 0
        if !isempty(codec.input_buffer)
            error[] = ErrorException("unconsumed compressed data in input buffer")
            return r, w, :error
        end
        if !isempty(codec.output_buffer)
            # wait for the output to clear
            return r, w, :ok
        end
        return r, w, :end
    end

    # Copy input to the buffer
    append!(codec.input_buffer, unsafe_wrap(Vector{UInt8}, input.ptr, length(input)))
    r += length(input) % Int

    # Try to find the end of the block in the input buffer
    i = 1
    found = findnext(END_OF_STREAM_DATA, codec.input_buffer, i)
    while !isnothing(found)
        try
            d = decompress(codec.algo, @view(codec.input_buffer[i:last(found)]))
            # success if no throw
            append!(codec.output_buffer, d)
            i = last(found) + 1
        catch
            # do nothing
        finally
            found = findnext(END_OF_STREAM_DATA, codec.input_buffer, last(found)+1)
        end
    end
    circshift!(codec.input_buffer, -(i-1))
    resize!(codec.input_buffer, length(codec.input_buffer)-(i-1))

    return r, w, :ok
end
