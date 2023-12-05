# All LZO-1 streams encode data in the same way

@enum DecompressionState begin
    BEFORE_FIRST_LITERAL
    AWAITING_COMMAND
    READING_LITERAL
    END_OF_STREAM
end

struct LiteralCopyCommand
    command_length::Int
    copy_length::Int
end

struct HistoryCopyCommand
    command_length::Int
    lookback::Int
    copy_length::Int
    post_copy_literals::UInt8
end

const NULL_LITERAL_COMMAND = LiteralCopyCommand(0, 0)
const NULL_HISTORY_COMMAND = HistoryCopyCommand(0, 0, 0, 0)
const END_OF_STREAM_COMMAND = HistoryCopyCommand(3, 16384, 3, 0) # Corresponds to byte sequence 0x11 0x00 0x00

struct InputNotConsumedException <: Exception end
struct FormatException <: Exception end

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
    output_buffer::PassThroughFIFO # 49151-byte history of uncompressed output data
    
    state::DecompressionState # The very first literal is encoded differently from the others

    remaining_literals::Int # Storage for the literals left to copy: could be because it was smooshed into the last copy command or because the input ran out before all the literals needed were copied

    last_literals_copied::UInt8 # determines how to interpret commands 0 through 15

    LZO1X1DecompressorCodec() = new(
        PassThroughFIFO(LZO1X1_MAX_DISTANCE),
        BEFORE_FIRST_LITERAL,
        0,
        0 % UInt8,
    )
end

const LZODecompressorCodec = LZO1X1DecompressorCodec
const LZODecompressorStream{S} = TranscodingStream{LZO1X1DecompressorCodec,S} where S<:IO
LZODecompressorStream(stream::IO, kwargs...) = TranscodingStream(LZODecompressorCodec(), stream; kwargs...)

function TranscodingStreams.initialize(codec::LZO1X1DecompressorCodec)
    empty!(codec.output_buffer)
    return
end

function TranscodingStreams.minoutsize(codec::LZO1X1DecompressorCodec, input::Memory)
    # The worst-case scenario is a recursive history lookup, in which case some number of bytes are repeated as many times as the run length requests.
    # Assuming that some output already esists so that the history lookup succeeds...
    l = length(codec.output_buffer)
    if length(input) >= 3
        l += (length(input) - 3) * 255
    end
    return l
end

function TranscodingStreams.expectedsize(codec::LZO1X1DecompressorCodec, input::Memory)
    # Usually around 2.4:1 compression ratio with a minimum around 20 bytes (see https://morotti.github.io/lzbench-web)
    return min(length(codec.output_buffer) + length(input) * 3, 20)
end

function TranscodingStreams.startproc(codec::LZO1X1DecompressorCodec, ::Symbol, ::Error)
    empty!(codec.output_buffer) # this costs almost nothing
    codec.state = BEFORE_FIRST_LITERAL
    codec.remaining_literals = 0
    codec.last_literals_copied = 0
    return :ok
end

function decode_run_length(input::Memory, start_index::Int, bits::Int)
    mask = ((1 << bits) - 1) % UInt8
    byte = input[start_index] & mask
    len = byte % Int
    if len != 0
        return 1, len
    end

    input_length = length(input)
    if start_index == input_length
        return 0, 0
    end

    bytes = 1
    byte = input[start_index + bytes]
    while byte == 0 && start_index + bytes < input_length
        len += 255
        bytes += 1
        byte = input[start_index + bytes]
    end

    if byte == 0
        return 0, 0
    end

    return bytes + 1, len + byte + mask
end

function decypher_copy(input::Memory, start_index::Int, last_literals_copied::UInt8)
    remaining_bytes = length(input) - start_index + 1
    command = input[start_index]

    # 2-byte commands first
    if remaining_bytes < 2
        return NULL_HISTORY_COMMAND
    elseif command < 0b00010000
        after = command & 0b00000011
        if last_literals_copied > 0 && last_literals_copied < 4
            len = 2
            dist = ((input[start_index + 1] % Int) << 2) + ((command & 0b00001100) >> 2) + 1
        else
            len = 3
            dist = ((input[start_index + 1] % Int) << 2) + ((command & 0b00001100) >> 2) + 2049
        end
        return HistoryCopyCommand(2, dist, len, after)
    elseif (command & 0b11000000) != 0
        after = command & 0b00000011
        if command < 0b10000000
            len = 3 + ((command & 0b00100000) >> 5)
            dist = ((input[start_index + 1] % Int) << 3) + ((command & 0b00011100) >> 2) + 1
        else
            len = 5 + ((command & 0b01100000) >> 5)
            dist = ((input[start_index + 1] % Int) << 3) + ((command & 0b00011100) >> 2) + 1
        end
        return HistoryCopyCommand(2, dist, len, after)
    elseif command < 0b00100000
        # variable-width length encoding
        msb = ((command & 0b00001000) % Int) << 11
        bytes, len = decode_run_length(input, start_index, 3)
        if bytes == 0 || remaining_bytes < bytes + 2
            return NULL_HISTORY_COMMAND
        end
        dist = 16384 + msb + ((input[start_index + bytes + 1] % Int) << 6) + ((input[start_index + bytes] % Int) >> 2)
        after = input[start_index + bytes] & 0b00000011
        return HistoryCopyCommand(bytes + 2, dist, len + 2, after)
    else
        # variable-width length encoding
        bytes, len = decode_run_length(input, start_index, 5)
        if bytes == 0 || remaining_bytes < bytes + 2
            return NULL_HISTORY_COMMAND
        end
        dist = 1 + ((input[start_index + bytes + 1] % Int) << 6) + ((input[start_index + bytes] % Int) >> 2)
        after = input[start_index + bytes] & 0b00000011
        return HistoryCopyCommand(bytes + 2, dist, len + 2, after)
    end
