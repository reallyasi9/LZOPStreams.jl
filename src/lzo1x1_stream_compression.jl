const LZO1X1_LAST_LITERAL_MAX_SIZE = 20 # do not try to match in history if the remaining literal is this size or less
const LZO1X1_MIN_MATCH = sizeof(UInt32)  # the smallest number of bytes to consider in a dictionary lookup

const LZO1X1_MAX_DISTANCE = (0b11000000_00000000 - 1) % Int  # 49151 bytes, if a match starts further back in the buffer than this, it is considered a miss

const LZO1X1_HASH_MAGIC_NUMBER = 0x1824429D
const LZO1X1_HASH_BITS = 13  # The number of bits that are left after shifting in the hash calculation

const LZO1X1_MIN_BUFFER_SIZE = LZO1X1_MAX_DISTANCE + LZO1X1_MIN_MATCH

@enum MatchingState begin
    HISTORY # Waiting on end of historical match
    LITERAL # Waiting on end of long literal
    COMMAND # Waiting to flush command to output
    FLUSH # Waiting to flush output buffer to output
end 

"""
    LZO1X1CompressorCodec(level::Int=5) <: TranscodingStreams.Codec

A struct that compresses data according to the 1X1 version of the LZO algorithm.

The LZO 1X1 algorithm is a Lempel-Ziv lossless compression algorithm defined by:
- A lookback dictionary implemented as a hash map with a maximum of size of `1<<12 = 4096` elements;
- A 4-byte history lookup window that scans the input with a skip distance that increases linearly with the number of misses;
- A maximum lookback distance of `0b11000000_00000000 - 1 = 49151` bytes;

The C implementation of LZO defined by liblzo2 requires that all compressable information be loaded in working memory at once, and is therefore not adaptable to streaming as required by TranscodingStreams. The C library version claims to use only a 4096-byte hash map as additional working memory, but it also requires that a continuous space in memory be available to hold the entire output of the compressed data, the length of which is not knowable _a priori_ but can be larger than the uncompressed data by a factor of roughly 256/255. This implementation needs to keep 49151 bytes of input history in memory in addition to the 4096-byte hash map, but only expands the output as necessary during compression.

Arguments:
 - `level::Int = 5`: The speed/compression tradeoff paramter, with larger numbers representing slower compression at a higher compresison ratio. On a technical level, every `pow(2, level)` history misses increases by 1 the number of bytes skipped when searching for the next history match. The default (5) is recommended by the original liblzo2 authors as a good balance between speed and compression.
"""
mutable struct LZO1X1CompressorCodec <: TranscodingStreams.Codec
    dictionary::HashMap{UInt32,Int} # 4096-element lookback history that maps 4-byte values to lookback distances
    input_buffer::CircularVector{UInt8} # 49151-byte history of uncompressed input data for history copy command lookups
    literal_buffer::Vector{UInt8} # required dynamic buffer for literals longer than the lookback length (expands and contracts as needed)

    bytes_read::Int # Number of bytes read from the raw input stream (so lookbacks have a common starting point)
    copy_start::Int # Where in the history of the raw input stream a match was found and a copy begins (match_start - copy_start = lookback)
    match_start::Int # Where in the raw input stream the first match of a historcal sequence was discovered (match_end - match_start + 1 = copy_length)
    match_end::Int # Where in the raw input stream the run of matching bytes from a historical sequence ended (bytes_read - match_end = literal_length)
    next_copy_start::Int # The location in history where the next match starts
    next_match_start::Int # The location in the raw input stream where the next match starts

    skip_trigger::Int # After 2^skip_trigger dictionary lookup misses, increase skip by 1
    first_literal::Bool
    state::MatchingState

    LZO1X1CompressorCodec(level::Integer=5) = new(HashMap{UInt32,Int}(
        LZO1X1_HASH_BITS,
        LZO1X1_HASH_MAGIC_NUMBER),
        CircularVector(zeros(UInt8, LZO1X1_MIN_BUFFER_SIZE * 2)),
        Vector{UInt8}(),
        0,
        0,
        0,
        0,
        0,
        0,
        level,
        true,
        LITERAL,
    )
