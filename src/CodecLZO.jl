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

using LZO_jll

include("liblzo2.jl")
include("compression.jl")
include("decompression.jl")

# Must be called before using the LZO library
function __init__()
    lzo_init()
    nothing
end

end
