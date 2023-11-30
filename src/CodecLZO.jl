module CodecLZO

export
    LZO1X1CompressorCodec,
    LZOCompressorCodec,
    LZOCompressorStream,
    LZO1X1DecompressorCodec,
    LZODecompressorCodec,
    LZODecompressorStream

import TranscodingStreams:
    TranscodingStreams,
    TranscodingStream,
    Memory,
    Error

import CircularArrays:
    CircularVector

include("memory_management.jl")
include("hashmap.jl")
include("passthroughfifo.jl")
include("lzo1x1_stream_compression.jl")
include("lzo1x1_stream_decompression.jl")

end
