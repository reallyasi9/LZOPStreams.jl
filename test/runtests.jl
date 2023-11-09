using CodecLZO
import CodecLZO:
    HashMap,
    consume_input!

using LZO_jll
using TranscodingStreams
using Test

# required to initialize the library
ccall((:__lzo_init_v2, liblzo2), Cint, (Cuint, Cint, Cint, Cint, Cint, Cint, Cint, Cint, Cint, Cint), 1, -1, -1, -1, -1, -1, -1, -1, -1, -1)

# working memory for LZO1X1
const working_memory = zeros(UInt8, 1<<16)

function lzo_compress(a::Vector{UInt8})
    l = length(a)
    size_ptr = Ref{Csize_t}()
    output = Vector{UInt8}(undef, l + l>>8 + 5) # minimum safe size
    @ccall liblzo2.lzo1x_1_compress(a::Ptr{Cuchar}, sizeof(a)::Csize_t, output::Ptr{Cuchar}, size_ptr::Ptr{Csize_t}, working_memory::Ptr{Cvoid})::Cint
    return resize!(output, size_ptr[])
end

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
            test_cases = [
                "small random" => rand(UInt8, 64),
                "large random" => rand(UInt8, CodecLZO.LZO1X1_MAX_DISTANCE),
            ]

            for (name, val) in test_cases
                @testset "$name" begin
                    @test transcode(LZO1X1CompressorCodec, val) == lzo_compress(val)
                end
            end
        end

    end

end
