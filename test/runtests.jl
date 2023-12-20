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

@testitem "HashMap force 8-bit collisions" begin
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

@testitem "LiteralCopyCommand" begin
    let
        null_command = CodecLZO.LiteralCopyCommand(0)
        @test null_command == CodecLZO.NULL_LITERAL_COMMAND

        for n in 1:3
            # Super-small literals can fit in the last two bits of the previous command
            # Except if there is no previous command...
            @test_throws ErrorException CodecLZO.LiteralCopyCommand(n; first_literal=true)

            lcc = CodecLZO.LiteralCopyCommand(n; first_literal=false)
            @test lcc.copy_length == n
            @test lcc.command_length == 0
        end

        for n in (4,238)
            # First literals can be compactly stored
            lcc = CodecLZO.LiteralCopyCommand(n; first_literal=true)
            @test lcc.copy_length == n
            @test lcc.command_length == 1
        end

        for n in (239,)
            # But only up to a point, where it reverts to the same as first_literal=false
            lcc = CodecLZO.LiteralCopyCommand(n; first_literal=true)
            @test lcc == CodecLZO.LiteralCopyCommand(n; first_literal=false)
        end

        for n in (4,18)
            # The first 4 bits can carry the copy length (minus 3)
            lcc = CodecLZO.LiteralCopyCommand(n; first_literal=false)
            @test lcc.copy_length == n
            @test lcc.command_length == 1
        end

        for n in (19,273)
            # If the length is longer, an additional byte stores the rest (minus 18)
            lcc = CodecLZO.LiteralCopyCommand(n; first_literal=false)
            @test lcc.copy_length == n
            @test lcc.command_length == 2
        end

        for n in (274,528)
            # Every additional 255 bytes of length is stored as a zero byte
            lcc = CodecLZO.LiteralCopyCommand(n; first_literal=false)
            @test lcc.copy_length == n
            @test lcc.command_length == 3
        end
    end
end

@testitem "decode LiteralCopyCommand" begin
    let
        # Valid first literals
        @test CodecLZO.decode(CodecLZO.LiteralCopyCommand, UInt8[17]) == CodecLZO.LiteralCopyCommand(1,0)
        @test CodecLZO.decode(CodecLZO.LiteralCopyCommand, UInt8[255]) == CodecLZO.LiteralCopyCommand(1,238)

        # Invalid first literal
        @test_throws ErrorException CodecLZO.decode(CodecLZO.LiteralCopyCommand, UInt8[16])

        # Long literals
        @test CodecLZO.decode(CodecLZO.LiteralCopyCommand, UInt8[0b00000001]) == CodecLZO.LiteralCopyCommand(1,4)
        @test CodecLZO.decode(CodecLZO.LiteralCopyCommand, UInt8[0b00001111]) == CodecLZO.LiteralCopyCommand(1,18)
        @test CodecLZO.decode(CodecLZO.LiteralCopyCommand, UInt8[0b00000000,0b00000001]) == CodecLZO.LiteralCopyCommand(2,19)
        @test CodecLZO.decode(CodecLZO.LiteralCopyCommand, UInt8[0b00000000,0b11111111]) == CodecLZO.LiteralCopyCommand(2,273)
        @test CodecLZO.decode(CodecLZO.LiteralCopyCommand, UInt8[0b00000000,0b00000000,0b00000001]) == CodecLZO.LiteralCopyCommand(3,274)
    end
end

@testitem "encode LiteralCopyCommand" begin
    let
        # Valid first literals
        output = zeros(UInt8, 4)
        CodecLZO.encode!(output, CodecLZO.LiteralCopyCommand(1,0); first_literal=true)
        @test output == UInt8[17, 0, 0, 0]

        fill!(output, zero(UInt8))
        CodecLZO.encode!(output, CodecLZO.LiteralCopyCommand(1,238); first_literal=true)
        @test output == UInt8[255, 0, 0, 0]
        
        # Fall back to long literal
        fill!(output, zero(UInt8))
        CodecLZO.encode!(output, CodecLZO.LiteralCopyCommand(1,239); first_literal=true) # Note: number of bytes is ignored
        @test output == UInt8[0, 239-18, 0, 0]

        # Long literals
        fill!(output, zero(UInt8))
        CodecLZO.encode!(output, CodecLZO.LiteralCopyCommand(1,4))
        @test output == UInt8[1, 0, 0, 0]

        fill!(output, zero(UInt8))
        CodecLZO.encode!(output, CodecLZO.LiteralCopyCommand(1,18))
        @test output == UInt8[0b00001111, 0, 0, 0]

        fill!(output, zero(UInt8))
        CodecLZO.encode!(output, CodecLZO.LiteralCopyCommand(2,19))
        @test output == UInt8[0, 1, 0, 0]

        fill!(output, zero(UInt8))
        CodecLZO.encode!(output, CodecLZO.LiteralCopyCommand(2,273))
        @test output == UInt8[0, 0b11111111, 0, 0]

        fill!(output, zero(UInt8))
        CodecLZO.encode!(output, CodecLZO.LiteralCopyCommand(3,274))
        @test output == UInt8[0, 0, 1, 0]
    end
