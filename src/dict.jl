# Dictionary functions from lzo_dict.h

LZO_SIZE(bits) = 1 << bits
LZO_MASK(bits) = LZO_SIZE(bits) - 1
DX2(p::AbstractVector{UInt8}, s1::Integer, s2::Integer) = @inbounds (((p[3] << s2) ⊻ p[2]) << s1) ⊻ p[1]
DX3(p::AbstractVector{UInt8}, s1::Integer, s2::Integer, s3::Integer) = @inbounds (((((p[4] << s3) ⊻ p[3]) << s2) ⊻ p[2]) << s1) ⊻ p[1]
DM(mask, v, s::Integer=0) = (v & (mask >> s)) << s