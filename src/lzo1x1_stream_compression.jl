const LZO1X1_LITERAL_BUFFER_SIZE = 20 # do not try to match in history if the remaining literal is this size or less
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

    write_head::Int # Where the next byte of data will go in input_buffer
    bytes_read::Int # Number of bytes read from the start of the input_buffer (so lookbacks have a common starting point)

    copy_start::Int # Where in the history of the raw input stream a match was found and a copy begins (match_start - copy_start = lookback)
    match_start::Int # Where in the raw input stream the first match of a historcal sequence was discovered (match_end - match_start + 1 = copy_length)
    match_end::Int # Where in the raw input stream the run of matching bytes from a historical sequence ended (bytes_read - match_end = literal_length)
    next_copy_start::Int # The location in history where the next match starts

    skip_trigger::Int # After 2^skip_trigger dictionary lookup misses, increase skip by 1
    first_literal::Bool # The first literal written has a special command structure
    last_literals_copied::Int # The number of literal bytes copied in the last command written to the output
    state::MatchingState

    LZO1X1CompressorCodec(level::Integer=5) = new(HashMap{UInt32,Int}(
            LZO1X1_HASH_BITS,
            LZO1X1_HASH_MAGIC_NUMBER),
        CircularVector(zeros(UInt8, LZO1X1_MIN_BUFFER_SIZE * 2)),
        Vector{UInt8}(),
        1,
        0,
        0,
        0,
        0,
        0,
        level,
        true,
        0,
        LITERAL,
    )
end

const LZOCompressorCodec = LZO1X1CompressorCodec
const LZOCompressorStream{S} = TranscodingStream{LZO1X1CompressorCodec,S} where {S<:IO}
LZOCompressorStream(stream::IO, kwargs...) = TranscodingStream(LZOCompressorCodec(), stream; kwargs...)

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

"""
    match_length(v, i::Integer, j::Integer, N::Integer)::Int

Searches `v[i:i+N-1]` for the last element that matches in `v[j:j+N-1]`, returning the maximal length of the matching elements up to and including `N`.

The argument `v` need only implement `getindex(v, ::Integer)`. If the search runs out of bounds, a `BoundsError` will be thrown. If no matches are found, `0` will be returned, and if no non-match is found, `N` will be returned.
"""
function match_length(v, i::Integer, j::Integer, N::Integer)
    offset = zero(Int)
    while offset < N
        v[i+offset] != v[j+offset] && return offset
        offset += 1
    end
    return Int(N)
end


"""
    find_next_match!(dict::HashMap, v, i::Integer, N::Integer, [skip_trigger::Integer=typemax(Int), skip_start_index::Integer=i])::Tuple{Int,Int}

Searches `v[i:i+N-1]` for the first `keytype(dict)` element that matches in its own history as recorded in `dict`, returning the first matching index `idx` and the historical location `j` such that `v[idx]` matches `v[j]`, `j<idx`, and `v[idx-skip]` does not match anything (see description of `skip` below).

The argument `v` need only implement `getindex(v, ::Integer)`. If the search runs out of bounds, a `BoundsError` will be thrown. If no matches are found, `(0,0)` will be returned.

The method updates `dict` in place with new information about locations of elements from `v`.

Indices `idx` of `v` are examined one at a time until `skip_start_index + idx` is equal to a multiple of `pow(2, skip_trigger)`, after which every other index is examined (then every third, fourth, etc.).
"""

function find_next_match!(dict::HashMap{K,Int}, v, i::Integer, N::Integer, skip_trigger::Integer=typemax(Int), skip_start_index::Integer=i) where {K}
    offset = zero(Int)
    while offset < N
        idx = Int(i + offset)
        value = reinterpret_get(K, v, idx)
        history = replace!(dict, value, idx)
        if history > 0 && idx - history <= LZO1X1_MAX_DISTANCE && reinterpret_get(K, v, history) == value
            return idx, history
        else
            offset += ((idx - skip_start_index + 1) >> skip_trigger) + 1
        end
    end
    return zero(Int), zero(Int)
