module CodecLZOP

using LibLZO:
    max_compressed_length,
    unsafe_decompress!,
    unsafe_compress!,
    decompress,
    compress,
    unsafe_optimize!,
    LZO1X_1,
    LZO1X_1_15,
    LZO1X_999,
    AbstractLZOAlgorithm,
    version

using SimpleChecksums:
    adler32

using CRC32:
    crc32

using Dates

using InlineStrings:
    String255

using FlagSets

@static if VERSION < v"1.7"
    include("compat.jl")
end

const LZO_LIB_VERSION = version()
const LZO_LIB_VERSION_NUMBER = VersionNumber(LZO_LIB_VERSION >> 12, (LZO_LIB_VERSION >> 8) & 0xf, (LZO_LIB_VERSION >> 4) & 0xf, (LZO_LIB_VERSION & 0xf,))
const LZOP_VERSION_NUMBER = VersionNumber(1, 3, 0, (0,))
const LZOP_MIN_VERSION_NUMBER = VersionNumber(0, 9, 0, (0,))

include("lzop_filter.jl")
include("lzop_header.jl")
include("lzop_block.jl")
include("lzop_file.jl")

end
