using CodecLZO
using Test

@testset "CodecLZO.jl" begin
    @test CodecLZO.lzo_version() == 0x20a0
    @test CodecLZO.lzo_version_string() == "2.10"
    @test CodecLZO.lzo_version_date() == "Mar 01 2017"
    @test CodecLZO.lzo_init() == CodecLZO.LZO_E_OK
end
