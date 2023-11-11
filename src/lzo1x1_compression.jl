const LZO1X1_LAST_LITERAL_SIZE = 3  # the number of bytes in the last literal
const LZO1X1_LAST_LITERAL_MAX_SIZE = 20 # do not try to match in history if the remaining literal is this size or less
const LZO1X1_MIN_MATCH = 4  # the smallest number of bytes to consider in a dictionary lookup
const LZO1X1_MAX_INPUT_SIZE = 0x7e00_0000  # 2133929216 bytes
const LZO1X1_ML_BITS = 4  # 4 bits
const LZO1X1_RUN_BITS = 8 - LZO1X1_ML_BITS  # 4 bits
const LZO1X1_RUN_MASK = (1 << LZO1X1_RUN_BITS) - 1 # 0b00001111

const LZO1X1_MAX_DISTANCE = 0b11000000_00000000 - 1  # 49151 bytes, if a match starts further back in the buffer than this, it is considered a miss
const LZO1X1_SKIP_TRIGGER = 6  # This tunes the compression ratio: higher values increases the compression but runs slower on incompressable data

const LZO1X1_HASH_MAGIC_NUMBER = 0x1824429D
const LZO1X1_HASH_BITS = 13  # The number of bits that are left after shifting in the hash calculation

const LZO1X1_MIN_BUFFER_SIZE = LZO1X1_MAX_DISTANCE + LZO1X1_MIN_MATCH

@enum MatchingState begin
    FIRST_LITERAL # Waiting on end of first literal
    HISTORY # Waiting on end of historical match
    LITERAL # Waiting on end of long literal
end 

abstract type AbstractLZOCompressorCodec <: TranscodingStreams.Codec end

"""
    LZO1X1CompressorCodec <: AbstractLZOCompressorCodec

A `TranscodingStreams.Codec` struct that compresses data according to the 1X1 version of the LZO algorithm.

The LZO 1X1 algorithm is defined by:
- A lookback dictionary implemented as a hash map with a maximum of size of `1<<12 = 4096` elements that uses a specific fast hashing algorithm;
- A 4-byte history lookup window that scans the input with a logarithmically increasing skip distance;
- A maximum lookback distance of `0b11000000_00000000 - 1 = 49151` bytes;

The C implementation of LZO defined by liblzo2 requires that all compressable information be loaded in working memory at once, and is therefore not adaptable to streaming as required by TranscodingStreams. The C library version therefore uses only a 4096-byte hash map as additional working memory, while this version needs to keep the full 49151 bytes of history in memory in addition to the 4096-byte hash map.
"""
mutable struct LZO1X1CompressorCodec <: AbstractLZOCompressorCodec
    dictionary::HashMap{UInt32,Int} # 4096-element lookback history that maps 4-byte values to lookback distances

    input_buffer::CircularVector{UInt8} # 49151-byte history of uncompressed input data
    read_head::Int # The location of the byte to start reading (equal to the previous write_head before the buffer was refilled)
    write_head::Int # The location of the next byte in the buffer to write (serves also to mark the end of stream if input is shorter than buffer size)
    
    tries::Int # used to compute the step size each time a miss occurs in the stream
    
    state::MatchingState # Whether or not the compressor is awaiting more input to complete a match
    match_start_index::Int # If a match is found in the history, this is the starting index
    output_buffer::Vector{UInt8} # A buffer for matching past the end of a given input chunk (grows as needed)
    
    # In the case that a matching run of input ends at anything other than 4 bytes from the end of the input chunk,
    # the output_buffer will hold the copy command so that it can be updated with the proper number of literal copies
    # after the input buffer is refilled.

    previous_copy_command_was_short::Bool # Whether the previous copy command was a short lookback (1 byte command with 2 bits of literal copy + 1 distance byte) or a long lookback (1 byte command + N distance bytes with 2 bits of literal copy at LSB position)
    previous_literal_length::Int # The previous literal encoding length

    LZO1X1CompressorCodec() = new(HashMap{UInt32,Int}(
        LZO1X1_HASH_BITS,
        LZO1X1_HASH_MAGIC_NUMBER),
        CircularVector(zeros(UInt8, LZO1X1_MIN_BUFFER_SIZE)), # The circular array needs a small buffer to guarantee the next bytes read can be matched
        0,
        1,
        1 << LZO1X1_SKIP_TRIGGER,
        FIRST_LITERAL,
        0,
        Vector{UInt8}(),
        false,
        0,
    )
