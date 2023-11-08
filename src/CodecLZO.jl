module CodecLZO

export
    LZO1X1CompressorCodec,
    LZOCompressorCodec,
    LZOCompressorStream

import TranscodingStreams:
    TranscodingStreams,
    TranscodingStream,
    Memory,
    Error,
    splitkwargs

import CircularArrays:
    CircularVector

include("memory_management.jl")
include("hashmap.jl")
include("lzo1x1_compression.jl")
include("decompression.jl")

end
