using CodecLZO
using Test

@testset "CodecLZO.jl" begin

    @testset "HashMap" begin
        @testset "hash" begin
            @test CodecLZO.hash(0) == 0
            @test CodecLZO.hash(0, -one(UInt8)) == zero(UInt8)
        end
    end

end
