const LZO1X1_LAST_LITERAL_SIZE = 5  # the number of bytes in the last literal
const LZO1X1_MIN_MATCH = 4  # the smallest number of bytes to consider in a dictionary lookup
const LZO1X1_MAX_INPUT_SIZE = 0x7e00_0000  # 2133929216 bytes
const LZO1X1_HASH_LOG = 12  # 1 << 12 = 4 KB maximum dictionary size
const LZO1X1_MIN_TABLE_SIZE = 16
const LZO1X1_MAX_TABLE_SIZE = 1 << LZO1X1_HASH_LOG
const LZO1X1_COPY_LENGTH = 8  # copy this many bytes at a time, if possible
const LZO1X1_MATCH_FIND_LIMIT = LZO1X1_COPY_LENGTH + LZO1X1_MIN_MATCH  # 12
const LZO1X1_MIN_LENGTH = LZO1X1_MATCH_FIND_LIMIT + 1
const LZO1X1_ML_BITS = 4  # match lengths can be up to 1 << 4 - 1 = 15
const LZO1X1_RUN_BITS = 8 - LZO1X1_ML_BITS  # match runs can be up to 1 << 4 - 1 = 15
const LZO1X1_RUN_MASK = (1 << LZO1X1_RUN_BITS) - 1

const LZO1X1_MAX_DISTANCE = 0b11000000_00000000 - 1  # 49151 bytes, if a match starts further back in the buffer than this, it is considered a miss
const LZO1X1_SKIP_TRIGGER = 6  # This tunes the compression ratio: higher values increases the compression but runs slower on incompressable data

const LZO1X1_HASH_MAGIC_NUMBER = 889523592379
const LZO1X1_HASH_BITS = 28

const LZO1X1_MIN_BUFFER_LENGTH = LZO1X1_MAX_DISTANCE + LZO1X1_MATCH_FIND_LIMIT

abstract type AbstractLZOCompressorCodec <: TranscodingStreams.Codec end

"""
    LZO1X1CompressorCodec <: AbstractLZOCompressorCodec

A `TranscodingStreams.Codec` struct that compresses data according to the 1X1 version of the LZO algorithm.

The LZO 1X1 algorithm is defined by:
- A lookback dictionary implemented as a hash map with a maximum of size of at most `1<<12 = 4096` elements and as few as 16 elements using a specific fast hashing algorithm;
- An 8-byte history lookup window that scans the input with a logarithmically increasing skip distance;
- A maximum lookback distance of `0b11000000_00000000 - 1 = 49151`;

The C implementation of LZO defined by liblzo2 requires that all compressable information be loaded in working memory at once, and is therefore not adaptable to streaming as required by TranscodingStreams. The C library version therefore uses only a 4096-byte hash map as additional working memory, while this version needs to keep the full 49151 bytes of history in memory in addition to the 4096-byte hash map.
"""
mutable struct LZO1X1CompressorCodec <: AbstractLZOCompressorCodec
    dictionary::HashMap{Int32,Int} # 4096-element lookback history that maps 4-byte values to lookback distances

    buffer::CircularBuffer # 49151-byte history of uncompressed input data
    
    first_literal::Bool # Whether or not the literal to be written to the output stream is the first value written, which requires special opcodes in LZO
    state::UInt8 # 2-bit number of literal bytes to be skipped after the most recent dictionary lookup command
    tries::Int # used to compute the step size each time a miss occurs in the stream

    still_consuming::Bool # Whether we are still consuming input to check match length or literal length
    literal_match::Bool # Whether the current match is a literal or a history match
    match_length::Int # Length of the match (so far)

    LZO1X1CompressorCodec() = new(HashMap{Int32,Int}(
        LZO1X1_MAX_TABLE_SIZE,
        LZO1X1_HASH_MAGIC_NUMBER,
        LZO1X1_HASH_BITS),
        CircularBuffer(LZO1X1_MIN_BUFFER_LENGTH), # The circular array needs a small buffer to guarantee the next bytes read can be matched
        true,
        UInt8(0),
        1 << LZO1X1_SKIP_TRIGGER,
        false,
        false,
        0,
    )
end

function TranscodingStreams.initialize(codec::LZO1X1CompressorCodec)
    empty!(codec.dictionary)
    codec.write_head = 1
    codec.read_head = 1
    codec.first_literal = true
    codec.state = UInt8(0)
    return
end

