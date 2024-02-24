const ADLER32_D=0x00000001
const ADLER32_C=0x00000002
const STDIN=0x00000004
const STDOUT=0x00000008
const NAME_DEFAULT=0x00000010
const DOSISH=0x00000020
const H_EXTRA_FIELD=0x00000040
const H_GMTDIFF=0x00000080
const CRC32_D=0x00000100
const CRC32_C=0x00000200
const MULTIPART=0x00000400
const H_FILTER=0x00000800
const H_CRC32=0x00001000
const H_PATH=0x00002000

struct LZOPBlockHeader
    uncompressed_length::UInt32
    compressed_length::UInt32
    adler32_uncompressed::UInt32
    crc32_uncompressed::UInt32
    adler32_compressed::UInt32
    crc32_compressed::UInt32

    options::UInt32
    no_compression::Bool
    eos::Bool
end

function LZOPBlockHeader(uncompressed_data, compressed_data; options::UInt32=0x00000000)
    uncompressed_length = length(uncompressed_data) % UInt32

    # final block has length of 0 and signals end of stream
    if uncompressed_length == 0
        return LZOPBlockHeader(0, 0, 0, 0, 0, 0, options, true, true)
    end

    compressed_length = length(compressed_data) % UInt32

    # if compressing does not help, write out the uncompressed data instead
    # these two values being equal is a switch for other writes that follow
    no_compression = compressed_length >= uncompressed_length
    if no_compression
        compressed_length = uncompressed_length
    end

    # uncompressed checksum(s) (optional)
    adler32_uncompressed = 0x00000001
    if (options & ADLER32_D) != 0
        # Note: the initial value for Adler32 is 1, not 0 as defined in Libz.jl
        adler32_uncompressed = adler32(0x00000001, pointer(uncompressed_data), uncompressed_length)
    end
    crc32_uncompressed = 0x00000000
    if (options & CRC32_D) != 0
        crc32_uncompressed = crc32(0x00000000, pointer(uncompressed_data), uncompressed_length)
    end

    adler32_compressed = 0x00000001
    crc32_compressed = 0x00000000
    if !no_compression
        # compressed checksum(s) (optional, and only if compression helped)
        if (options & ADLER32_C) != 0
            # Note: the initial value for Adler32 is 1, not 0 as defined in Libz.jl
            adler32_compressed = adler32(0x00000001, pointer(compressed_data), compressed_length)
        end
        if (options & CRC32_C) != 0
            crc32_compressed = crc32(0x00000000, pointer(compressed_data), compressed_length)
        end
    end

    return LZOPBlockHeader(uncompressed_length, compressed_length, adler32_uncompressed, crc32_uncompressed, adler32_compressed, crc32_compressed, options, no_compression, false)
end

function unsafe_encode_net!(output, value::Integer, i::Integer=0)
    b = sizeof(value)
    while b > 0
        unsafe_store!(pointer(output), (value & 0xff) % UInt8, i+b-1)
        value >>= 8
        b -= 1
    end
    return sizeof(value)
end

function Base.sizeof(h::LZOPBlockHeader)
    bytes = 4
    h.eos && return bytes

    bytes += 4
    if (h.options & ADLER32_D) != 0
        bytes += 4
    end
    if (h.options & CRC32_D) != 0
        bytes += 4
    end

    if !h.no_compression
        if (h.options & ADLER32_C) != 0
            bytes += 4
        end
    
        if (h.options & CRC32_C) != 0
            bytes += 4
        end
    end

    return bytes
end

function unsafe_encode!(output, h::LZOPBlockHeader)
    w = 0

    # uncompressed length
    w += unsafe_encode_net!(output, h.uncompressed_length, w+1)

    # final block has length of 0 and signals end of stream
    h.eos && return w

    w += unsafe_encode_net!(output, h.compressed_length, w+1)

    # uncompressed checksum(s) (optional)
    if (h.options & ADLER32_D) != 0
        # Note: the initial value for Adler32 is 1, not 0 as defined in Libz.jl
        w += unsafe_encode_net!(output, h.adler32_uncompressed, w+1)
    end
    if (h.options & CRC32_D) != 0
        w += unsafe_encode_net!(output, h.crc32_uncompressed, w+1)
    end

    if !h.no_compression
        # compressed checksum(s) (optional, and only if compression helped)
        if (h.options & ADLER32_C) != 0
            # Note: the initial value for Adler32 is 1, not 0 as defined in Libz.jl
            w += unsafe_encode_net!(output, h.adler32_compressed, w+1)
        end
        if (h.options & CRC32_C) != 0
            w += unsafe_encode_net!(output, h.crc32_compressed, w+1)
        end
    end

    # compressed or uncompressed data follows, depending on if compressed_length < uncompressed_length comparison

    return w
end