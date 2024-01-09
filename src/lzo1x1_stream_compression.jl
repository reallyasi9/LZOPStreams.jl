const LZO1X1_LAST_LITERAL_SIZE = 3  # the number of bytes in the last literal
const LZO1X1_LAST_LITERAL_MAX_SIZE = 20 # do not try to match in history if the remaining literal is this size or less
const LZO1X1_MIN_MATCH = sizeof(UInt32)  # the smallest number of bytes to consider in a dictionary lookup
const LZO1X1_MAX_INPUT_SIZE = 0x7e00_0000 % Int  # 2133929216 bytes, seemingly arbitrary?
const LZO1X1_LITERAL_LENGTH_BITS = 4  # The number of bits in a literal command before resorting to run encoding
const LZO1X1_LONG_COPY_LENGTH_BITS = 3  # The number of bits in a long-distance (16K to 48K) history copy command before resorting to run encoding
const LZO1X1_SHORT_COPY_LENGTH_BITS = 5  # The number of bits in a short-distance (under 16K) history copy command before resorting to run encoding

const LZO1X1_MAX_DISTANCE = (0b11000000_00000000 - 1) % Int  # 49151 bytes, if a match starts further back in the buffer than this, it is considered a miss

const LZO1X1_HASH_MAGIC_NUMBER = 0x1824429D
const LZO1X1_HASH_BITS = 13  # The number of bits that are left after shifting in the hash calculation

const LZO1X1_MIN_BUFFER_SIZE = LZO1X1_MAX_DISTANCE + LZO1X1_MIN_MATCH

@enum MatchingState begin
    FIRST_LITERAL # Waiting on end of first literal
    HISTORY # Waiting on end of historical match
    LITERAL # Waiting on end of long literal
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
    input_buffer::ModuloBuffer{UInt8} # 49151-byte history of uncompressed input data for history copy command lookups

    command_buffer::CircularBuffer{AbstractCommand} # The last command readied by the compression algorithm
    output_buffer::Vector{UInt8} # A buffer for literals that can be longer than the 49151-byte lookback limit

    bytes_read::Int # Number of bytes read from the raw input stream (so lookbacks have a common starting point)
    copy_start::Int # Where in the raw input stream a copy started
    copy_length::Int # How many bytes match in a history copy

    skip_trigger::Int # After 2^skip_trigger history misses, increase skip by 1
    skip::Int # How many bytes to skip when searching for the next history match

    LZO1X1CompressorCodec(level::Integer=5) = new(HashMap{UInt32,Int}(
        LZO1X1_HASH_BITS,
        LZO1X1_HASH_MAGIC_NUMBER),
        ModuloBuffer{UInt8}(LZO1X1_MIN_BUFFER_SIZE), # The circular array needs a small buffer to guarantee the next bytes read can be matched
        CircularBuffer{AbstractCommand}(1), # Only the last command (or nothing) is kept
        Vector{UInt8}(),
        0,
        0,
        0,
        level,
        1,
    )
end

const LZOCompressorCodec = LZO1X1CompressorCodec
const LZOCompressorStream{S} = TranscodingStream{LZO1X1CompressorCodec,S} where S<:IO
LZOCompressorStream(stream::IO, kwargs...) = TranscodingStream(LZOCompressorCodec(), stream; kwargs...)

function TranscodingStreams.initialize(codec::LZO1X1CompressorCodec)
    empty!(codec.input_buffer)
    empty!(codec.command_buffer)
    empty!(codec.output_buffer)
    return
end

"""
    state(codec)::MatchingState

Determine the state of the codec from the command in the buffer.

The state of the codec can be one of:
- `FIRST_LITERAL``: in the middle of recording the first literal copy command from the input (the initial state);
- `LITERAL`: in the middle of writing a literal copy command to the output; or
- `HISTORY`: in the middle of writing a history copy command to the output.
"""
function state(codec::LZO1X1CompressorCodec)
    if isempty(codec.command_buffer)
        return FIRST_LITERAL
    elseif first(codec.command_buffer) isa LiteralCopyCommand
        return LITERAL
    else
        return HISTORY
    end
end

function command(codec::LZO1X1CompressorCodec)
    isempty(codec.command_buffer) && return nothing
    return first(codec.command_buffer)
end

