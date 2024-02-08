# All LZO-1 streams encode data in the same way

@enum DecompressionState begin
    AWAITING_FIRST_LITERAL
    AWAITING_COMMAND
    COPYING_HISTORY
    READING_LITERAL
    FLUSHING
    END_OF_STREAM
end

"""
    LZO1X1DecompressorCodec <: TranscodingStreams.Codec

A struct that decompresses data according to the 1X1 version of the LZO algorithm.

The LZO 1X1 algorithm is a Lempel-Ziv lossless compression algorithm. Compressed streams consist of alternating encoded instructions and sequences of literal values. The encoded instructions tell the decompressor to either:
1. copy a sequence of bytes of a particular length directly from the input to the output (literal copy), or
2. look back a certain distance in the already returned output and copy a sequence of bytes of a particular length from the output to the output again.

For implementation purposes, this decompressor uses a buffer of 49151 bytes to store output. This is equal to the maximum lookback distance of the LZO 1X1 algorithm.

The C implementation of LZO defined by liblzo2 requires that all decompressed information be available in working memory at once, and is therefore not adaptable to streaming as required by TranscodingStreams. The C library version claims to use no additional working memory, but it requires that a continuous space in memory be available to hold the entire output of the compressed data, the length of which is not knowable _a priori_ but can be larger than the compressed data by a factor of roughly 255. This implementation needs to keep 49151 bytes of output history in memory while decompressing, equal to the maximum lookback distance of the LZO 1x1 algorithm, and a small number of bytes to keep track of the command being processed in case the command is broken between multiple reads from the input memory.
"""
mutable struct LZO1X1DecompressorCodec <: TranscodingStreams.Codec
    input_buffer::Vector{UInt8} # TranscodingStreams will not issue more input data unless some number of bytes is read from input: a buffer is the only way to deal with this in a chain of codec streams
    output_buffer::CircularVector{UInt8} # 49151-byte history of uncompressed output data for historical lookups

    next_write::Int # location in output_buffer where next byte will be written
    next_read::Int # location in output_buffer where next byte will be exported to output memory stream

    state::DecompressionState # keep track of the current operation so it can be resumed after more input is available
    remaining_literals::Int # number of literals left to copy from the input memory
    remaining_copy::Int # number of historical bytes left to copy from output_buffer to output memory
    next_copy::Int # the next byte to copy from output_buffer history to output_buffer write head
    last_literals_copied::Int # number of literals copied in the last command (to properly interpret short history copy commands)

    LZO1X1DecompressorCodec() = new(
        Vector{UInt8}(),
        CircularVector(zeros(UInt8, LZO1X1_MAX_DISTANCE * 2)),
        1,
        1,
        AWAITING_FIRST_LITERAL,
        0,
        0,
        0,
        0,
    )
end

const LZODecompressor = LZO1X1DecompressorCodec
const LZODecompressorStream{S} = TranscodingStream{LZO1X1DecompressorCodec,S} where {S<:IO}
LZODecompressorStream(stream::IO, kwargs...) = TranscodingStream(LZODecompressor(), stream; kwargs...)

"""
    state(codec)::MatchingState

Return the state of the decompressor.

The state can be one of:
    - `AWAITING_FIRST_LITERAL`: The codec is looking for the end of the first literal copy command. Transitions to READING_LITERAL.
    - `AWAITING_COMMAND`: The codec is looking for the next command pair. Transitions to COPYING_HISTORY.
    - `COPYING_HISTORY`: The codec is copying a sequence of bytes from history in the output buffer to the write head of the output buffer, evicting bytes from the back of the output buffer to output memory. Transitions to FLUSHING.
    - `READING_LITERAL`: The codec is writing a literal sequence to the output buffer. Transitions to FLUSHING.
    - `FLUSHING`: The codec is flushing the output buffer to output memory. Transitions to AWAITING_COMMAND, COPYING_HISTORY, or READING_LITERAL, depending on if the output memory blocked during a sequence write.
    - `END_OF_STREAM`: The codec received the end-of-stream command. Any further input will result in an exception being thrown.
"""
state(codec::LZO1X1DecompressorCodec) = codec.state

function TranscodingStreams.expectedsize(codec::LZO1X1DecompressorCodec, input::Memory)
    # Usually around 2.4:1 compression ratio (see https://morotti.github.io/lzbench-web)
    return length(codec.output_buffer) + length(input) * 2
end