end

function decypher_literal(input::Memory, start_index::Int)
    command = input[start_index]
    if command < 0b00010000
        bytes, len = decode_run_length(input, start_index, 4)
        if bytes == 0
            return NULL_LITERAL_COMMAND
        end
        return LiteralCopyCommand(bytes, len + 3)
    else
        return LiteralCopyCommand(1, command - 17)
    end
end

function TranscodingStreams.process(codec::LZO1X1DecompressorCodec, input::Memory, output::Memory, error::Error)

    input_length = length(input) # length(::Memory) returns a UInt for whatever reason
    
    # An input length of zero signals EOF
    if input_length == 0
        # If this is the middle of a command, something went wrong
        if codec.state != END_OF_STREAM
            error[] = InputNotConsumedException()
            return 0, 0, :error
        end
        n_written = flush!(codec.output_buffer, output, 1)
        return 0, n_written, :end
    end

    # Any input after EOS is an error (for now)
    if codec.state == END_OF_STREAM
        error[] = FormatException()
        return 0, 0, :error
    end

    # Everything else is decompressed into the buffer then emitted
    n_read = 0
    n_written = 0
    while n_read < input_length

        if codec.state == BEFORE_FIRST_LITERAL
            if n_read != 0
                error[] = FormatException()
                return 0, 0, :error
            end
            # First command is special
            if input[n_read + 1] == 16 # history copy command
                error[] = FormatException()
                return 0, 0, :error
            end

            literal_command = decypher_literal(input, 1)
            if literal_command == NULL_LITERAL_COMMAND
                # need more input to know what to do!
                return 0, 0, :ok
            end

            n_read += literal_command.command_length
            codec.last_literals_copied = min(literal_command.copy_length, 4)
            
            r, w = prepend!(codec.output_buffer, input, n_read + 1, output, n_written + 1, literal_command.copy_length)
            n_read += r
            n_written += w

            if r < literal_command.copy_length
                codec.remaining_literals = literal_command.copy_length - r
                codec.state = READING_LITERAL
                break # don't keep looping: return and ask for more input
            end

            codec.state = AWAITING_COMMAND
        end

        if codec.state == READING_LITERAL
            # Push back as many literals as allowed
            r, w = prepend!(codec.output_buffer, input, n_read + 1, output, n_written + 1, codec.remaining_literals)
            n_read += r
            n_written += w
            codec.remaining_literals -= r
            if codec.remaining_literals == 0
                codec.state = AWAITING_COMMAND
            else
                break # don't keep looping: return and ask for more input
            end
        end

        if codec.state == AWAITING_COMMAND && n_read < input_length
            
            # peek at the command
            command = input[n_read + 1]

            if command < 0b00010000 && codec.last_literals_copied == 0
                literal_command = decypher_literal(input, n_read + 1)
                if literal_command == NULL_LITERAL_COMMAND
                    break # don't keep looping: return and ask for more input
                end

                n_read += literal_command.command_length
                codec.last_literals_copied = min(literal_command.copy_length, 4)

                r, w = prepend!(codec.output_buffer, input, n_read + 1, output, n_written + 1, literal_command.copy_length)
                n_read += r
                n_written += w

                if r < literal_command.copy_length
                    codec.remaining_literals = literal_command.copy_length - r
                    codec.state = READING_LITERAL
                    break # don't keep looping: return and ask for more input
                end
                
                codec.state = AWAITING_COMMAND
            else
                copy_command = decypher_copy(input, n_read + 1, codec.last_literals_copied)
                if copy_command == NULL_HISTORY_COMMAND
                    break # don't keep looping: return and ask for more input
                end
                
                n_read += copy_command.command_length
                
                if copy_command == END_OF_STREAM_COMMAND
                    codec.state = END_OF_STREAM
                    break # flush happens when empty input is passed by TranscodingStreams
                end
                if copy_command.lookback > codec.output_buffer.write_head-1
                    error[] = FormatException()
                    return n_read, n_written, :error
                end
                
                # execute copy manually, byte by byte, to account for potential looping of the output buffer
                # which happens when the number of bytes to copy is greater than the lookback distance
                n_written += self_copy_and_output!(codec.output_buffer, copy_command.lookback, output, n_written, copy_command.copy_length)

                codec.remaining_literals = copy_command.post_copy_literals
                codec.last_literals_copied = codec.remaining_literals
                if codec.remaining_literals != 0
                    codec.state = READING_LITERAL
                else
                    codec.state = AWAITING_COMMAND
                end
            end
        end 
    end

    return n_read, n_written, :ok
end

function TranscodingStreams.finalize(codec::LZO1X1DecompressorCodec)
    empty!(codec.output_buffer)
    return
end