function TranscodingStreams.minoutsize(codec::LZO1X1CompressorCodec, input::Memory)
    # The worst-case scenario is a super-long literal, in which case the input has to be emitted in its entirety along with the output buffer
    # plus the appropriate commands to start a long literal or match and end the stream.
    # If in the middle of a history write, then the worst-case scenario is if the history copy command ends the copy and the rest of the input has to be written as a literal.
    if state(codec) == HISTORY
        # CMD + HISTORY_RUN + HISTORY_REMAINDER + DISTANCE + CMD + LITERAL_RUN + LITERAL_REMAINDER + LITERAL + EOS
        cmd = command(codec)::HistoryCopyCommand
        return command_length(cmd) + 1 + length(input) ÷ 255 + 1 + length(input) + 3
    else
        # CMD + LITERAL_RUN + LITERAL_REMAINDER + LITERAL + CMD + LITERAL_RUN + LITERAL_REMAINDER + LITERAL + EOS + buffer
        return 1 + length(codec.output_buffer) ÷ 255 + 1 + length(codec.output_buffer) + 1 + length(input) ÷ 255 + 1 + length(input) + 3
    end
end

function TranscodingStreams.expectedsize(codec::LZO1X1CompressorCodec, input::Memory)
    # Usually around 2.4:1 compression ratio with a minimum of 24 bytes (see https://morotti.github.io/lzbench-web)
    return max((length(codec.output_buffer) + length(input)) ÷ 2, 24)
end

function TranscodingStreams.startproc(codec::LZO1X1CompressorCodec, ::Symbol, ::Error)
    empty!(codec.dictionary)
    codec.bytes_read = 0
    codec.copy_start = 0
    codec.copy_length = 0
    codec.skip = 1
    return :ok
end

function TranscodingStreams.process(codec::LZO1X1CompressorCodec, input::Memory, output::Memory, ::Error)

    input_length = length(input)
    
    # An input length of zero signals EOF
    if input_length == 0
        # Everything remaining in the buffer has to be flushed as a literal because it didn't match
        w = emit_last_literal!(codec, output, 1)
        return 0, w, :end
    end

    # Everything else is loaded into the buffer and consumed
    n_read = 0
    n_written = 0
    while n_read < input_length - LZO1X1_MIN_MATCH
        # Looking for the end of a copy run
        if state(codec) == HISTORY
            # get the last 4-byte word for faster reading from the input
            word = reinterpret_get(UInt32, codec.input_buffer[codec.copy_start+codec.copy_length-1])
            while n_read < input_length - LZO1X1_MIN_MATCH
                if input[n_read+1] == codec.input_buffer[codec.copy_start+codec.copy_length]
                    n_read += 1
                    codec.bytes_read += 1
                    push!(codec.input_buffer, input[n_read])
                    word = reinterpret_next(word, codec.input_buffer, codec.copy_start+codec.copy_length)
                    codec.dictionary[word] = codec.bytes_read
                    codec.copy_length += 1
                else
                    command = HistoryCopyCommand(codec.bytes_read - codec.copy_start, codec.copy_length, 0)
                    push!(codec.command_buffer, command)
                    break
                end
            end
        end
        # Looking for the end of a literal run
        if state(codec) == LITERAL || state(codec) == FIRST_LITERAL
            # get the next 4-byte word for faster reading from the input
            word = reinterpret_get(UInt32, input, n_read+1)
            while n_read < input_length - LZO1X1_MIN_MATCH
                
            end
        end

        n_read += consume_input!(codec, input, n_read + 1)

        # The buffer is processed and potentially data is written to output
        n_written += compress_and_emit!(codec, output, n_written + 1)
    end

    # We are done
    return n_read, n_written, :ok

end

function TranscodingStreams.finalize(codec::LZO1X1CompressorCodec)
    empty!(codec.dictionary)
    empty!(codec.input_buffer)
    empty!(codec.command_buffer)
    empty!(codec.output_buffer)
    return
end


