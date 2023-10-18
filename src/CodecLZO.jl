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

include("dict.jl")
include("compression.jl")
include("decompression.jl")

end