end

"""
    state(codec)::MatchingState

Return the state of the compressor.

The state can be one of:
    - `HISTORY`: The codec is looking for the end of the historical match (i.e., the byte before the next literal).
    - `LITERAL`: The codec is looking for the next historical match (i.e., the length of the current literal).
    - `COMMAND`: The codec is writing a command sequence.
    - `FLUSH`: The codec is flushing the literal buffer to output.
"""
state(codec::LZO1X1CompressorCodec) = codec.state

const LZOCompressorCodec = LZO1X1CompressorCodec
const LZOCompressorStream{S} = TranscodingStream{LZO1X1CompressorCodec,S} where S<:IO
LZOCompressorStream(stream::IO, kwargs...) = TranscodingStream(LZOCompressorCodec(), stream; kwargs...)

# function TranscodingStreams.minoutsize(codec::LZO1X1CompressorCodec, input::Memory)
#     # The worst-case scenario is a super-long literal, where the input has to be emitted in
#     # its entirety along with the output buffer plus the appropriate commands to start a
#     # long literal or match and end the stream.
#     # If in the middle of a history write, then the worst-case scenario is if the history
#     # copy command ends the copy and the rest of the input has to be written as a literal.
#     cl = codec.copy_length ÷ 255 + 4
#     # COPY_COMMAND + LITERAL_CMD + LITERAL_RUN + LITERAL_REMAINDER + LITERAL + EOS
#     return cl + 1 + length(input) ÷ 255 + 1 + length(input) + 3
# end

function TranscodingStreams.expectedsize(codec::LZO1X1CompressorCodec, input::Memory)
    # Usually around 2.4:1 compression ratio with a minimum of 24 bytes (see https://morotti.github.io/lzbench-web)
    return max(length(input) ÷ 2, 24)
end

function find_last_matching(buffer::CircularVector{UInt8}, history_start::Int, input_start::Int, max_length::Int)
    for i in 1:max_length
        buffer[history_start+i-1] != buffer[input_start+i-1] && return i-1, true
    end
    return max_length, false
end

function find_next_matching!(dict::HashMap{UInt32,Int}, buffer::CircularVector{UInt8}, input_start::Int, max_length::Int, first_nonmatching_index::Int, skip_trigger::Int)
    i = input_start
    while i <= input_start + max_length
        lookup = reinterpret_get(UInt32, buffer, i)
        idx = replace!(dict, lookup, i)
        if idx > 0 && input_start - idx <= LZO1X1_MAX_DISTANCE && reinterpret_get(UInt32, buffer, idx) == lookup
            return i - input_start, idx
        else
            skip = ((i - first_nonmatching_index + 1) >> skip_trigger) + 1
            i += skip
        end
    end
    return max_length, 0
end

function build_command(codec::LZO1X1CompressorCodec)
    return CommandPair(codec.first_literal, false, codec.match_start - codec.copy_start, codec.match_end - codec.match_start + (codec.first_literal ? 0 : 1), codec.next_match_start - codec.match_end - 1)
end

function flush!(output, buffer::Vector{UInt8}, output_start::Int)
    to_flush = min(length(buffer), length(output) - output_start) % Int
    for i in 1:to_flush
        output[output_start + i - 1] = buffer[i]
    end
    if to_flush == length(buffer)
        empty!(buffer)
    else
        circshift!(buffer, -to_flush)
        resize!(buffer, length(buffer) - to_flush)
    end
    return to_flush
end