function find_next_match!(codec::LZO1X1CompressorCodec, input_idx::Int)

    while input_idx <= codec.write_head - LZO1X1_MIN_MATCH
        input_long = reinterpret_get(UInt32, codec.input_buffer, input_idx)
        match_idx = replace!(codec.dictionary, input_long, input_idx)
        if match_idx > 0 && input_idx - match_idx < LZO1X1_MAX_DISTANCE && input_long == reinterpret_get(UInt32, codec.input_buffer, match_idx)
            return match_idx, input_idx
        end
        # The window jumps proportional to the number of bytes read this round
        input_idx += ((input_idx - codec.read_head) >> LZO1X1_SKIP_TRIGGER) + 1
    end
    # the input_idx might have skipped beyond the write head, so clamp it
    input_idx = min(input_idx, codec.write_head - LZO1X1_MIN_MATCH + 1)
    return -1, input_idx
end


# Write a literal from `codec.output_buffer` to `output` starting at `start_index`.
# Returns the number of bytes written to output and a status flag.
function emit_literal!(codec::LZO1X1CompressorCodec, output::Memory, start_index::Int)
    n_written = encode_literal_length!(codec, output, start_index)
    len = length(codec.output_buffer)
    unsafe_copyto!(output, start_index + n_written, codec.output_buffer, 1, len)
    resize!(codec.output_buffer, 0)
    return n_written + len
end

# End of stream is a copy of bytes from a distance of zero in the history
function emit_last_literal!(codec::LZO1X1CompressorCodec, output::Memory, start_index::Int)
    # in the middle of a history lookup means I can write that now
    n_written = 0
    if codec.state == HISTORY
        n_matching = count_matching(
            @view(codec.input_buffer[codec.read_head:codec.write_head-1]),
            @view(codec.input_buffer[codec.match_start_index:codec.write_head-1]))
        distance = codec.read_head - codec.match_start_index
        command = HistoryCopyCommand(distance, n_matching, 0)
        n_written += emit_copy!(codec, output, start_index, distance, n_matching)
        codec.read_head += n_matching
        codec.state = LITERAL
    end
    # everything in the input buffer is unmatched, so move that to the output buffer
    @inbounds append!(codec.output_buffer, codec.input_buffer[codec.read_head:codec.write_head-1])

    n_written += emit_literal!(codec, output, start_index + n_written)

    # EOS is signaled by a long copy command (0b00010000) with a distance of exactly 16384 bytes (last two bytes == 0).
    # The length of the copy does not matter, but must be between 3 and 9 (encoded in the first 3 bits of the command)
    # so that the following bytes are not interpreted as a length encoding run.
    output[start_index+n_written] = 0b00010001
    output[start_index+n_written+1] = 0 % UInt8
    output[start_index+n_written+2] = 0 % UInt8

    return n_written + 3
end

function emit_copy!(codec::LZO1X1CompressorCodec, output::Memory, start_index::Int, distance::Int, N::Int)
    # All LZO1X1 matches are 4 bytes or more, so command codes 0-15 and 64-95 are never used, but we add the logic for completeness

    if codec.previous_literal_length < 4 && N == 2 && distance <= 1024
        # 0b0000DDSS_HHHHHHHH, distance = (H << 2) + D + 1
        distance -= 1
        D = UInt8(distance & 0b00000011)
        H = UInt8((distance - D) >> 2)
        push!(codec.output_buffer, D << 2)
        push!(codec.output_buffer, H)
        codec.previous_copy_command_was_short = true
        return 0
    elseif codec.previous_literal_length >= 4 && N == 3 && 2049 <= distance <= 3072
        # 0b0000DDSS_HHHHHHHH, distance = (H << 2) + D + 2049
        distance -= 2049
        D = UInt8(distance & 0b00000011)
        H = UInt8((distance - D) >> 2)
        push!(codec.output_buffer, D << 2)
        push!(codec.output_buffer, H)
        codec.previous_copy_command_was_short = true
        return 0
    elseif 3 <= N <= 4 && distance < 2049
        # 0b01LDDDSS_HHHHHHHH, distance = (H << 3) + D + 1
        distance -= 1
        D = UInt8(distance & 0b00000111)
        H = UInt8((distance - D) >> 3)
        L = UInt8(N - 3)
        output[start_index] = 0b01000000 | (L << 5) | (D << 2)
        push!(codec.output_buffer, H)
        codec.previous_copy_command_was_short = true
        return 1
    elseif 5 <= N <= 8 && distance <= 2049
        # 0b1LLDDDSS_HHHHHHHH, distance = (H << 3) + D + 1
        distance -= 1
        D = UInt8(distance & 0b00000111)
        H = UInt8((distance - D) >> 3)
        L = UInt8(N - 5)
        output[start_index] = 0b10000000 | (L << 5) | (D << 2)
        push!(codec.output_buffer, H)
        codec.previous_copy_command_was_short = true
        return 1
    else
        if distance < 16384
            # 0b001LLLLL_*_DDDDDDSS_DDDDDDDD, distance = D + 1, length = 2 + (L ?: *)
            # Note that D is encoded LE in the last 16 bits!
            output[start_index] = zero(UInt8)
            run = encode_run!(output, start_index, N-2, 5)
            output[start_index] |= 0b00100000
            distance -= 1
        else
            # 0b0001HLLL_*_DDDDDDSS_DDDDDDDD, distance = 16384 + (H << 14) + D, length = 2 + (L ?: *)
            # Note that D is encoded LE in the last 16 bits!
            output[start_index] = zero(UInt8)
            run = encode_run!(output, start_index, N-2, 3)
            output[start_index] |= 0b00010000
            distance -= 16384
            H = UInt8((distance >> 14) & 1)
            output[start_index] |= H << 3
        end
        DH = UInt8((distance >> 6) & 0b11111111)
        DL = UInt8(distance & 0b00111111)
        push!(codec.output_buffer, DL << 2) # This is popped off the top with popfirst! when encoding the next literal length
        push!(codec.output_buffer, DH)
        codec.previous_copy_command_was_short = false
        return run
    end