function TranscodingStreams.minoutsize(codec::LZO1X1CompressorCodec, input::Memory)
    # If nothing has been cached, we can base this off the input alone.
    # EOS is always 3 bytes
    extra_bytes = 3
    if codec.first_literal
        if length(input) == 0
            # An empty input produces empty output.
            return 0
        elseif length(input) < 4
            # We need to encode at least a single byte encoding the length, the literal itself, then potentially a three-byte EOS command.
            return 1 + length(input) + extra_bytes
        else
            # Encode at least the first 4 bytes as literal plus a length byte
            extra_bytes += 5
        end
    end

    # The best we can possibly do with the remaining input is emit a command of some length, a single byte per 255 copies from the previous input, then a three-byte EOS command.
    remainder = remaining_to_read(codec) + length(input)
    if remainder <= 12
        return 2 + extra_bytes
    else
        # 3 byte command plus 1 byte per 255 copies emitted
        return 3 + remainder ÷ 255 + extra_bytes
    end
end

function TranscodingStreams.expectedsize(codec::LZO1X1CompressorCodec, input::Memory)
    # Usually around 2:1 compression ratio with a minimum around 5 bytes
    return max((remaining_to_read(codec) + length(input)) ÷ 2, 5)
end

function load_buffer!(codec::LZO1X1CompressorCodec, input::Union{AbstractVector{UInt8}, Memory}, error::Error, from::Int = 1, len::Int = length(input))
    input_length = length(input)
    
    if input_length < buffer_free_space(codec)
        copyto!(codec.buffer, codec.write_head, input, 1, input_length)
        codec.write_head += input_length
        return input_length, :ok
    end


    
    # If we are in the middle of a match, we can throw away everything up to the 

    @boundscheck if codec.write_head + len >= LZO1X1_MAX_INPUT_SIZE
        error[] = ErrorException("input of length $(len) would result in total input size of $(codec.write_head + len) > $LZO1X1_MAX_INPUT_SIZE")
        return 0, :error
    end
    to_copy = min(len, LZO1X1_MAX_DISTANCE)
    @inbounds copyto!(codec.buffer, codec.write_head, input, from, to_copy)
    codec.write_head += to_copy
    return to_copy, :ok
end

function compute_table_size(l::Int)
    # smallest power of 2 larger than l
    target = one(l) << ((sizeof(l)*8 - leading_zeros(l-one(l))) + 1)
    return clamp(target, LZO1X1_MIN_TABLE_SIZE, LZO1X1_MAX_TABLE_SIZE)
end

