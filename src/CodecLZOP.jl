module CodecLZOP

export
    LZOPCompressorCodec,
    LZOPCompressor,
    LZOPCompressorStream,
    LZOPDecompressorCodec,
    LZOPDecompressor,
    LZOPDecompressorStream

using TranscodingStreams:
    TranscodingStream,
    Memory,
    Error

import CircularArrays:
    CircularVector

using LibLZO:
    max_compressed_length,
    unsafe_decompress!,
    unsafe_compress!,
    decompress,
    compress,
    unsafe_optimize!,
    LZO1X_1,
    AbstractLZOAlgorithm

using SimpleChecksums:
    adler32

using CRC:
    CRC_32, crc

using Dates

using InlineStrings:
    String255

@static if VERSION < v"1.7"
    include("compat.jl")
end

const _crc32 = crc(CRC_32)

include("errors.jl")
include("memory_management.jl")
include("lzop_filter.jl")
include("lzop_block.jl")

end