end

function consume_input!(codec::LZO1X1CompressorCodec, input::Memory, input_start::Int)
    len = (length(input) - input_start + 1) # length(input) is UInt
    to_copy = min(len, LZO1X1_MAX_DISTANCE)
    # Memory objects do not allow range indexing, and circular vectors do not allow copyto!
    for i in 0:to_copy-1
        @inbounds codec.input_buffer[codec.write_head + i] = input[input_start + i]
    end
    codec.write_head += to_copy
    return to_copy
end


function compress_and_emit!(codec::LZO1X1CompressorCodec, input::Memory, input_start::Int, output::Memory, output_start::Int)
    input_length = length(input) - input_start + 1
    input_idx = codec.read_head
    n_written = 0

    while input_idx <= codec.write_head - LZO1X1_LAST_LITERAL_MAX_SIZE
        # If nothing has been written yet, load everything into the output buffer until the match is found
        if codec.state == FIRST_LITERAL || codec.state == LITERAL
            next_match_idx, input_idx = find_next_match!(codec, input_idx)

            # Put everything from the read head to just before the input index into the output buffer
            @inbounds append!(codec.output_buffer, codec.input_buffer[codec.read_head:input_idx-1])
            codec.read_head = input_idx
            if input_idx > codec.write_head - LZO1X1_MIN_MATCH
                # If out of input, wait for more
                return n_written
            end
            # Match found, meaning we have the entire literal
            n_written += emit_literal!(codec, output, output_start + n_written)
            codec.match_start_index = next_match_idx

            # At this point, we have the next match in match_start_index
            codec.state = HISTORY
        end

        # If we have a history lookup, find the length of the match
        n_matching = count_matching(
            @view(codec.input_buffer[input_idx:codec.write_head-LZO1X1_MIN_MATCH]),
            @view(codec.input_buffer[codec.match_start_index:codec.write_head-LZO1X1_MIN_MATCH]))
        
        # put all of the matching data into the dictionary
        matched_long = reinterpret_get(UInt32, codec.input_buffer, codec.match_start_index)
        for idx in (codec.match_start_index + 1):input_idx
            matched_long = reinterpret_next(matched_long, codec.input_buffer, idx)
            setindex!(codec.dictionary, idx, matched_long)
        end

        distance = input_idx - codec.match_start_index
        input_idx += n_matching
        if input_idx >= codec.write_head-LZO1X1_MIN_MATCH
            # If out of input, wait for more
            return n_written
        end

        # This is a history copy, so emit the command, but keep the last byte of the command in the output buffer, potentially for the next literal to be emitted.
        n_written += emit_copy!(codec, output, output_start + n_written, distance, n_matching)
        codec.read_head = input_idx
        codec.state = LITERAL
    end

    return n_written

end

