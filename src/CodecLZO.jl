module CodecLZO

export
    LZO1X1CompressorCodec

import TranscodingStreams:
    TranscodingStreams,
    TranscodingStream,
    Memory,
    Error,
    initialize,
    finalize,
    splitkwargs

import CircularArrays:
    CircularArray

include("dict.jl")
include("hashmap.jl")
include("lzo1x1_compression.jl")
include("decompression.jl")

end
