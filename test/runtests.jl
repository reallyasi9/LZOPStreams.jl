using CodecLZO

using LZO_jll
using Random
using TranscodingStreams
using TestItemRunner

@testitem "HashMap" begin
    h = CodecLZO.HashMap{UInt8,Int}(8, UInt8(2^8 - 45)) # that's prime
    @test h[0x01] == 0
    h[0x01] = 1
    @test h[0x01] == 1
    # overwrite
    h[0x01] = 2
    @test h[0x01] == 2
    # empty
    empty!(h)
    @test h[0x01] == 0
end

@testitem "HashMap no 8-bit collisions" begin
    let
        h8 = CodecLZO.HashMap{UInt8,Int}(8, UInt8(2^8 - 59)) # that's also prime
        collisions = 0
        for i in 0x00:0xff
            collisions += h8[i]
            h8[i] = 1
        end
        @test collisions == 0
    end
end

@testitem "HashMap no 16-bit collisions" begin
    let
        h16 = CodecLZO.HashMap{UInt16,Int}(16, UInt16(54869)) # yup: it's prime
        collisions = 0
        for i in 0x0000:0xffff
            collisions += h16[i]
            h16[i] = 1
        end
        @test collisions == 0
    end
end

@testitem "force 8-bit collisions" begin
    let
        h87 = CodecLZO.HashMap{UInt8,Int}(7, UInt8(157))
        collisions = 0
        for i in 0x00:0xff
            collisions += h87[i]
            h87[i] = 1
        end
        @test collisions >= 127

        h86 = CodecLZO.HashMap{UInt8,Int}(6, UInt8(157))
        collisions = 0
        for i in 0x00:0xff
            collisions += h86[i]
            h86[i] = 1
        end
        @test collisions >= 191
    end
end



@testitem "LZO1X1CompressorCodec constructor" begin
    c = LZO1X1CompressorCodec()
end

@testitem "LZO1X1CompressorCodec transcode" begin
    using TranscodingStreams
    using LZO_jll
    using Random
    
    function lzo_compress(a::Vector{UInt8})
        ccall((:__lzo_init_v2, liblzo2), Cint, (Cuint, Cint, Cint, Cint, Cint, Cint, Cint, Cint, Cint, Cint), 1, -1, -1, -1, -1, -1, -1, -1, -1, -1)
        working_memory = zeros(UInt8, 1 << 16)
        l = length(a)
        size_ptr = Ref{Csize_t}()
        output = Vector{UInt8}(undef, l + l >> 8 + 5) # minimum safe size
        @ccall liblzo2.lzo1x_1_compress(a::Ptr{Cuchar}, sizeof(a)::Csize_t, output::Ptr{Cuchar}, size_ptr::Ptr{Csize_t}, working_memory::Ptr{Cvoid})::Cint
        return resize!(output, size_ptr[])
    end

    function lzo_decompress(a::Vector{UInt8})
        ccall((:__lzo_init_v2, liblzo2), Cint, (Cuint, Cint, Cint, Cint, Cint, Cint, Cint, Cint, Cint, Cint), 1, -1, -1, -1, -1, -1, -1, -1, -1, -1)
        working_memory = UInt8[] # no working memory needed to decompress
        LZO_E_OUTPUT_OVERRUN = -5 # error that tells us to resize the output array
        l = length(a)
        output = Vector{UInt8}(undef, l * 2) # guess size, will be resized in the loop that follows
        size_ptr = Ref{Csize_t}(length(output))
        while ccall((:lzo1x_decompress, liblzo2), Cint, (Ptr{Cuchar}, Csize_t, Ptr{Cuchar}, Ptr{Csize_t}, Ptr{Cvoid}), a, sizeof(a), output, size_ptr, working_memory) == LZO_E_OUTPUT_OVERRUN
            resize!(output, length(output) * 2)
            size_ptr[] = length(output)
        end
        return resize!(output, size_ptr[])
    end

    let
        rng = Random.Xoshiro(42)
        small_random = rand(rng, UInt8, 24)
        limit_random = rand(rng, UInt8, CodecLZO.LZO1X1_MAX_DISTANCE + 1)
        large_random = rand(rng, UInt8, 1_000_000)

        # randoms should find no matches in history, so these should just encode extremely long literal copies
        lzo_compressed = lzo_compress(small_random)
        compressed = transcode(LZO1X1CompressorCodec, small_random)
        @test length(compressed) == length(lzo_compressed)
        @test compressed == lzo_compressed
        @test lzo_decompress(compressed) == small_random

        lzo_compressed = lzo_compress(limit_random)
        compressed = transcode(LZO1X1CompressorCodec, limit_random)
        @test length(compressed) == length(lzo_compressed)
        @test compressed == lzo_compressed

        lzo_compressed = lzo_compress(large_random)
        compressed = transcode(LZO1X1CompressorCodec, large_random)
        @test length(compressed) == length(lzo_compressed)
        @test compressed == lzo_compressed
    end
end

@run_package_tests verbose = true