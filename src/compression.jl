abstract type LZOCompressorCodec <: TranscodingStreams.Codec end

dictionary_type(::LZOCompressorCodec) = Nothing
dictionary_bits(::LZOCompressorCodec) = nothing
dictionary_index1(::LZOCompressorCodec, ::Integer, ::AbstractVector{UInt8}) = nothing
dictionary_index2(::LZOCompressorCodec, ::Integer, ::AbstractVector{UInt8}) = nothing
dictionary_index(::LZOCompressorCodec, ::Integer) = nothing

dictionary_mask(c::LZOCompressorCodec) = (1 << dictionary_bits(c)) - 1
dictionary_high(c::LZOCompressorCodec) = (1 << (dictionary_bits(c) - 1)) + 1


struct LZO1X1CompressorCodec <: LZOCompressorCodec
    working::Vector{UInt8}
    bytes_processed::Int
    
    LZO1X1CompressorCodec() = new(Vector{UInt8}(undef, 16384), 0)
end

dictionary_type(::LZO1X1CompressorCodec) = UInt16
dictionary_bits(::LZO1X1CompressorCodec) = 14
dictionary_index1(c::LZOCompressorCodec, ::Integer, p::AbstractVector{UInt8}) = DM(dictionary_mask(c), (0x21 * DX3(p, 5, 5, 6)) >> 5)
dictionary_index2(c::LZOCompressorCodec, d::Integer, ::AbstractVector{UInt8}) = d & (dictionary_mask(c) & 0x7ff) ⊻ (dictionary_high(c) | 0x1f)
dictionary_index(c::LZOCompressorCodec, dv::Integer) = (0x1824429d * dv) >> (32 - dictionary_bits(c))

function TranscodingStreams.initialize(codec::LZO1X1CompressorCodec)
    fill!(codec.working, 0)
    codec.bytes_processed = 0
    return
end

function TranscodingStreams.process(codec::LZO1X1CompressorCodec, input::Memory, output::Memory, error::Error)
    n_read = 0
    n_written = 0
    status = :ok

    # Processing is done in chunks of 49152 bytes
    if length(input) == 0
        # acts as an instruction to end processing
    end

    return n_read, n_written, status
end