function TranscodingStreams.process(codec::LZO1X1DecompressorCodec, input::Memory, output::Memory, error::Error)

    input_length = length(input) % Int # length(::Memory) returns a UInt for whatever reason

    # An input length of zero signals EOF
    if input_length == 0 && isempty(codec.input_buffer)
        # If this is the middle of a command, something went wrong
        if state(codec) != END_OF_STREAM
            error[] = InputNotConsumedException()
            return 0, 0, :error
        end
        remaining = codec.next_write - codec.next_read
        to_copy = min(remaining, length(output) % Int)
        copyto!(output, 1, codec.output_buffer, codec.next_read, to_copy)
        if to_copy != remaining
            codec.next_read += to_copy
            return 0, to_copy, :ok
        else
            return 0, to_copy, :end
        end
    end

    # Any input after EOS is an error (for now)
    if state(codec) == END_OF_STREAM
        error[] = FormatException()
        return 0, 0, :error
    end

    # Copy everything to the internal buffer and process from there
    append!(codec.input_buffer, input)

    n_read = 0
    n_written = 0
    while n_read < length(codec.input_buffer) # this loop will break before the end of the input if a read or write is blocked

        if state(codec) == AWAITING_FIRST_LITERAL || state(codec) == AWAITING_COMMAND
            n_bytes, command = try
                decode(CommandPair, codec.input_buffer, n_read + 1; first_literal=state(codec)==AWAITING_FIRST_LITERAL, last_literal_length=codec.last_literals_copied)
            catch e
                error[] = e
                return input_length, n_written, :error
            end

            if n_bytes == 0
                break
            end

            if command == END_OF_STREAM_COMMAND
                codec.state = END_OF_STREAM
                n_read += n_bytes
                break
            end

            if command.lookback >= codec.next_write
                error[] = LookbehindOverrunException(n_read+1, codec.next_write - command.lookback, codec.input_buffer[n_read+1:n_read+n_bytes])
                return input_length, n_written, :error
            end

            n_read += n_bytes

            codec.remaining_literals = command.literal_length
            codec.remaining_copy = command.copy_length
            codec.next_copy = codec.next_write - command.lookback
            codec.last_literals_copied = command.literal_length

            codec.state = COPYING_HISTORY
        end

        if state(codec) == COPYING_HISTORY
            # maintain the lookback buffer while allowing room to write literals
            # in theory, we can always put this into the output buffer because the back LZO1X1_MAX_DISTANCE will have been flushed before we reached this point
            to_copy = min(codec.remaining_copy, LZO1X1_MAX_DISTANCE)

            # special gymnastics for history copies that overrun the write head of the output buffer
            while to_copy > 0
                chunk = min(codec.next_write - codec.next_copy, to_copy)
                copyto!(codec.output_buffer, codec.next_write, codec.output_buffer, codec.next_copy, chunk)
                to_copy -= chunk
                codec.next_write += chunk
                codec.next_copy += chunk
                codec.remaining_copy -= chunk
            end
            
            # always flush the buffer after copying a history chunk: use what is remaining to determine if more history needs to be copied
            codec.state = FLUSHING
        end

        if state(codec) == READING_LITERAL
            # in theory, we can always put this into the output buffer because the back LZO1X1_MAX_DISTANCE will have been flushed before we reach this point
            to_copy = min(codec.remaining_literals, length(codec.input_buffer) - n_read, LZO1X1_MAX_DISTANCE)

            copyto!(codec.output_buffer, codec.next_write, codec.input_buffer, n_read + 1, to_copy)
            codec.next_write += to_copy
            codec.remaining_literals -= to_copy
            n_read += to_copy

            # always flush the buffer after copying a literal chunk: use what is remaining to determine if more literals need to be copied
            codec.state = FLUSHING
        end

        if state(codec) == FLUSHING
            # only flush until LZO1X1_MAX_DISTANCE remains in the output buffer
            margin = codec.next_write - LZO1X1_MAX_DISTANCE - codec.next_read + 1
            if margin > 0
                to_copy = min(length(output) % Int - n_written, margin)
                copyto!(output, n_written + 1, codec.output_buffer, codec.next_read, to_copy)
                codec.next_read += to_copy
                n_written += to_copy
                if to_copy != margin
                    break
                end
            end

            if codec.remaining_copy > 0
                codec.state = COPYING_HISTORY
            elseif codec.remaining_literals > 0
                codec.state = READING_LITERAL
            else
                codec.state = AWAITING_COMMAND
            end
        end
    end

    trim_front!(codec.input_buffer, n_read)
    return input_length, n_written, :ok
end

function trim_front!(vec, n)
    new_length = length(vec) - n
    circshift!(vec, -n)
    return resize!(vec, new_length)
end