function compress_chunk!(codec::LZO1X1CompressorCodec, output::AbstractVector{UInt8}, error::Error)
    input_length = remaining(codec)

    

    # nothing compresses to nothing
    # This should never happen (see above)
    # if input_length == 0
    #     return 0, 0, :ok
    # end

    # inputs that are smaller than the shortest lookback distance are emitted as literals
    if input_length < LZO1X1_MIN_LENGTH
        return emit_last_literal!(output, 1, input, error, input_length; first_literal = true)
    end

    # build a working table
    table_size = compute_table_size(input_length)
    mask = table_size - 1
    empty!(codec.working)

    # the very first byte is set in the table to the first memory index (1 in julia)
    # NOTE: this is different from the C implementation, which uses zero-indexed pointer offsets!
    input_idx = 1
    codec.working[reinterpret_get(Int64, input, input_idx), mask] = 1

    input_idx += 1
    done = false
    first_literal = true
    n_read = 0
    n_written = 0
    while !done
        # the index of the input we are reading to look for a match in the dictionary
        next_input_idx = input_idx

        # it takes until the next power of 2 misses before the step size increases by 1 additional byte
        # (so when we have done this 1 << (SKIP_TRIGGER + 1) times, step size becomes 2, and so on)
        find_match_attempts = 1 << LZO1X1_SKIP_TRIGGER
        step = 1

        # step forward in the input until we find a match or run out of input to match
        while true
            input_idx = next_input_idx
            next_input_idx += step

            # ran out of matches to find, so emit remaining as a literal and quit
            if next_input_idx > LZO1X1_MATCH_FIND_LIMIT
                r, w, status = emit_last_literal!(output, n_written + 1, @view(input[n_read+1:end]), error; first_literal = first_literal)
                n_read += r
                n_written += w
                return n_read, n_written, status
            end

            # step size increases with logarithmic misses
            step = find_match_attempts >>> LZO1X1_SKIP_TRIGGER
            find_match_attempts += 1

            # get the index of the previous match (if any) from the working hash table
            # (what is the index match_index such that input[match_index] begins a match of what is in the input at input[input_idx])
            input_long = reinterpret_get(Int64, input, input_idx)
            match_index = codec.working[input_long, mask]

            # update the position in the working dictionary for the next time we find this value
            codec.working[input_long, mask] = input_idx

            # if the first 4 bytes of the past data matches the current data and it is within the maximum distance allowed of the input, we have succeded!
            if reinterpret_get(Int32, input, match_index) == input_long % Int32 && match_index + LZO1X1_MAX_DISTANCE >= input_idx
                break
            end
        end

        # everything from the input to the first match is emitted as a literal
        # rewind the stream until the first non-matching byte is found
        # NOTE: input_idx >= match_index, so this should always be inbounds
        while input_idx > n_read && match_index > 1 && @inbounds input[input_idx-1] == input[match_index-1]
            input_idx -= 1
            match_index -= 1
        end

        # now that we are back to the first non-matching byte in the input, emit everything up to the matched input as a literal
        literal_length = input_idx - n_read
        r, w, status = emit_literal!(output, n_written + 1, @view(input[n_read+1:n_read+literal_length+1]), error, literal_length; first_literal = first_literal)
        n_read += r
        n_written += w
        if status != :ok
            return n_read, n_written, status
        end
        first_literal = false

        # find the length of the match and write that to the output instead of the matched data
        while true
            offset = input_idx - match_index

            input_idx += LZO1X1_MIN_MATCH  # at least 4 bytes
            match_length = count_matching_bytes(input, input_idx, match_idx + LZO1X1_MIN_MATCH, input_length - LZO1X1_LAST_LITERAL_SIZE)
            input_idx += match_length

            # write the copy command to the output
            r, w, status = emit_copy!(output, n_written+1, offset, match_length + LZO1X1_MIN_MATCH, error)
            n_read += r
            n_written += w
            if status != :ok
                return n_read, n_written, status
            end

            input_idx += r
            if input_idx > LZO1X1_MATCH_FIND_LIMIT
                done = true
                break
            end

            # store where the position occured
            position = input_idx - 2
            codec.working[reinterpret_get(Int64, input, position), mask] = position

            # test the next position and move forward until we no longer match
            # update the match location in the working dictionary
            input_value = reinterpret_get(Int64, input, input_idx)
            match_index = codec.working[input_value, mask]
            codec.working[input_value, mask] = input_idx

            if match_index + MAX_DISTANCE < input_idx || reinterpret_get(Int32, input, match_index) != reinterpret_get(Int32, input, input_idx)
                input_idx += 1
                break
            end
        end
    end

    # and we're done!
    # everything else is literal data that cannot be compressed
    r, w, status = emit_last_literal!(output, n_written + 1, @view(input[n_read+1:end]), error; first_literal = false)
    n_read += r
    n_written += w
    return n_read, n_written, status
end