end

const LZOCompressorCodec = LZO1X1CompressorCodec
const LZOCompressorStream{S} = TranscodingStream{LZO1X1CompressorCodec,S}

function TranscodingStreams.initialize(codec::LZO1X1CompressorCodec)
    empty!(codec.dictionary)
    codec.input_buffer .= 0
    codec.read_head = 0
    codec.write_head = 1
    codec.tries = 1 << LZO1X1_SKIP_TRIGGER
    codec.state = FIRST_LITERAL
    codec.match_start_index = 0
    empty!(codec.output_buffer)
    codec.previous_copy_command_was_short = false
    codec.previous_literal_length = 0
    return
end

function TranscodingStreams.minoutsize(codec::LZO1X1CompressorCodec, input::Memory)
    # The worst-case scenario is a super-long literal, in which case the input has to be emitted in its entirety along with the output buffer
    # plus the appropriate commands to start a long literal or match and end the stream.
    if codec.state == HISTORY
        # CMD + HISTORY_RUN + HISTORY_REMAINDER + DISTANCE + CMD + LITERAL_RUN + LITERAL_REMAINDER + LITERAL + EOS + buffer
        return 1 + (codec.write_head - codec.match_start_index) ÷ 255 + 1 + 2 + 1 + length(input) ÷ 255 + 1 + length(input) + 3 + 64
    else
        # CMD + LITERAL_RUN + LITERAL_REMAINDER + LITERAL + CMD + LITERAL_RUN + LITERAL_REMAINDER + LITERAL + EOS + buffer
        return 1 + length(codec.output_buffer) ÷ 255 + 1 + length(codec.output_buffer) + 1 + length(input) ÷ 255 + 1 + length(input) + 3 + 64
    end
end

function TranscodingStreams.expectedsize(codec::LZO1X1CompressorCodec, input::Memory)
    # Usually around 2.4:1 compression ratio with a minimum around 5 bytes (see https://morotti.github.io/lzbench-web)
    return max((length(codec.output_buffer) + length(input)) ÷ 2, 5)
end

function TranscodingStreams.startproc(codec::LZO1X1CompressorCodec, mode::Symbol, error::Error)
    if mode != :write
        error[] = ErrorException("$(type(codec)) is write-only")
        return :error
    end
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
    while n_read < input_length
        n_read += consume_input!(codec, input, n_read + 1)

        # The buffer is processed and potentially data is written to output
        n_written += compress_and_emit!(codec, output, n_written + 1)
    end

    # We are done
    return n_read, n_written, :ok

end

"""
    n_written = encode_run(output, start_index, len, bits)

Emit the number of zero bytes necessary to encode a length `len` in a command expecting `bits` leading bits.

Literal and copy lengths are always encoded as either a single byte or a sequence of three or more bytes. If `len < (1 << bits)`, the length will be encoded in the lower `bits` bits of the starting byte of `output` so the return will be 0. Otherwise, the return will be the number of additional bytes needed to encode the length. The returned number of bytes does not include the zeros in the first byte (the command) used to signal that a run encoding follows, but it does include the remainder.

Note: the argument `len` is expected to be the _adjusted length_ for the command. Literals use an adjusted length of `len = length(literal) - 3` and copy commands use an adjusted literal length of `len = length(copy) - 2`.
"""
function encode_run!(output::Union{AbstractVector{UInt8},Memory}, start_index::Int, len::Int, bits::Int)
    if len < 1 << bits
        output[start_index] |= len % UInt8
        return 0
    end
    mask = UInt8(1 << bits - 1)
    len -= mask
    output[start_index] &= ~mask # clear the bits just in case
    n_written = 0
    while len >= 255
        len -= 255
        n_written += 1
        output[start_index + n_written] = 0 % UInt8
    end
    n_written += 1
    output[start_index + n_written] = len % UInt8
    return n_written
