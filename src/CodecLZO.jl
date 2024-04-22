module CodecLZO

export
    LZO1X1CompressorCodec,
    LZOCompressor,
    LZOCompressorStream,
    LZO1X1DecompressorCodec,
    LZODecompressor,
    LZODecompressorStream,
    LZO1X1FastCompressorCodec,
    LZOFastCompressor,
    LZOFastCompressorStream,
    LZO1X1FastDecompressorCodec,
    LZOFastDecompressor,
    LZOFastDecompressorStream

import TranscodingStreams:
    TranscodingStreams,
    TranscodingStream,
    Memory,
    Error

import CircularArrays:
    CircularVector

import LibLZO:
    max_compressed_length,
    unsafe_decompress!,
    unsafe_compress!,
    decompress,
    compress,
    unsafe_optimize!,
    LZO1X_1,
    AbstractLZOAlgorithm

import SimpleChecksums:
    adler32

import CRC:
    CRC_32, crc

@static if VERSION < v"1.7"
    include("compat.jl")
end

const _crc32 = crc(CRC_32)

include("errors.jl")
include("memory_management.jl")
include("lzop_filter.jl")
include("lzop_block.jl")
include("hashmap.jl")
include("commands.jl")
include("lzo1x1.jl")
include("lzo1x1_stream_compression.jl")
include("lzo1x1_stream_decompression.jl")
include("lzo1x1_fast_compression.jl")
include("lzo1x1_fast_decompression.jl")

end
