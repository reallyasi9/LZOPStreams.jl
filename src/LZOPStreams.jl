module LZOPStreams

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

using FlagSets

using BufferedStreams
using StringEncodings

@static if VERSION < v"1.9"
    include("compat.jl")
end

const LZO_LIB_VERSION = UInt16(version())
const LZOP_VERSION = 0x1300
const LZOP_MIN_VERSION = 0x0900

include("lzop_filter.jl")
include("lzop_header.jl")
include("lzop_block.jl")
include("lzop_file.jl")

end
