abstract type LZOCompressorCodec <: TranscodingStreams.Codec end

mutable struct LZO1X1CompressorCodec <: LZOCompressorCodec
    working::Vector{UInt8}
    buffer::Vector{UInt8}
    buffer_used::Int
    
    LZO1X1CompressorCodec() = new(Vector{UInt8}(undef, MAX_TABLE_SIZE), Vector{UInt8}(undef, MAX_DISTANCE), 0)
end

function TranscodingStreams.initialize(codec::LZO1X1CompressorCodec)
    fill!(codec.working, 0)
    fill!(codec.buffer, 0)
    codec.buffer_used = 0
    return
end

function buffer_input!(codec::LZO1X1CompressorCodec, input::Memory, start_idx::Int, error::Error)
    @boundscheck if start_idx < 1 || start_idx > length(input)
        error[] = ErrorException("input start index $start_idx out of bounds")
        return 0, :error
    end
    @boundscheck if codec.buffer_used < 0 || codec.buffer_used > length(codec.buffer)
        error[] = ErrorException("buffer used $(codec.buffer_used) out of bounds")
        return 0, :error
    end
    input_remaining = length(input) - start_idx + 1
    buffer_remaining = length(codec.buffer) - codec.buffer_used
    to_copy = min(input_remaining, buffer_remaining)
    @inbounds copyto!(codec.buffer, codec.buffer_used+1, input, start_idx, to_copy)
    return to_copy, :ok
end

function compute_table_size(l::Int)
    # smallest power of 2 larger than l
    target = one(l) << ((sizeof(l)*8 - leading_zeros(l-one(l))) + 1)
    return clamp(target, MIN_TABLE_SIZE, MAX_TABLE_SIZE)
end

function compress_chunk!(codec::LZO1X1CompressorCodec, input::Memory, input_start::Int, output::Memory, output_start::Int, error::Error)
    input_length = length(input) - input_start + 1

    # nothing compresses to nothing
    # This should never happen
    if input_length == 0
        return 0, 0, :ok
    end

    # inputs that are smaller than the shortest lookback distance are emitted as literals
    if input_length < MIN_LENGTH
        return emit_last_literal(input, input_start, output, output_start, error; first_literal = true)
    end

    # build a working table
    table_size = compute_table_size(input_length)
    mask = table_size - 1
    fill!(codec.working, 0)

    # the very first byte is set in the table to the first memory index (1 in julia)
    # NOTE: this is different from the C implementation, which uses zero-indexed pointer offsets!
    codec.working[hash(unsafe_get(Int64, input, input_start), mask)] = 1

    input_idx = input_start+1
    next_hash = hash(unsafe_get(Int64, input, input_idx), mask)

    done = false
    first_literal = true
    n_read = 0
    n_written = 0
    while !done
        next_input_idx = input_idx
        find_match_attempts = 1 << SKIP_TRIGGER
        step = 1

        # loop until we find a match or run out of input to match
        while true
            h = next_hash
            input_idx = next_input_idx
            next_input_idx += step

            # ran out of matches to find, so emit remaining as a literal and quit
            if next_input_idx > MATCH_FIND_LIMIT
                r, w, status = emit_last_literal(input, input_start+n_read, output, output_start+n_written, error; first_literal = first_literal)
                n_read += r
                n_written += w
                return n_read, n_written, status
            end

            # step size decreases exponentially each miss
            step = find_match_attempts >>> SKIP_TRIGGER
            find_match_attempts += 1

            # get the index of the previous match (if any) from the working hash table
            # (what is the index match_index such that input[match_index] begins a match of what is in the input at input[input_idx])
            match_index = codec.working[h]
            next_hash = hash(unsafe_get(Int64, input, next_input_idx), mask)

            # put the position of the match identified by the hash onto the working hash table
            codec.working[h] = input_idx

            # if the past data matches the current data and it is the closest possible match to the current index, we have succeded
            if unsafe_get(Int32, input, match_index) == unsafe_get(Int32, input, input_idx) && match_index + MAX_DISTANCE >= input_idx
                break
            end
        end
    end
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