end

function build_command(codec::LZO1X1CompressorCodec)
    # Invariants:
    #                  ↓codec.copy_start        ↓codec.match_start        ↓codec.bytes_read
    # input_buffer: ←--**** ... ***--&-- ... ---**** ... ****#### ... ####&-- ... -??? ... →
    #                                ↑codec.next_copy_start ↑codec.match_end       ↑codec.write_head
    # TODO I would rather not rely on last_literal being passed to this command: the codec should properly construct the literal_length itself, which means at last literal, codec.bytes_read should equal codec.write_head-1, not codec.write_head.
    lookback = codec.first_literal ? 0 : codec.match_start - codec.copy_start
    copy_length = codec.first_literal ? 0 : codec.match_end - codec.match_start + 1
    literal_length = codec.bytes_read - codec.match_end - 1
    return CommandPair(codec.first_literal, false, lookback, copy_length, literal_length)
end

function flush!(output, buffer::Vector{UInt8}, output_start::Int)
    to_flush = min(length(buffer), length(output) - output_start + 1) % Int
    copyto!(output, output_start, buffer, 1, to_flush)
    if to_flush == length(buffer)
        empty!(buffer)
    else
        circshift!(buffer, -to_flush)
        resize!(buffer, length(buffer) - to_flush)
    end
    return to_flush
end

