import CodecLZO:
    HashMap,
    CircularBuffer

using Test

@testset "CodecLZO.jl" begin

    @testset "HashMap" begin
        h = HashMap{UInt8,Int}(8)
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
            h8 = HashMap{UInt8,Int}(8)
            collisions = 0
            for i in 0x00:0xff
                collisions += h8[i]
                h8[i] = 1
            end
            @test collisions == 0
        end

        @testset "no 16-bit collisions" begin
            h16 = HashMap{UInt16,Int}(16)
            collisions = 0
            for i in 0x0000:0xffff
                collisions += h16[i]
                h16[i] = 1
            end
            @test collisions == 0
        end

        @testset "force 8-bit collisions" begin
            h87 = HashMap{UInt8,Int}(7)
            collisions = 0
            for i in 0x00:0xff
                collisions += h87[i]
                h87[i] = 1
            end
            @test collisions >= 127

            h86 = HashMap{UInt8,Int}(6)
            collisions = 0
            for i in 0x00:0xff
                collisions += h86[i]
                h86[i] = 1
            end
            @test collisions >= 191
        end

    end

    @testset "CircularBuffer" begin
        @testset "basic methods" begin
            cb = CircularBuffer()
            @test length(cb) == 0
        end
    end

end