end

function find_next_match!(codec::LZO1X1CompressorCodec, input_idx::Int)
    while input_idx <= codec.write_head - LZO1X1_MIN_MATCH
        input_long = reinterpret_get(UInt32, codec.input_buffer, input_idx)
        match_idx = replace!(codec.dictionary, input_long, input_idx)
        if match_idx > 0 && input_idx - match_idx < LZO1X1_MAX_DISTANCE
            return match_idx, input_idx
        end
        # TODO: figure out if this resets each match attempt or if it is a global running sum
        input_idx += codec.tries >>> LZO1X1_SKIP_TRIGGER        
        codec.tries += 1
    end
    return -1, input_idx
end

function encode_literal_length!(codec::LZO1X1CompressorCodec, output::Union{AbstractVector{UInt8},Memory}, start_index::Int)

    # In LZO1X1, the first literal is always at least 4 bytes and, if it is small, is 
    # specially coded.
    len = length(codec.output_buffer)

    if codec.state == FIRST_LITERAL && len < (0xff - 17)
        output[index] = (len+18) % UInt8
        codec.previous_literal_length = len
        return 1
    end

    # Except for the first literal, literal copies always follow history copies, so a command should always be in the buffer.

    # 2-bit literal lengths are encoded in the low two bits of the previous command.
    # Commands are encoded as 16-bit LEs, and either the LSB of the 1st byte or 2nd byte are overwritten
    # depending on the length of the previous history copy.
    output[start_index] = popfirst!(codec.output_buffer)
    output[start_index+1] = popfirst!(codec.output_buffer)
    n_written = 2
    len -= 2
    codec.previous_literal_length = len
    if len < 4
        idx_offset = codec.previous_copy_command_was_short ? 0 : 1
        output[start_index+idx_offset] |= len % UInt8
        return n_written
    end

    # everything else is encoded raw or as a run of unary zeros plus a remainder
    len -= 3
    n_written += encode_run!(output, start_index, len, LZO1X1_RUN_BITS)
    
    return n_written
end

# Write a literal from `codec.output_buffer` to `output` starting at `start_index`.
# Returns the number of bytes written to output and a status flag.
function emit_literal!(codec::LZO1X1CompressorCodec, output::Union{AbstractVector{UInt8},Memory}, start_index::Int)
    n_written = encode_literal_length!(codec, output, start_index)
    len = length(codec.output_buffer)
    unsafe_copyto!(output, start_index + n_written, codec.output_buffer, 1, len)
    resize!(codec.output_buffer, 0)
    return n_written + len
end

# End of stream is a copy of bytes from a distance of zero in the history
function emit_last_literal!(codec::LZO1X1CompressorCodec, output::Union{AbstractVector{UInt8},Memory}, start_index::Int)
    # in the middle of a history lookup means I can write that now
    n_written = 0
    if codec.state == HISTORY
        n_matching = count_matching(
            @view(codec.input_buffer[codec.read_head:codec.write_head-1]),
            @view(codec.input_buffer[codec.match_start_index:codec.write_head-1]))
        distance = codec.read_head - codec.match_start_index
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
    begin
        output[start_index+n_written] = 0b00010001
        output[start_index+n_written+1] = 0 % UInt8
        output[start_index+n_written+2] = 0 % UInt8
    end
    return n_written + 3
end

