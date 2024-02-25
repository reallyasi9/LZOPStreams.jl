const BLOCK_SIZE = 256*1024
const MAX_BLOCK_SIZE = 64*1024*1024

function encode_net!(output, value::Integer, i::Integer=0)
    b = sizeof(value)
    length(output) < b && return 0
    while b > 0
        unsafe_store!(pointer(output), (value & 0xff) % UInt8, i+b-1)
        value >>= 8
        b -= 1
    end
    return sizeof(value)
end

function compress_block!(algo::AbstractLZOAlgorithm, output, input::AbstractVector{UInt8}; crc32::Bool=false, filter::FilterType=NO_FILTER)
    length(input) > MAX_BLOCK_SIZE && throw(ArgumentError("unable to encode input block of size $(length(input)) > $MAX_BLOCK_SIZE"))
    
    bytes_written = 0

    # uncompressed length
    w = encode_net!(output, length(input) % UInt32, bytes_written+1)
    w == 0 && return 0
    bytes_written += w

    # final block has length of 0 and signals end of stream
    length(input) == 0 && return bytes_written

    # uncompressed checksum
    checksum = crc32 ? Libz.crc32(input) : Libz.adler32(input)
    
    # compressed length
    filter!(input, filter)
    compressed = compress(algo, input)
    # LZOP always optimizes, which doubles the compression time for little gain (TODO: revisit this decision)
    unsafe_optimize!(algo, input, compressed)

    compressed_length = min(length(input), length(compressed))
    # will it fit?
    if length(output) - bytes_written < compressed_length + 16
        return 0
    end
    # everything else is guaranteed to fit

    use_compressed = compressed_length == length(compressed)
    bytes_written += encode_net!(output, compressed_length % UInt32, bytes_written+1)
    bytes_written += encode_net!(output, checksum, bytes_written+1)

    # compressed checksum is only output if compression is used
    if use_compressed
        checksum = crc32 ? Libz.crc32(compressed) : Libz.adler32(compressed)
        bytes_written += encode_net!(output, checksum, bytes_written+1)
        bytes_written += unsafe_copyto!(output, bytes_written+1, compressed, 1, compressed_length)
    else
        bytes_written += unsafe_copyto!(output, bytes_written+1, input, 1, compressed_length)
    end

    return bytes_written
end
