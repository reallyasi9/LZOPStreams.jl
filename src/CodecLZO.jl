module CodecLZO

export
    LZO1X1CompressorCodec,
    LZOCompressor,
    LZOCompressorStream,
    LZO1X1DecompressorCodec,
    LZODecompressor,
    LZODecompressorStream

import TranscodingStreams:
    TranscodingStreams,
    TranscodingStream,
    Memory,
    Error

import CircularArrays:
    CircularVector

import LibLZO

@static if VERSION < v"1.7"
    include("compat.jl")
end

include("errors.jl")
include("memory_management.jl")
include("hashmap.jl")
include("commands.jl")
include("lzo1x1.jl")
include("lzo1x1_stream_compression.jl")
include("lzo1x1_stream_decompression.jl")

end