function TranscodingStreams.process(codec::LZO1X1CompressorCodec, input::Memory, output::Memory, ::Error)

    input_length = length(input) % Int
    
    # An input length of zero signals EOF
    if input_length == 0
        # Everything remaining in the buffer has to be flushed as a literal because it didn't match
        w, done = emit_last_literal!(codec, output, 1)
        if done
            return 0, w, :end
        else
            return 0, w, :ok
        end
    end

    # Only copy up to the minimum buffer size
    to_process = min(input_length, LZO1X1_MIN_BUFFER_SIZE)
    for i in 1:to_process
        codec.input_buffer[codec.bytes_read+i] = input[i]
    end

    # Consume everything in the buffer
    n_written = 0
    last_index = codec.bytes_read + to_process - LZO1X1_MIN_MATCH
    while codec.bytes_read <= last_index
        # All commands are history+literal pairs except the first (literal only) and the last (history only).
        # The last command is already taken care of above.
        # If this is the first literal, the history part is skipped.
        if state(codec) == HISTORY
            copy_length = codec.bytes_read - codec.match_start + 1
            bytes_remaining = to_process - LZO1X1_MIN_MATCH - codec.bytes_read
            n_bytes_matching, end_found = find_last_matching(codec.input_buffer, codec.copy_start+copy_length, codec.bytes_read+1, bytes_remaining)

            codec.bytes_read += n_bytes_matching
            if end_found
                codec.match_end = codec.bytes_read
                codec.state = LITERAL
            end
        end

        if state(codec) == LITERAL
            bytes_remaining = to_process - LZO1X1_MIN_MATCH - codec.bytes_read
            search_start = codec.bytes_read+1
            n_bytes_nonmatching, copy_start = find_next_matching!(codec.dictionary, codec.input_buffer, search_start, bytes_remaining, codec.match_end+1, codec.skip_trigger)

            codec.bytes_read += n_bytes_nonmatching + 1
            codec.next_copy_start = copy_start
            codec.next_match_start = codec.bytes_read
            append!(codec.literal_buffer, codec.input_buffer[search_start:codec.bytes_read-1])
            if copy_start > 0
                codec.state = COMMAND
            end
        end

        if state(codec) == COMMAND
            command = build_command(codec)
            w = encode!(output, command, n_written + 1)
            if w > 0
                n_written += w
                codec.match_start = codec.next_match_start
                codec.copy_start = codec.next_copy_start
                codec.match_end = 0
                codec.next_match_start = 0
                codec.next_copy_start = 0
                codec.first_literal = false
                codec.state = FLUSH
            else
                # quit immediately because we ran out of output space
                return to_process, n_written, :ok
            end
        end

        if state(codec) == FLUSH
            n_written += flush!(output, codec.literal_buffer, n_written+1)
            if !isempty(codec.literal_buffer)
                # quit immediately because we ran out of output space
                return to_process, n_written, :ok
            end
            codec.state = HISTORY
        end
    end

    # We are done with this load
    return to_process, n_written, :ok

end

function TranscodingStreams.finalize(codec::LZO1X1CompressorCodec)
    empty!(codec.dictionary)
    fill!(codec.input_buffer, zero(UInt8))
    empty!(codec.literal_buffer)
    return
end

function emit_last_literal!(codec::LZO1X1CompressorCodec, output::Memory, start_index::Int)
    
    w = 0
    
    # in the middle of a history lookup means I can write that now
    if state(codec) == HISTORY
        match_end = codec.bytes_read-1
        command = CommandPair(false, false, codec.match_start - codec.copy_start, match_end - codec.match_start + 1, 0)
        w += encode!(output, command, start_index)
    elseif state(codec) == LITERAL
        # in the middle of a literal search means I can write that now, too
        command = CommandPair(codec.first_literal, false, codec.match_start - codec.copy_start, codec.match_end - codec.match_start + 1, codec.bytes_read - codec.match_end)
        w += encode!(output, command, start_index)
    elseif state(codec) == COMMAND
        # in the middle of a command means I can write that
        command = build_command(codec)
        w += encode!(output, command, start_index)
        if w == 0
            return 0, false
        else
            codec.match_start = codec.next_match_start
            codec.copy_start = codec.next_copy_start
            codec.match_end = 0
            codec.next_match_start = 0
            codec.next_copy_start = 0
            codec.first_literal = false
        end
    end

    if state(codec) == FLUSH
        w += flush!(output, codec.literal_buffer, w+start_index)
        if !isempty(codec.literal_buffer)
            return w, false
        end
    end

    eos_w = encode!(output, END_OF_STREAM_COMMAND, w+start_index)
    if eos_w == 0
        return w, false
    end
    return w+eos_w, true
end

