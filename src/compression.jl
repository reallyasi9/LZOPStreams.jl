abstract type AbstractLZOCompressorCodec <: TranscodingStreams.Codec end

mutable struct LZO1X1CompressorCodec <: AbstractLZOCompressorCodec
    dictionary::HashMap{Int32,Int}

    buffer::CircularArray{UInt8}
    read_head::Int
    write_head::Int
    
    first_literal::Bool
    state::Int

    LZO1X1CompressorCodec() = new(HashMap{Int32,Int}(MAX_TABLE_SIZE), CircularArray(UInt8(0), MAX_DISTANCE), 1, 1, true, 0)
end

function remaining(codec::LZO1X1CompressorCodec)
    return codec.write_head - codec.read_head
end

function TranscodingStreams.initialize(codec::LZO1X1CompressorCodec)
    empty!(codec.dictionary)
    fill!(codec.buffer, 0)
    codec.read_head = 1
    codec.write_head = 1
    codec.first_literal = true
    codec.state = 0
    return
end

function buffer_input!(codec::LZO1X1CompressorCodec, input::Union{AbstractVector{UInt8}, Memory}, error::Error)
    @boundscheck if codec.read_head < 1 || codec.write_head < 1 || codec.write_head < codec.read_head
        error[] = ErrorException("read/write buffer heads $(codec.read_head)/$(codec.write_head) out of bounds")
        return 0, :error
    end
    input_remaining = length(input)
    buffer_remaining = min(MAX_DISTANCE - remaining(codec), 0)
    to_copy = min(input_remaining, buffer_remaining)
    @inbounds copyto!(codec.buffer, codec.write_head, input, 1, to_copy)
    codec.write_head += to_copy
    return to_copy, :ok
end

function compute_table_size(l::Int)
    # smallest power of 2 larger than l
    target = one(l) << ((sizeof(l)*8 - leading_zeros(l-one(l))) + 1)
    return clamp(target, MIN_TABLE_SIZE, MAX_TABLE_SIZE)
end

function compress_chunk!(codec::LZO1X1CompressorCodec, output::AbstractVector{UInt8}, error::Error)
    input_length = remaining(codec)

    # Every read from the dictionary requires at least 4 bytes for lookup.
    # Ingest nothion, emit nothing, and wait for more data.
    if input_length < MIN_MATCH
        return 0, 0, :ok
    end

    # nothing compresses to nothing
    # This should never happen (see above)
    # if input_length == 0
    #     return 0, 0, :ok
    # end

    # inputs that are smaller than the shortest lookback distance are emitted as literals
    if input_length < MIN_LENGTH
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
        find_match_attempts = 1 << SKIP_TRIGGER
        step = 1

        # step forward in the input until we find a match or run out of input to match
        while true
            input_idx = next_input_idx
            next_input_idx += step

            # ran out of matches to find, so emit remaining as a literal and quit
            if next_input_idx > MATCH_FIND_LIMIT
                r, w, status = emit_last_literal!(output, n_written + 1, @view(input[n_read+1:end]), error; first_literal = first_literal)
                n_read += r
                n_written += w
                return n_read, n_written, status
            end

            # step size increases with logarithmic misses
            step = find_match_attempts >>> SKIP_TRIGGER
            find_match_attempts += 1

            # get the index of the previous match (if any) from the working hash table
            # (what is the index match_index such that input[match_index] begins a match of what is in the input at input[input_idx])
            input_long = reinterpret_get(Int64, input, input_idx)
            match_index = codec.working[input_long, mask]

            # update the position in the working dictionary for the next time we find this value
            codec.working[input_long, mask] = input_idx

            # if the first 4 bytes of the past data matches the current data and it is within the maximum distance allowed of the input, we have succeded!
            if reinterpret_get(Int32, input, match_index) == input_long % Int32 && match_index + MAX_DISTANCE >= input_idx
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

            input_idx += MIN_MATCH  # at least 4 bytes
            match_length = count_matching_bytes(input, input_idx, match_idx + MIN_MATCH, input_length - LAST_LITERAL_SIZE)
            input_idx += match_length

            # write the copy command to the output
            r, w, status = emit_copy!(output, n_written+1, offset, match_length + MIN_MATCH, error)
            n_read += r
            n_written += w
            if status != :ok
                return n_read, n_written, status
            end

            input_idx += r
            if input_idx > MATCH_FIND_LIMIT
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

    n_read = 0
    n_written = 0

    # input length of zero means reading has hit EOF, so write out all buffers
    input_length = length(input)
    if input_length == 0
        r, n_written, status = compress_chunk!(codec, codec.buffer, 1, output, n_written+1, error)
        codec.buffer_used -= r
        if status == :ok
            status = :end
        end
        return 0, n_written, status
    end

    # if the buffer has data in it, try to fill it with input
    if codec.buffer_used > 0
        r, status = buffer_input!(codec, input, n_read+1, error)
        n_read += r
        if status != :ok
            return n_read, n_written, status
        end
    end

    # if the buffer is full, dump it
    if codec.buffer_used == length(codec.buffer_used)
        r, w, status = compress_chunk!(codec, codec.buffer, 1, output, n_written+1, error)
        codec.buffer_used -= r
        n_written += w
        if status != :ok
            return n_read, n_written, status
        end
    end

    # with everything else, process one chunk at a time
    while length(input) - n_read >= MAX_DISTANCE
        r, w, status = compress_chunk!(codec, input, n_read+1, output, n_written+1, error)
        n_read += r
        n_written += w
        if status != :ok
            return n_read, n_written, status
        end
    end

    # if anything else is left, buffer it until the next call to process
    if length(input) - n_read > 0
        r, status = buffer_input!(codec, input, n_read+1, error)
        n_read += r
    end
    
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
    if length <= RUN_MASK
        output[start_index] = length % UInt8
        return 1
    end

    output[start_index] = 0
    n_written = 1
    start_index += 1
    remaining = length - RUN_MASK
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
    if offset > MAX_DISTANCE || offset < 1
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