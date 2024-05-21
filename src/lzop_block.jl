const BLOCK_SIZE = 256 * 1024
const LZOP_MAX_BLOCK_SIZE = 64 * 1024 * 1024

"""
    compress_block(input, output, algo; [kwargs...])::Tuple{Int,Int}

    Compress a block of data from `input` to `output` using LZO algorithm `algo`, returning the number of bytes read from `input` and written to `output`.

# Arguments
- `input`: An `AbstractVector{UInt8}` or `IO` object containing the block of data to compress. Only the first `LZOP_MAX_BLOCK_SIZE` bytes will be read.
- `output::IO`: Output IO object to write the compressed block.

# Keyword arguments
- 'crc32::Bool = false`: If `true`, write a CRC-32 checksum for both uncompressed and compressed data. If `false`, write Adler32 checksums instead.
- `filter::AbstractLZOPFilter = NO_FILTER`: Transform the input data using the specified LZOP filter. These filters are documented in the `FilterType` enum. The effect on the compression efficiency is minimal in most cases, so use of them is discouraged.
- `optimize::Bool = false`: If `true`, process the data twice to optimize how it is stored for faster decompression. Setting this to `true` doubles compression time with little to no improvement in decompression time, so its use is not recommended.
"""
function compress_block(invec::AbstractVector{UInt8}, output::IO, algo::AbstractLZOAlgorithm; crc32::Bool=false, filter::AbstractLZOPFilter=NoopFilter(), optimize::Bool=false)
    bytes_read = min(length(invec), LZOP_MAX_BLOCK_SIZE) % Int

    bytes_written = zero(Int)

    # uncompressed length
    bytes_written += write(output, hton(bytes_read % UInt32))

    # final block has length of 0 and signals end of stream
    bytes_read == 0 && return bytes_read, bytes_written

    # Use a view into the data from here on out, making sure to accomodate for things like OffsetArrays
    input = @view invec[begin:begin+bytes_read-1]

    # uncompressed checksum
    checksum = crc32 ? _crc32(input) : adler32(input)

    # compressed length
    lzop_filter!(filter, input)
    compressed = compress(algo, input)
    compressed_length = min(bytes_read, length(compressed)) % UInt32

    bytes_written += write(output, hton(compressed_length))
    bytes_written += write(output, hton(checksum))

    # optimize only if using compressed data
    use_compressed = length(compressed) < bytes_read
    if optimize && use_compressed
        original_length = unsafe_optimize!(algo, input, compressed)
        if original_length != bytes_read
            throw(ErrorException("LZO optimization failed"))
        end
    end

    # compressed checksum is only output if compression is used
    if use_compressed
        checksum = crc32 ? _crc32(compressed) : adler32(compressed)
        bytes_written += write(output, hton(checksum))
        bytes_written += write(output, compressed)
    else
        bytes_written += write(output, input)
    end

    return bytes_read, bytes_written
end

# Extract data to a Vector if the input is a generic IO object.
function compress_block(io::IO, output::IO, algo::AbstractLZOAlgorithm; kwargs...)
    input = Vector{UInt8}()
    readbytes!(io, input, LZOP_MAX_BLOCK_SIZE)
    return compress_block(input, output, algo; kwargs...)
end

# Avoid the extra copy and use the buffer directly if the input is already an IOBuffer object.
function compress_block(io::IOBuffer, output::IO, algo::AbstractLZOAlgorithm; kwargs...)
    last_byte = min(io.size - io.ptr + 1, LZOP_MAX_BLOCK_SIZE)
    input = @view io.data[io.ptr:last_byte]
    return compress_block(input, output, algo; kwargs...)
end

compress_block(input::AbstractString, output::IO, algo::AbstractLZOAlgorithm; kwargs...) = compress_block(codeunits(input), output, algo; kwargs...)


