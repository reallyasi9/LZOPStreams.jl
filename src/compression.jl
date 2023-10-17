const LZO1X_1_MEM_COMPRESS::Lzo_uint32_t = (16384 * lzo_sizeof_dict_t)

struct LZO1X1CompressorCodec <: TranscodingStreams.Codec
    working::Vector{Cuint}
    
    LZO1X1CompressorCodec() = new(Vector{Cuint}(undef, LZO1X_1_MEM_COMPRESS))
end