function TranscodingStreams.process(codec::LZO1X1CompressorCodec, input::Memory, output::Memory, err::Error)

    # The input and output memory buffers are of indeterminate length, and the state of the codec at call time is arbitrary.
    #
    # This is what the input buffer looks like, each `-` representing a UInt8 value:
    #
    # input:  --------- ... ---
    # index: 1↑               ↑length(input)
    #
    # The output buffer looks similar:
    #
    # output: ????????? ... ???
    # index: 1↑               ↑length(output)
    #
    # Note that the output buffer might be filled with garbage at the start of each call to `process`.
    #
    # To begin, everything is loaded into a buffer with circular boundary conditions so we have the ability to lookup historical matches up to the lookback limit without having an infinitely large buffer or having to move data around all the time.
    # The buffer, called `codec.input_buffer`, has space for twice the lookback limit so we can guarantee that we still have all the possible historical matches available for the first byte of the input copied into the buffer.
    # By design, the buffer appears to run from index 1 to infinity, and at the start of the call to `process`, the algorithm has processed up to `codec.bytes_read`.
    # The `codec.write_head` is the index of the next byte that will be overwritten in the input_buffer, so the copy looks like this:
    #
    # Before:
    # input:  --------- ... ---
    # index: 1↑               ↑length(input)
    # input_buffer: ←******* ... ***---?? ... ???????→
    # index:        1↑   bytes_read↑   ↑write_head  ↑2*(lookback limit)
    #
    # After:
    # input_buffer: ←******* ... ***----- ... ---????→
    # index:        1↑   bytes_read↑            ↑   ↑2*(lookback limit)
    #                                           |write_head' = write_head+length(input)

    input_length = length(input) % Int

    # An input length of zero signals EOF, but only emit EOF if the entire input buffer was consumed
    last_literal = input_length == 0 && codec.bytes_read >= codec.write_head - LZO1X1_MIN_MATCH

    # Only copy up to the minimum buffer size
    to_read = min(input_length, LZO1X1_MIN_BUFFER_SIZE)
    if to_read > 0
        copyto!(codec.input_buffer, codec.write_head, input, 1, to_read)
        codec.write_head += to_read
    end

    # Consume everything in the buffer if possible
    n_written = 0
    stop_byte = last_literal ? codec.write_head - 1 : codec.write_head - LZO1X1_MIN_MATCH
    while codec.bytes_read < stop_byte

        # All commands are history+literal pairs except the first (literal only) and the last (EOS, which looks like history only).
        # The last command is already taken care of above.
        # If this is the first literal, the history part is skipped.
        if state(codec) == HISTORY
            # Invariants:
            #             (last_copy_byte)↓           ↓codec.match_start    ↓codec.write_head
            # input_buffer: ←--**** ... ***--- ... ---**** ... ***--- ... --??? ... →
            #                  ↑codec.copy_start                 ↑codec.bytes_read
            # always leave off the last LZO1X1_MIN_MATCH bytes: these will be picked up in emit_last_literal! if necessary.
            bytes_remaining = stop_byte - codec.bytes_read
            last_copy_byte = codec.copy_start + codec.bytes_read - codec.match_start
            n_bytes_matching = match_length(codec.input_buffer, last_copy_byte+1, codec.bytes_read+1, bytes_remaining)

            codec.bytes_read += n_bytes_matching
            if last_literal || n_bytes_matching != bytes_remaining
                codec.match_end = codec.bytes_read
                codec.state = LITERAL
            else
                continue
            end
        end

        if state(codec) == LITERAL
            # Invariants:
            #                  ↓codec.copy_start      ↓codec.match_start    ↓codec.bytes_read
            # input_buffer: ←--**** ... ***--- ... ---**** ... ***#### ... ##--- ... --??? ... →
            #                                                    ↑codec.match_end      ↑codec.write_head
            bytes_remaining = stop_byte - codec.bytes_read
            search_start = codec.bytes_read + 1
            match_start, copy_start = find_next_match!(codec.dictionary, codec.input_buffer, search_start, bytes_remaining, codec.skip_trigger, codec.match_end + 1)

            codec.next_copy_start = copy_start
            if match_start > 0
                codec.bytes_read = match_start
                append!(codec.literal_buffer, codec.input_buffer[search_start:codec.bytes_read-1])
                codec.state = COMMAND
            else
                codec.bytes_read += bytes_remaining
                append!(codec.literal_buffer, codec.input_buffer[search_start:codec.bytes_read])
            end

            if last_literal
                # last literal means we expect to reach the end of input, so call the literal copy complete and move on
                codec.state = COMMAND
            elseif match_start <= 0
                continue
            end
        end

        if state(codec) == COMMAND
            # Invariants:
            #                  ↓codec.copy_start        ↓codec.match_start        ↓codec.bytes_read
            # input_buffer: ←--**** ... ***--&-- ... ---**** ... ****#### ... ####&-- ... -??? ... →
            #                                ↑codec.next_copy_start ↑codec.match_end       ↑codec.write_head
            # this invariant requires that codec.bytes_read be one byte past the last literal (that is, pointing to the start of the next match)
            if last_literal
                codec.bytes_read += 1
            end
            command = build_command(codec)
            w = encode!(output, command, n_written + 1; last_literal_length=codec.last_literals_copied)
            if w > 0
                n_written += w
                codec.match_start = codec.bytes_read
                codec.copy_start = codec.next_copy_start
                codec.match_end = 0
                codec.next_copy_start = 0
                codec.first_literal = false
                codec.last_literals_copied = command.literal_length
                codec.state = FLUSH
            else
                # quit immediately because we ran out of output space
                return to_read, n_written, :ok
            end
        end

        if state(codec) == FLUSH
            n_written += flush!(output, codec.literal_buffer, n_written + 1)
            if !isempty(codec.literal_buffer)
                # quit immediately because we ran out of output space
                return to_read, n_written, :ok
            end
            codec.state = HISTORY
        end

    end

    status = :ok
    if last_literal
        w = encode!(output, END_OF_STREAM_COMMAND, n_written + 1)
        if w > 0
            n_written += w
            status = :end
        end
    end

    # We are done with this load
    return to_read, n_written, status

end

function TranscodingStreams.finalize(codec::LZO1X1CompressorCodec)
    empty!(codec.dictionary)
    fill!(codec.input_buffer, zero(UInt8))
    empty!(codec.literal_buffer)
    return
end
