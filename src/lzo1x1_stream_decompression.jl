# All LZO-1 streams encode data in the same way

@enum DecompressionState begin
    BEFORE_FIRST_LITERAL
    READING_RUN
    READING_DISTANCE
    READING_LITERAL
    IDLE
    END_OF_STREAM
end

abstract type AbstractLZODecompressorCodec <: TranscodingStreams.Codec end

struct InputNotConsumedException <: Exception end
struct FormatException <: Exception end

"""
    LZO1X1DecompressorCodec <: AbstractLZODecompressorCodec

A `TranscodingStreams.Codec` struct that decompresses data according to the 1X1 version of the LZO algorithm.

The LZO 1X1 algorithm is a Lempel-Ziv lossless compression algorithm. Compressed streams consist of alternating encoded instructions and sequences of literal values. The encoded instructions tell the decompressor to either:
1. copy a sequence of bytes of a particular length directly from the input to the output (literal copy), or
2. look back a certain distance in the already returned output and copy a sequence of bytes of a particular length from the output to the output again.

For implementation purposes, this decompressor uses a buffer of 49151 bytes to store output. This is equal to the maximum lookback distance of the LZO 1X1 algorithm.

The C implementation of LZO defined by liblzo2 requires that all decompressed information be available in working memory at once, and is therefore not adaptable to streaming as required by TranscodingStreams. The C library version claims to use no additional working memory, but it requires that a continuous space in memory be available to hold the entire output of the compressed data, the length of which is not knowable _a priori_ but can be larger than the compressed data by a factor of roughly 255. This implementation needs to keep 49151 bytes of output history in memory while decompressing, equal to the maximum lookback distance of the LZO 1x1 algorithm, and a small number of bytes to keep track of the command being processed in case the command is broken between multiple reads from the input memory.
"""
mutable struct LZO1X1DecompressorCodec <: AbstractLZODecompressorCodec
    output_buffer::PassThroughFIFO # 49151-byte history of uncompressed output data
    
    state::DecompressionState # The very first literal is encoded differently from the others

    command::UInt8 # To keep track of commands if they are broken between reads
    run_length::Int # The current run length being read, in case a length run is split between reads
    lookback_distance::UInt16 # The lookback distance being read, in case it is split between reads

    remaining_literals::Int # Storage for the literals left to copy: could be because it was smooshed into the last copy command or because the input ran out before all the literals needed were copied

    last_literals_copied::UInt8 # determines how to interpret commands 0 through 15

    LZO1X1DecompressorCodec() = new(
        PassThroughFIFO(LZO1X1_MAX_DISTANCE),
        BEFORE_FIRST_LITERAL,
        0 % UInt8,
        0,
        0 % UInt16,
        0,
        0 % UInt8,
    )
end

const LZODecompressorCodec = LZO1X1DecompressorCodec
const LZODecompressorStream{S} = TranscodingStream{LZO1X1DecompressorCodec,S}

function TranscodingStreams.minoutsize(codec::LZO1X1DecompressorCodec, input::Memory)
    # The worst-case scenario is a recursive history lookup, in which case some number of bytes are repeated as many times as the run length requests.
    # Assuming that some output already esists so that the history lookup succeeds...
    return length(codec.output_buffer) + (length(input) - 3) * 255
end

function TranscodingStreams.expectedsize(codec::LZO1X1DecompressorCodec, input::Memory)
    # Usually around 2.4:1 compression ratio with a minimum around 20 bytes (see https://morotti.github.io/lzbench-web)
    return min(length(codec.output_buffer) + length(input) * 3, 20)
end

function TranscodingStreams.startproc(codec::LZO1X1DecompressorCodec, mode::Symbol, error::Error)
    if mode != :read
        error[] = ErrorException("$(type(codec)) is read-only")
        return :error
    end
    return :ok
end