function emit_copy!(codec::LZO1X1CompressorCodec, output::Union{AbstractVector{UInt8},Memory}, start_index::Int, distance::Int, N::Int)
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
        push!(codec.output_buffer, 0b01000000 | (L << 5) | (D << 2))
        push!(codec.output_buffer, H)
        codec.previous_copy_command_was_short = true
        return 0
    elseif 5 <= N <= 8 && distance <= 2049
        # 0b1LLDDDSS_HHHHHHHH, distance = (H << 3) + D + 1
        distance -= 1
        D = UInt8(distance & 0b00000111)
        H = UInt8((distance - D) >> 3)
        L = UInt8(N - 5)
        push!(codec.output_buffer, 0b10000000 | (L << 5) | (D << 2))
        push!(codec.output_buffer, H)
        codec.previous_copy_command_was_short = true
        return 0
    else
        if distance < 16384
            # 0b001LLLLL_*_DDDDDDDD_DDDDDDSS, distance = D + 1, length = 2 + (L ?: *)
            run = encode_run!(output, start_index, N-2, 5)
            output[start_index] |= 0b00100000
            distance -= 1
        else
            # 0b0001HLLL_*_DDDDDDDD_DDDDDDSS, distance = 16384 + (H << 14) + D, length = 2 + (L ?: *)
            run = encode_run!(output, start_index, N-2, 3)
            output[start_index] |= 0b00010000
            distance -= 16384
            H = UInt8((distance >> 14) & 1)
            output[start_index] |= H << 3
        end
        DH = UInt8((distance >> 6) & 0b11111111)
        DL = UInt8(distance & 0b00111111)
        push!(codec.output_buffer, DH)
        push!(codec.output_buffer, DL << 2)
        codec.previous_copy_command_was_short = false
        return run
    end
end

function consume_input!(codec::LZO1X1CompressorCodec, input::Union{AbstractVector{UInt8}, Memory}, input_start::Int)
    len = length(input) - input_start + 1
    to_copy = min(len, LZO1X1_MAX_DISTANCE)
    # Memory objects do not allow range indexing, and circular vectors do not allow copyto!
    for i in 0:to_copy-1
        @inbounds codec.input_buffer[codec.write_head + i] = input[input_start + i]
    end
    codec.read_head = codec.write_head
    codec.write_head += to_copy
    return to_copy
end

function compress_and_emit!(codec::LZO1X1CompressorCodec, output::Union{AbstractVector{UInt8}, Memory}, output_start::Int)
    input_length = codec.write_head - codec.read_head

    # nothing compresses to nothing
    # This should never happen, as it signals EOS and that is handled elsewhere
    if input_length == 0
        return 0
    end

    input_idx = codec.read_head
    n_written = 0

    while input_idx <= codec.write_head - LZO1X1_LAST_LITERAL_MAX_SIZE
        # If nothing has been written yet, load everything into the output buffer until the match is found
        if codec.state == FIRST_LITERAL || codec.state == LITERAL
            next_match_idx, input_idx = find_next_match!(codec, input_idx)

            # Put everything from the read head to just before the input index into the output buffer
            @inbounds append!(codec.output_buffer, codec.input_buffer[codec.read_head:input_idx-1])
            if input_idx > codec.write_head - LZO1X1_MIN_MATCH
                # If out of input, wait for more
                return n_written
            end
            # Match found, meaning we have the entire literal
            n_written += emit_literal!(codec, output, output_start + n_written)
            codec.match_start_index = next_match_idx
            codec.read_head = input_idx

            # At this point, we have the next match in match_start_index
            codec.state = HISTORY
        end

        # If we have a history lookup, find the length of the match
        n_matching = count_matching(
            @view(codec.input_buffer[input_idx:codec.write_head-1]),
            @view(codec.input_buffer[codec.match_start_index:codec.write_head-1]))
        distance = input_idx - codec.match_start_index
        input_idx += n_matching
        if input_idx == codec.write_head
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

