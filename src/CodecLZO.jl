module CodecLZO

export
    LZOCompressor,
    LZOCompressorStream,
    LZODecompressor,
    LZODecompressorStream

import TranscodingStreams:
    TranscodingStreams,
    TranscodingStream,
    Memory,
    Error,
    initialize,
    finalize,
    splitkwargs

import DataStructures:
    CircularBuffer

include("dict.jl")
include("hashmap.jl")
include("compression.jl")
include("decompression.jl")

end