function TranscodingStreams.process(codec::LZO1X1DecompressorCodec, input::Memory, output::Memory, error::Error)

    input_length = length(input) % Int # length(::Memory) returns a UInt for whatever reason
    
    # An input length of zero signals EOF
    if input_length == 0
        # If this is the middle of a command, something went wrong
        if codec.state != END_OF_STREAM
            error[] = InputNotConsumedException()
            return 0, 0, :error
        end
        n_written = flush!(codec, output, 1)
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
            # First command is special
            r, status = consume_first_literal!(codec, input, n_read + 1, error)
            n_read += r
            if status != :ok
                return n_read, n_written, :error
            end
        end
        
        if codec.state == IDLE
            # Read the command
            r, status = consume_command!(codec, input, n_read + 1, error)
            n_read += r
            if status != :ok
                return n_read, n_written, :error
            end
        end

        if codec.state == READING_RUN
            # Store the run length
            r, status = consume_run!(codec, input, n_read + 1, error)
            n_read += r
            if status != :ok
                return n_read, n_written, :error
            end
        end

        if codec.state == READING_DISTANCE
            # Store the distance
            r, status = consume_distance!(codec, input, n_read + 1, error)
            n_read += r
            if status != :ok
                return n_read, n_written, :error
            end
        end

        # This is either a copy or a literal at this point. Assume copy first and deal with literals later.
        r, w, status = execute_copy!(codec, input, n_read + 1, output, n_written + 1, error)
        n_read += r
        n_written += w
        if status != :ok
            return n_read, n_written, :error
        end

        if codec.state == READING_LITERAL
            # Push back as many literals as allowed
            r, w = prepend!(codec.output_buffer, input, n_read + 1, output, n_written + 1, codec.remaining_literals)
            n_read += r
            n_written += w
            codec.remaining_literals -= r
            if codec.remaining_literals == 0
                codec.state = IDLE
            end
        end
        
    end

    # We are done
    return n_read, n_written, :ok

end

function TranscodingStreams.finalize(codec::LZO1X1DecompressorCodec)
    empty!(codec.output_buffer)
    return
end

function decompress_input!(codec::LZO1X1DecompressorCodec, input::Memory, input_start::Int, error::Error)

    n_read = 0
    len = length(input) - input_start + 1

    # The first literal is specially coded.
    if codec.first_literal
        first_byte = input[input_start]
        if first_byte >= 18
            # I don't think a copy of less than 4 literals as the first command is possible in LZO 1X1, but the option is included for completeness
            n = first_byte - 18
            if len < n + 1
                # can't read enough: request more bytes?
                return 0, :ok
            end
            n_read += 1
            if n >= 4
                copyto!(codec.output_buffer, codec.write_head, input, input_start + n_read, n)
                codec.write_head += n
                n_read += n
                codec.next_literal_length = 0x04
            else
                # deal with the literal copy in the loop
                codec.next_literal_length = n
            end
        elseif first_byte >= 16
            # A dictionary copy (16) is not valid at this location
            # The Linux kernel uses 17 as a flag to describe the version of the bitstream, but it is not otherwise valid
            error[] = FormatException()
            return 0, :error
        end
        codec.first_literal = false
    end

    while n_read < len
        if 0 < codec.next_literal_length < 4
            # copy literals
            n_to_copy = min(codec.next_literal_length, len - n_read)
            copyto!(codec.output_buffer, codec.write_head, input, input_start + n_read, n_to_copy)
            codec.write_head += n_to_copy
            n_read += n_to_copy
            codec.next_literal_length = 4
            continue
        end

        command = input[input_start + n_read]

        if (command & 0b10000000) != 0
            if n_read + 1 >= len
                # need another byte
                return n_read, :ok
            end
            n_to_copy = 5 + ((command >> 5) & 0b00000011)
            distance = 1 + (input[input_start + n_read + 1] << 3) + (command >> 2) & 0b00000111
            codec.next_literal_length = command & 0b00000011
            
            r, status = copy_history!(codec.output_buffer, distance, n_to_copy)
            n_read += r
            
        elseif (command & 0b01000000) != 0
        elseif (command & 0b00100000) != 0
        elseif (command & 0b00010000) != 0
        else
        end
    end

    return n_read, :ok

end