function TranscodingStreams.process(codec::LZO1X1CompressorCodec, input::Memory, output::Memory, error::Error)

    input_length = length(input)
    
    # An input length of zero signals EOF
    if input_length == 0
        # Everything remaining in the buffer has to be flushed as a literal because it didn't match
        r, w, status = emit_last_literal!(codec, output, 1, error)
        if status == :ok
            status = :end
        end
        return r, w, status
    end

    # Everything else is loaded into the buffer and consumed
    r, status = load_buffer!(codec, input, error)
    if status != :ok
        return r, 0, status
    end

    # The buffer is processed and potentially data is written to output
    w, status = process_buffer!(codec, output, error)

    # We are done
    return r, w, status


    # Every read from the dictionary requires at least 4 bytes for lookup.
    # Ingest nothing, emit nothing, and wait for more data.
    if input_length < LZO1X1_MIN_MATCH
        return 0, 0, :ok
    end

    input_idx = 1
    n_read = 0
    n_written = 0

    # If this is the very first call to process data, mark the location in the dictionary put the first 8 bytes into the buffer for later use.
    # Remember that the lookup table stores the read location in the buffer, not the lookback distance.
    if codec.write_head == 1
        # We need at least 8 bytes to put something on the lookup table.
        if input_length < LZO1X1_COPY_LENGTH
            return 0, 0, :ok
        end

        codec.dictionary[reinterpret_get(Int64, input, input_idx)] = 1
        r, status = buffer_input!(codec, input, error, input_idx, sizeof(Int64))
        n_read += r
        if status != :ok
            return n_read, n_written, status
        end
        input_idx += 1
    end

    # Consume input until the number of bytes remaining is less than the minimum required to find a match
    match_idx = 0 # the location of the first 4-byte match found
    step = 1 # The last step in number of bytes taken when looking for a match
    while input_length - input_idx + 1 < LZO1X1_MATCH_FIND_LIMIT
        # Find the first 4-byte match

        # This is a strange part of the algorithm: it asks for a hash of an 8-byte value, but the hash map only has resolution to 28 bits, so we are sure to collide both with the 4-byte match and with a bunch of other things.
        # It is unclear why this is 8 bytes instead of 4 bytes.
        # Silmultaneously Load this location back onto the dictionary as the closest location of this 8-byte value so the hash only has to be calculated once.
        input_long_value = reinterpret_get(Int64, input, input_idx)
        match_idx = replace!(codec.dictionary, input_long_value, input_idx)

        # This requires that another `step` bytes be buffered
        r, status = buffer_input!(codec, input, error, input_idx, step)
        n_read += r
        if status != :ok
            return n_read, n_written, status
        end

        step = codec.tries >>> LZO1X1_SKIP_TRIGGER        
        input_idx += step
        codec.tries += 1

        # No match is easy to detect: the match index is zero
        # Out of range matches are a bit harder to detect
        if match_idx == 0 || codec.write_head - match_idx > LZO1X1_MAX_DISTANCE
            continue
        end

        # At match of 4 bytes, break
        if reinterpret_get(Int32, input, input_idx) == reinterpret_get(Int32, codec.buffer, match_idx)
            break
        end
    end

    # Everything put into the buffer so far by definition did not match anything in the dictionary, so it is a literal to emit
    r, w, status = emit_literal!(output, n_written+1, codec.buffer, codec.read_head, error, codec.write_head-codec.read_head; first_literal=codec.first_literal)
    codec.first_literal = false
    codec.read_head += r
    n_written += w
    if status != :ok
        return n_read, n_written, status
    end

    # If nothing was found, wait for the next input
    if match_idx == 0 || codec.write_head - match_idx > LZO1X1_MAX_DISTANCE
        return n_read, n_written, :ok
    end

    # TODO: Get length of match, output copy command with potential literal match, loop
    
    # done: wait for next call to process
    return n_read, n_written, :ok
end

function encode_literal_length!(output::AbstractVector{UInt8}, start_index::Int, length::Int; first_literal::Bool=false)

    # code 17 is used to signal the first literal value in the stream when reading back
    if first_literal && length < (0xff - 17)
        output[start_index] = (length+17) % UInt8
        return 1
    end

    # 2-bit literal lengths are encoded in the low two bits of the previous command.
    # commands are encoded as 16-bit LEs
    if length < 4
        output[start_index-2] = (output[start_index-2] | length) % UInt8
        return 0
    end

    # everything else is encoded in the strangest way possible...
    # encode (length - 3 - RUN_MASK)/256 in unary zeros, then encode (length - 3 - RUN_MASK) % 256 as a byte
    length -= 3
    if length <= LZO1X1_RUN_MASK
        output[start_index] = length % UInt8
        return 1
    end

    output[start_index] = 0
    n_written = 1
    start_index += 1
    remaining = length - LZO1X1_RUN_MASK
    while remaining > 255
        output[start_index] = 0
        start_index += 1
        n_written += 1
        remaining -= 255
    end
    output[start_index] = remaining % UInt8
    n_written += 1

    return n_written
end

# Write a literal from `input` of length `literal_length` to `output` starting at `start_index`.
# Note that all literals should have lengths a multiple of 8 bytes except the last literal in the stream.
# Returns the number of bytes read from input, the number of bytes written to output, and a status symbol.
function emit_literal!(output::AbstractVector{UInt8}, start_index::Int, input::AbstractVector{UInt8}, error::Error, literal_length::Int=length(input); first_literal::Bool=false)
    if literal_length % 8 != 0
        error[] = ErrorException("literal length $literal_length not a multiple of 8 bytes")
        return 0, 0, :error
    end
    n_written = encode_literal_length!(output, start_index, literal_length; first_literal=first_literal)
    copyto!(output, start_index + n_written, input, 1, literal_length)
    return literal_length, n_written + literal_length, :ok
end

# Write the last literal from `input` of length `literal_length` to `output` starting at `start_index`.
# The last literal can be any length.
# Returns the number of bytes read from input, the number of bytes written to output, and a status symbol.
function emit_last_literal!(output::AbstractVector{UInt8}, start_index::Int, input::AbstractVector{UInt8}, error::Error, literal_length::Int=length(input); first_literal::Bool=false)
    n_written = encode_literal_length!(output, start_index, literal_length; first_literal=first_literal)
    copyto!(output, start_index + n_written, input, 1, literal_length)
    n_written += literal_length
    # write stop command 0b0001HMMM with zero match offset (16 bits)
    output[start_index + n_written] = 0b00010001
    output[start_index + n_written + 1] = 0
    output[start_index + n_written + 2] = 0
    return literal_length, start_index + n_written + 3, :ok
