module CodecLZO

export
    LZO1X1CompressorCodec,
    LZOCompressorCodec,
    LZOCompressorStream,
    LZO1X1DecompressorCodec,
    LZODecompressorCodec,
    LZODecompressorStream,
    LZO1X1FastCompressorCodec,
    LZOFastCompressorCodec,
    LZOFastCompressorStream,
    LZO1X1FastDecompressorCodec,
    LZOFastDecompressorCodec,
    LZOFastDecompressorStream

import TranscodingStreams:
    TranscodingStreams,
    TranscodingStream,
    Memory,
    Error

import CircularArrays:
    CircularVector

using LZO_jll

include("memory_management.jl")
include("hashmap.jl")
include("passthroughfifo.jl")
include("lzo1x1_stream_compression.jl")
include("lzo1x1_stream_decompression.jl")
include("lzo1x1_fast_compression.jl")
include("lzo1x1_fast_decompression.jl")

end
