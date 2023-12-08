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
    LZOFastDecompressorStream,
    unsafe_lzo_compress!,
    lzo_compress!,
    lzo_compress,
    unsafe_lzo_decompress!,
    lzo_decompress!,
    lzo_decompress

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

function __init__()
    # The LZO library initialization method takes parameters that check that the following values are consistent between the compiled library and the code calling it:
    # 1. the version of the library (must be != 0)
    # 2. sizeof(short)
    # 3. sizeof(int)
    # 4. sizeof(long)
    # 5. sizeof(lzo_uint32_t) (required to be 4 bytes, irrespective of machine architecture)
    # 6. sizeof(lzo_uint) (required to be 8 bytes, irrespective of machine architecture)
    # 7. lzo_sizeof_dict_t (size of a pointer)
    # 8. sizeof(char *)
    # 9. sizeof(lzo_voidp) (size of void *)
    # 10. sizeof(lzo_callback_t) (size of a complex callback struct)
    # If any of these arguments except the first is -1, the check is skipped.
    e = ccall((:__lzo_init_v2, liblzo2), Cint, (Cuint, Cint, Cint, Cint, Cint, Cint, Cint, Cint, Cint, Cint), 1, sizeof(Cshort), sizeof(Cint), sizeof(Clong), sizeof(Culong), sizeof(Culonglong), sizeof(Ptr{Cchar}), sizeof(Ptr{Cchar}), sizeof(Ptr{Cvoid}), -1)
    if e != LZO_E_OK
        throw(ErrorException("initialization of liblzo2 failed: $e"))
    end
end

end