end

@testitem "unsafe_encode LiteralCopyCommand" begin
    let
        # Valid first literals
        output = zeros(UInt8, 4)
        CodecLZO.unsafe_encode!(pointer(output), CodecLZO.LiteralCopyCommand(1,0); first_literal=true)
        @test output == UInt8[17, 0, 0, 0]

        fill!(output, zero(UInt8))
        CodecLZO.unsafe_encode!(pointer(output), CodecLZO.LiteralCopyCommand(1,238); first_literal=true)
        @test output == UInt8[255, 0, 0, 0]
        
        # Fall back to long literal
        fill!(output, zero(UInt8))
        CodecLZO.unsafe_encode!(pointer(output), CodecLZO.LiteralCopyCommand(1,239); first_literal=true) # Note: number of bytes is ignored
        @test output == UInt8[0, 239-18, 0, 0]

        # Long literals
        fill!(output, zero(UInt8))
        CodecLZO.unsafe_encode!(pointer(output), CodecLZO.LiteralCopyCommand(1,4))
        @test output == UInt8[1, 0, 0, 0]

        fill!(output, zero(UInt8))
        CodecLZO.unsafe_encode!(pointer(output), CodecLZO.LiteralCopyCommand(1,18))
        @test output == UInt8[0b00001111, 0, 0, 0]

        fill!(output, zero(UInt8))
        CodecLZO.unsafe_encode!(pointer(output), CodecLZO.LiteralCopyCommand(2,19))
        @test output == UInt8[0, 1, 0, 0]

        fill!(output, zero(UInt8))
        CodecLZO.unsafe_encode!(pointer(output), CodecLZO.LiteralCopyCommand(2,273))
        @test output == UInt8[0, 0b11111111, 0, 0]

        fill!(output, zero(UInt8))
        CodecLZO.unsafe_encode!(pointer(output), CodecLZO.LiteralCopyCommand(3,274))
        @test output == UInt8[0, 0, 1, 0]
    end
end

