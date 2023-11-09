using CodecLZO
import CodecLZO:
    HashMap,
    consume_input!

using TranscodingStreams
using Test

@testset "CodecLZO.jl" begin

    @testset "HashMap" begin
        h = HashMap{UInt8,Int}(8, 889523592379, 8)
        @test h[0x01] == 0
        h[0x01] = 1
        @test h[0x01] == 1
        # overwrite
        h[0x01] = 2
        @test h[0x01] == 2
        # empty
        empty!(h)
        @test h[0x01] == 0
        
        @testset "no 8-bit collisions" begin
            h8 = HashMap{UInt8,Int}(8, 889523592379, 8)
            collisions = 0
            for i in 0x00:0xff
                collisions += h8[i]
                h8[i] = 1
            end
            @test collisions == 0
        end

        @testset "no 16-bit collisions" begin
            h16 = HashMap{UInt16,Int}(16, 889523592379, 16)
            collisions = 0
            for i in 0x0000:0xffff
                collisions += h16[i]
                h16[i] = 1
            end
            @test collisions == 0
        end

        @testset "force 8-bit collisions" begin
            h87 = HashMap{UInt8,Int}(7, 889523592379, 7)
            collisions = 0
            for i in 0x00:0xff
                collisions += h87[i]
                h87[i] = 1
            end
            @test collisions >= 127

            h86 = HashMap{UInt8,Int}(6, 889523592379, 7)
            collisions = 0
            for i in 0x00:0xff
                collisions += h86[i]
                h86[i] = 1
            end
            @test collisions >= 191
        end

    end

    @testset "LZO1X1CompressorCodec" begin
        @testset "constructor" begin
            c = LZO1X1CompressorCodec()
        end

        @testset "transcode" begin
            compressed = transcode(LZO1X1CompressorCodec, UInt8[1, 2, 3, 4])
            @test compressed == UInt8[22, 1, 2, 3, 4, 0b00010001, 0, 0]

            compressed = transcode(LZO1X1CompressorCodec, UInt8[1, 2, 3, 4, 1, 2, 3, 4])
            @test compressed == UInt8[22, 1, 2, 3, 4, 0b01101100, 0, 0b00010001, 0, 0]

            compressed = transcode(LZO1X1CompressorCodec, UInt8[1, 2, 3, 4, 1, 2, 3, 4, 5, 6, 7, 8])
            @test compressed == UInt8[22, 1, 2, 3, 4, 0b01101100, 0, 0b00000001, 5, 6, 7, 8, 0b00010001, 0, 0]
        end

    end

end