"""
    decompress_block(input, output, algo; [kwargs...])::Tuple{Int,Int}

    Decompress a block of data from `input` to `output` using LZO algorithm `algo`, returning the number of bytes read from `input` and written to `output`.

# Arguments
- `input`: An `AbstractVector{UInt8}` or `IO` object containing the block of LZO-compressed data to decompress.
- `output::IO`: Output IO object to write the decompressed block.

# Keyword arguments
- 'crc32::Bool = false`: If `true`, assume the checksum written to the block for both uncompressed and compressed data is a CRC-32 checksum. If `false`, assume Adler32 checksums instead.
- `filter::AbstractLZOPFilter = NO_FILTER`: Untransform the output data using the specified LZOP filter. These filters are documented in the `FilterType` enum. The effect on the compression efficiency is minimal in most cases, so use of them is discouraged.
- `on_checksum_fail::Symbol = :error`: Choose how the function responds to invalud checksums. If `:error`, and `ErrorException` will be thrown. If `:warn`, a warning will be printed. If `:ignore`, the checksum values will be completely ignored.
"""
function decompress_block(input::IO, output::IO, algo::AbstractLZOAlgorithm; crc32::Bool=false, filter::AbstractLZOPFilter=NoopFilter(), on_checksum_fail::Symbol=:error)
    on_checksum_fail ∉ (:error, :warn, :ignore) && throw(ArgumentError("on_checksum_fail must be one of :error, :warn, or :ignore (got $on_checksum_fail)"))

    # uncompressed length
    uncompressed_length = ntoh(read(input, UInt32))
    bytes_read = 4

    # abort if uncompressed length is zero
    uncompressed_length == 0 && return bytes_read, 0

    # error if uncompressed length is too long, irrespective of checksum fail flag
    uncompressed_length > LZOP_MAX_BLOCK_SIZE && throw(ErrorException("invalid LZOP block: uncompressed length greater than max block size ($uncompressed_length > $LZOP_MAX_BLOCK_SIZE)"))

    # compressed length
    compressed_length = ntoh(read(input, UInt32))
    bytes_read += 4

    # error if larter than uncompressed length, irrespective of checksum fail flag
    compressed_length > uncompressed_length && throw(ErrorException("invalid LZOP block: uncompressed length less than compressed length ($uncompressed_length < $compressed_length)"))

    uncompressed_checksum = ntoh(read(input, UInt32))
    bytes_read += 4

    # use raw data if compressed and uncompressed lengths are the same, else decompress
    if compressed_length != uncompressed_length
        compressed_checksum = ntoh(read(input, UInt32))
        bytes_read += 4
    else
        compressed_checksum = uncompressed_checksum
    end

    raw_data = Vector{UInt8}(undef, compressed_length)
    readbytes!(input, raw_data, compressed_length)
    bytes_read += compressed_length

    if compressed_length != uncompressed_length
        if on_checksum_fail != :ignore
            checksum = crc32 ? _crc32(raw_data) : adler32(raw_data)
            if checksum != compressed_checksum
                on_checksum_fail == :error && throw(ErrorException("invalid LZOP block: compressed checksum recorded in block does not equal computed checksum with crc32=$crc32 ($compressed_checksum != $checksum)"))
                if on_checksum_fail == :warn
                    @warn "invalid LZOP block: compressed checksum recorded in block does not equal computed checksum" crc32 recorded_checksum = compressed_checksum computed_checksum = checksum
                end
            end
        end

        uncompressed_data = Vector{UInt8}(undef, uncompressed_length)
        decompressed_length = unsafe_decompress!(algo, uncompressed_data, raw_data)
        decompressed_length != uncompressed_length && throw(ErrorException("invalid LZOP block: uncompressed length recorded in block does not equal length of decompressed data reported by LZO algorithm: ($uncompressed_length != $decompressed_length)"))
    else
        uncompressed_data = raw_data
    end

    # in-place unfilter of data before the checksum
    lzop_unfilter!(filter, uncompressed_data)

    # only perform final checksum if flag not set to ignore and the data is compressed
    if on_checksum_fail != :ignore
        checksum = crc32 ? _crc32(uncompressed_data) : adler32(uncompressed_data)
        if checksum != uncompressed_checksum
            on_checksum_fail == :error && throw(ErrorException("invalid LZOP block: uncompressed checksum recorded in block does not equal computed checksum with crc32=$crc32 ($uncompressed_checksum != $checksum)"))
            if on_checksum_fail == :warn
                @warn "invalid LZOP block: uncompressed checksum recorded in block does not equal computed checksum" crc32 recorded_checksum = uncompressed_checksum computed_checksum = checksum
            end
        end
    end

    bytes_written = write(output, uncompressed_data)

    return bytes_read, bytes_written
end

# Wrap data in an IOBuffer if input is a Vector of bytes
function decompress_block(input::AbstractVector{UInt8}, output::IO, algo::AbstractLZOAlgorithm; kwargs...)
    io = IOBuffer(input)
    return decompress_block(io, output, algo; kwargs...)
end
