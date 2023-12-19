# All LZO-1 streams encode data in the same way

@enum DecompressionState begin
    BEFORE_FIRST_LITERAL
    AWAITING_COMMAND
    READING_LITERAL
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
    input_buffer::Vector{UInt8} # The codec must consume all the input from an input stream before the end-of-stream signal is sent, so input must be buffered
    output_buffer::PassThroughFIFO # 49151-byte history of uncompressed output data
    
    state::DecompressionState # The very first literal is encoded differently from the others

    remaining_literals::Int # Storage for the literals left to copy: could be because it was smooshed into the last copy command or because the input ran out before all the literals needed were copied

    last_literals_copied::UInt8 # determines how to interpret commands 0 through 15

    LZO1X1DecompressorCodec() = new(
        Vector{UInt8}(),
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
    empty!(codec.input_buffer)
    empty!(codec.output_buffer)
    return
end

function TranscodingStreams.minoutsize(codec::LZO1X1DecompressorCodec, input::Memory)
    # The worst-case scenario is a recursive history lookup, in which case some number of bytes are repeated as many times as the run length requests.
    # Assuming that some output already esists so that the history lookup succeeds...
    l = length(codec.output_buffer)
    li = length(input) + length(codec.input_buffer)
    if li >= 3
        l += (li - 3) * 255
    end
    return l
end

function TranscodingStreams.expectedsize(codec::LZO1X1DecompressorCodec, input::Memory)
    # Usually around 2.4:1 compression ratio (see https://morotti.github.io/lzbench-web)
    return length(codec.output_buffer) + (length(input) + length(codec.input_buffer)) * 3
end

function TranscodingStreams.startproc(codec::LZO1X1DecompressorCodec, ::Symbol, ::Error)
    empty!(codec.input_buffer)
    empty!(codec.output_buffer) # this costs almost nothing
    codec.state = BEFORE_FIRST_LITERAL
    codec.remaining_literals = 0
    codec.last_literals_copied = 0
    return :ok
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
    append!(codec.input_buffer, input)
    read_idx = 0
    n_written = 0
    while read_idx < input_length

        if codec.state == BEFORE_FIRST_LITERAL
            if read_idx != 0
                error[] = FormatException()
                return 0, 0, :error
            end
            # First command is special
            if codec.input_buffer[read_idx + 1] == 16 # history copy command
                error[] = FormatException()
                return 0, 0, :error
            end

            literal_command = decypher_literal(codec.input_buffer, 1)
            if literal_command == NULL_LITERAL_COMMAND
                # need more input to know what to do!
                return 0, 0, :ok
            end

            read_idx += literal_command.command_length
            codec.last_literals_copied = min(literal_command.copy_length, 4)
            
            r, w = prepend!(codec.output_buffer, codec.input_buffer, read_idx + 1, output, n_written + 1, literal_command.copy_length)
            read_idx += r
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
            r, w = prepend!(codec.output_buffer, codec.input_buffer, read_idx + 1, output, n_written + 1, codec.remaining_literals)
            read_idx += r
            n_written += w
            codec.remaining_literals -= r
            if codec.remaining_literals == 0
                codec.state = AWAITING_COMMAND
            else
                break # don't keep looping: return and ask for more input
            end
        end

        if codec.state == AWAITING_COMMAND && read_idx < input_length
            
            # peek at the command
            command = codec.input_buffer[read_idx + 1]

            if command < 0b00010000 && codec.last_literals_copied == 0
                literal_command = decypher_literal(codec.input_buffer, read_idx + 1)
                if literal_command == NULL_LITERAL_COMMAND
                    break # don't keep looping: return and ask for more input
                end

                read_idx += literal_command.command_length
                codec.last_literals_copied = min(literal_command.copy_length, 4)

                r, w = prepend!(codec.output_buffer, codec.input_buffer, read_idx + 1, output, n_written + 1, literal_command.copy_length)
                read_idx += r
                n_written += w

                if r < literal_command.copy_length
                    codec.remaining_literals = literal_command.copy_length - r
                    codec.state = READING_LITERAL
                    break # don't keep looping: return and ask for more input
                end
                
                codec.state = AWAITING_COMMAND
            else
                copy_command = decypher_copy(codec.input_buffer, read_idx + 1, codec.last_literals_copied)
                if copy_command == NULL_HISTORY_COMMAND
                    break # don't keep looping: return and ask for more input
                end
                
                read_idx += copy_command.command_length
                
                if copy_command == END_OF_STREAM_COMMAND
                    codec.state = END_OF_STREAM
                    break # flush happens when empty input is passed by TranscodingStreams
                end
                if copy_command.lookback > codec.output_buffer.write_head-1
                    error[] = FormatException()
                    return input_length, n_written, :error
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

    # make sure to remove the input buffer we used before the next call starts
    splice!(codec.input_buffer, 1:read_idx)
    return input_length, n_written, :ok
end

function TranscodingStreams.finalize(codec::LZO1X1DecompressorCodec)
    empty!(codec.output_buffer)
    return
end
