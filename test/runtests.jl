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
    c1 = LZO1X1CompressorCodec()
    c2 = LZOCompressorCodec()
    @test true
end

@testitem "LZO1X1CompressorCodec transcode" begin
    using TranscodingStreams
    using Random
    
    let
        small_array = UInt8.(collect(0:255)) # no repeats, so should be one long literal
        small_array_compressed = transcode(LZOCompressorCodec, small_array)
        @test length(small_array_compressed) == 2 + length(small_array) + 3

        # The first command should be a copy of the entire 256-byte literal.
        # The 0b0000XXXX command copies literals with a length encoding of either 3 + XXXX or 18 + (zero bytes following command) * 255 + (non-zero trailing byte).
        @test small_array_compressed[1:2] == UInt8[0b00000000, 256 - 18]

        # The last command is boilerplate: a copy of 3 bytes from distance 16384
        @test small_array_compressed[end-2:end] == UInt8[0b00010001, 0, 0]
        
        double_small_array = vcat(small_array, small_array) # this should add an additional 5 bytes to the literal because the skip logic, followed by a long copy command
        double_small_array_compressed = transcode(LZOCompressorCodec, double_small_array)
        @test length(double_small_array_compressed) == 2 + (length(small_array) + 5) + 4 + 3

    end
end

@run_package_tests verbose = true