@testitem "HistoryCopyCommand" begin
    let
        null_command = CodecLZO.HistoryCopyCommand(0,0,0,0)
        @test null_command == CodecLZO.NULL_HISTORY_COMMAND

        # first by size of copy, then by distance of copy

        @test_throws ErrorException CodecLZO.HistoryCopyCommand(1, 0, 0) # too short
        @test_throws ErrorException CodecLZO.HistoryCopyCommand(1, 1, 0) # too short
        @test_throws ErrorException CodecLZO.HistoryCopyCommand(0, 2, 0) # too near
        @test_throws ErrorException CodecLZO.HistoryCopyCommand(1, 2, 4) # too many post-copy literals
        @test_throws ErrorException CodecLZO.HistoryCopyCommand(49153, 2, 0) # too far

        # length = 2 is special
        for d in (1,1024)
            # This is only allowed if the number of literals copied last was 1, 2, or 3.
            let
                hcc = CodecLZO.HistoryCopyCommand(d, 2, 0; last_literals_copied=1)
                @test hcc.command_length == 2
                @test hcc.lookback == d
                @test hcc.copy_length == 2
            end
        end
        @test_throws ErrorException CodecLZO.HistoryCopyCommand(1025, 2, 0; last_literals_copied=1)
        @test_throws ErrorException CodecLZO.HistoryCopyCommand(1024, 2, 0; last_literals_copied=0)
        @test_throws ErrorException CodecLZO.HistoryCopyCommand(1024, 2, 0; last_literals_copied=4)

        # length = 3 has four zones
        for d in (1,2048)
            let
                hcc = CodecLZO.HistoryCopyCommand(d, 3, 0)
                @test hcc.command_length == 2
                @test hcc.lookback == d
                @test hcc.copy_length == 3
            end
        end
        for d in (2049,3072)
            # This zone is special and is only available if the previous copy command included extra literals
            let
                hcc = CodecLZO.HistoryCopyCommand(d, 3, 0; last_literals_copied=4)
                @test hcc.command_length == 2
                @test hcc.lookback == d
                @test hcc.copy_length == 3
            end
        end
        for d in (3073,16384)
            let
                hcc = CodecLZO.HistoryCopyCommand(d, 3, 0)
                @test hcc.command_length == 3
                @test hcc.lookback == d
                @test hcc.copy_length == 3
            end
        end
        for d in (16385,49152)
            let
                hcc = CodecLZO.HistoryCopyCommand(d, 3, 0)
                @test hcc.command_length == 3
                @test hcc.lookback == d
                @test hcc.copy_length == 3
            end
        end

        # length = 4 has only 3 zones
        for d in (1,2048)
            let
                hcc = CodecLZO.HistoryCopyCommand(d, 4, 0)
                @test hcc.command_length == 2
                @test hcc.lookback == d
                @test hcc.copy_length == 4
            end
        end
        for d in (2049,16384)
            let
                hcc = CodecLZO.HistoryCopyCommand(d, 4, 0)
                @test hcc.command_length == 3
                @test hcc.lookback == d
                @test hcc.copy_length == 4
            end
        end
        for d in (16385,49152)
            let
                hcc = CodecLZO.HistoryCopyCommand(d, 4, 0)
                @test hcc.command_length == 3
                @test hcc.lookback == d
                @test hcc.copy_length == 4
            end
        end

        # length = 5 through 8 have 3 zones also
        for l in 5:8
            for d in (1,2048)
                let
                    hcc = CodecLZO.HistoryCopyCommand(d, l, 0)
                    @test hcc.command_length == 2
                    @test hcc.lookback == d
                    @test hcc.copy_length == l
                end
            end
            for d in (2049,16384)
                let
                    hcc = CodecLZO.HistoryCopyCommand(d, l, 0)
                    @test hcc.command_length == 3
                    @test hcc.lookback == d
                    @test hcc.copy_length == l
                end
            end
            for d in (16385,49152)
                let
                    hcc = CodecLZO.HistoryCopyCommand(d, l, 0)
                    @test hcc.command_length == 3
                    @test hcc.lookback == d
                    @test hcc.copy_length == l
                end
            end
        end

        # lengths greater than 8 have only 2 zones
        for d in (1,16384)
            let
                hcc = CodecLZO.HistoryCopyCommand(d, 9, 0)
                @test hcc.command_length == 3
                @test hcc.lookback == d
                @test hcc.copy_length == 9
            end
        end
        for d in (16385,49152)
            let
                hcc = CodecLZO.HistoryCopyCommand(d, 9, 0)
                @test hcc.command_length == 3
                @test hcc.lookback == d
                @test hcc.copy_length == 9
            end
        end

        # lengths are run-length encoded
        # closer copies break at 33, farther copies break at 9
        let
            hcc = CodecLZO.HistoryCopyCommand(16385, 9, 0)
            @test hcc.command_length == 3

            hcc = CodecLZO.HistoryCopyCommand(16385, 10, 0)
            @test hcc.command_length == 4

            hcc = CodecLZO.HistoryCopyCommand(16385, 264, 0)
            @test hcc.command_length == 4

            hcc = CodecLZO.HistoryCopyCommand(16385, 265, 0)
            @test hcc.command_length == 5
        end

        let
            hcc = CodecLZO.HistoryCopyCommand(1, 33, 0)
            @test hcc.command_length == 3

            hcc = CodecLZO.HistoryCopyCommand(1, 34, 0)
            @test hcc.command_length == 4

            hcc = CodecLZO.HistoryCopyCommand(1, 288, 0)
            @test hcc.command_length == 4

            hcc = CodecLZO.HistoryCopyCommand(1, 289, 0)
            @test hcc.command_length == 5
        end
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