end

function count_matching_bytes(input::AbstractVector{UInt8}, start_index::Int, match_start_index::Int, match_limit::Int)
    current = start_index

    # TODO: there has to be a SIMD way to do this, but aliasing might get in the way...
    # Try 8 bytes at a time using some magic calculations
    while current < match_limit - (sizeof(Int64) - 1)
        diff = reinterpret_get(Int64, input, match_start_index) ⊻ reinterpret_get(Int64, input, current)
        # Non-matching bits found, so use the bits as a mask
        if diff != 0
            current += trailing_zeros(diff) >> 3
            return current - start_index
        end
    end

    # Try in decreasing size of integers to figure out the remainder
    if current < match_limit - (sizeof(Int32) - 1) && reinterpret_get(Int32, input, match_start_index) == reinterpret_get(Int32, input, current)
        current += sizeof(Int32)
        match_start_index += sizeof(Int32)
    end

    if current < match_limit - (sizeof(Int16) - 1) && reinterpret_get(Int16, input, match_start_index) == reinterpret_get(Int16, input, current)
        current += sizeof(Int16)
        match_start_index += sizeof(Int16)
    end

    if current < match_limit - (sizeof(UInt8) - 1) && @inbounds input[match_start_index] == input[current]
        current += 1
    end

    return current - start_index
end

function emit_copy!(output::AbstractVector{UInt8}, start_index::Int, offset::Int, match_length::Int, error::Error)
    if offset > LZO1X1_MAX_DISTANCE || offset < 1
        error[] = ErrorException("unsupported copy offset $offset")
        return 0, :error
    end

    # small copies with small offsets pack the information into two bytes
    if match_length <= 8 && offset <= 2048
        # 0bMMMP_PP00 0bPPPP_PPPP
        # M = length-1 (3 bits)
        # P = offset-1 (11 bits)
        # L = reserved?
        match_length -= 1
        offset -= 1
        output[start_index] = ((match_length % UInt8) << 5) | ((offset % UInt8) & 0b111) << 2
        output[start_index+1] = (offset % UInt8) >>> 3

        return 2, :ok
    end

    # everything else is encoded as length-2
    match_length -= 2

    n_written = 0
    if offset >= (1<<15)
        # 0b0001_1MMM (0bMMMM_MMMM)* 0bPPPP_PPPP_PPPP_PPLL
        # M = length-2 (3 + 8x bits)
        # P = offset (14 bits)
        # L = reserved?
        n_written = encode_match_length!(output, start_index, match_length, 0b0000_0111, 0b0001_1000)
    elseif offset > (1 << 14)
        # 0b0001_0MMM (0bMMMM_MMMM)* 0bPPPP_PPPP_PPPP_PPLL
        # M = length-2 (3 + 8x bits)
        # P = offset (14 bits)
        # L = reserved?
        n_written = encode_match_length!(output, start_index, match_length, 0b0000_0111, 0b0001_0000)
    else
        # 0b001M_MMMM (0bMMMM_MMMM)* 0bPPPP_PPPP_PPPP_PPLL
        # M = length-2 (5 + 8x bits)
        # P = offset (14 bits)
        # L = reserved?
        n_written = encode_match_length!(output, start_index, match_length, 0b0001_1111, 0b0010_0000)
        # this command encodes offset-1
        offset -= 1
    end

    n_written += encode_offset!(output, start_index+n_written, offset)

    return n_written, :ok
end

function encode_match_length!(output::AbstractVector{UInt8}, start_index::Int, match_length::Int, match_length_high_bits::UInt8, command::UInt8)
    
    if match_length < match_length_high_bits
        # Tiny lengths just get packed in with the command
        output[start_index] = command | match_length % UInt8
        return 1
    end

    # Otherwise, everything but the remainder of the length minus the base is stored as zeros
    output[start_index] = command
    n_written = 1
    remainder = match_length - match_length_high_bits
    while remainder > 255
        output[start_index+n_written] = 0
        n_written += 1
        remainder -= 255
    end
    output[start_index+n_written] = remainder % UInt8
    n_written +=1
    
    return n_written

end

function encode_offset!(output::AbstractVector{UInt8}, start_index::Int, offset::Int)
    output[start_index] = (offset & 0xff) % UInt8
    output[start_index+1] = ((offset >>> 8) & 0xff) % UInt8
    return 2
end