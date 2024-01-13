using CodecLZO
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

@testitem "CommandPair command_length" begin
    using CodecLZO: CommandPair, command_length

    let 
        # null command
        @test_throws ErrorException command_length(CodecLZO.NULL_COMMAND)

        # small first literal
        cp = CommandPair(true, 0, 0, 0)
        @test_throws ErrorException command_length(cp)

        # first literal with copy command
        cp = CommandPair(true, 100, 100, 4)
        @test_throws ErrorException command_length(cp)

        # negative literal length
        cp = CommandPair(false, 100, 100, -1)
        @test_throws ErrorException command_length(cp)

        # small copy
        cp = CommandPair(false, 100, 1, 100)
        @test_throws ErrorException command_length(cp)

        # zero lookback
        cp = CommandPair(false, 0, 100, 100)
        @test_throws ErrorException command_length(cp)

        # illegal length-2 copies
        # bad last literals
        cp = CommandPair(false, 100, 2, 100)
        @test_throws ErrorException command_length(cp)
        @test_throws ErrorException command_length(cp, 4)
        # lookback too long
        cp = CommandPair(false, 1<<10 + 1, 2, 100)
        @test_throws ErrorException command_length(cp, 1)

        # small first literals
        cp = CommandPair(true, 0, 0, 4)
        @test command_length(cp) == 0 + 1
        cp = CommandPair(true, 0, 0, 0xff - 17)
        @test command_length(cp) == 0 + 1

        # longer first literals with run encoding
        cp = CommandPair(true, 0, 0, 0xff - 16)
        @test command_length(cp) == 0 + 2
        cp = CommandPair(true, 0, 0, 273)
        @test command_length(cp) == 0 + 2
        cp = CommandPair(true, 0, 0, 274)
        @test command_length(cp) == 0 + 3

        # length-2 copies, short literals
        cp = CommandPair(false, 100, 2, 3)
        @test command_length(cp, 1) == 2 + 0
        # length-2 copies, long literals
        cp = CommandPair(false, 100, 2, 274)
        @test command_length(cp, 1) == 2 + 3
        # length-3 copies (weird)
        cp = CommandPair(false, 2049, 3, 274)
        @test command_length(cp, 4) == 2 + 3
        # short, nearby copies
        cp = CommandPair(false, 100, 8, 274)
        @test command_length(cp, 4) == 2 + 3
        # short, nearby copies with run-encoded longer literals
        cp = CommandPair(false, 100, 8, 18)
        @test command_length(cp, 4) == 2 + 1
        cp = CommandPair(false, 100, 8, 19)
        @test command_length(cp, 4) == 2 + 2
        cp = CommandPair(false, 100, 8, 19)
        @test command_length(cp, 4) == 2 + 2
        cp = CommandPair(false, 100, 8, 273)
        @test command_length(cp, 4) == 2 + 2
        cp = CommandPair(false, 100, 8, 274)
        @test command_length(cp, 4) == 2 + 3

        # longer nearby copies with run encoding
        cp = CommandPair(false, 1 << 11 + 1, 33, 274)
        @test command_length(cp, 4) == 3 + 3
        cp = CommandPair(false, 1 << 11 + 1, 34, 274)
        @test command_length(cp, 4) == 4 + 3

        # longer long-distance copies with run encoding
        cp = CommandPair(false, 1 << 14 + 1, 9, 274)
        @test command_length(cp, 4) == 3 + 3
        cp = CommandPair(false, 1 << 14 + 1, 10, 274)
        @test command_length(cp, 4) == 4 + 3
        
    end
end

@testitem "CopyCommand encode" begin
    using CodecLZO: CommandPair, encode!, encode_literal_copy!, encode_history_copy!

    let
        # No space to write
        data = UInt8[]
        c = CommandPair(true, 0, 0, 4)
        @test encode_literal_copy!(data, c, 1) == 0
        @test encode!(data, c, 1) == 0

        # valid first literals
        resize!(data, 2)
        c = CommandPair(true, 0, 0, 4)
        @test encode_literal_copy!(data, c, 1) == 1
        @test encode!(data, c, 1) == 1
        @test data[1:1] == UInt8[0b00010101]

        # offset
        fill!(data, zero(UInt8))
        @test encode_literal_copy!(data, c, 2) == 1
        @test encode!(data, c, 2) == 1
        @test data[1:2] == UInt8[0b00000000, 0b00010101]

        c = CommandPair(true, 0, 0, 238)
        @test encode_literal_copy!(data, c, 1) == 1
        @test encode!(data, c, 1) == 1
        @test data[1:1] == UInt8[0b11111111]

        # Run-encoded first literal
        c = CommandPair(true, 0, 0, 239)
        @test encode_literal_copy!(data, c, 1) == 2
        @test encode!(data, c, 1) == 2
        @test data[1:2] == UInt8[0b00000000, 0b11011101]
        c = CommandPair(true, 0, 0, 273)
        @test encode_literal_copy!(data, c, 1) == 2
        @test encode!(data, c, 1) == 2
        @test data[1:2] == UInt8[0b00000000, 0b11111111]

        # No space to write
        c = CommandPair(true, 0, 0, 274)
        @test encode_literal_copy!(data, c, 1) == 0
        @test encode!(data, c, 1) == 0

        # Still no space due to start offset
        resize!(data, 3)
        @test encode_literal_copy!(data, c, 2) == 0
        @test encode!(data, c, 2) == 0

        # Finally, space to write!
        @test encode_literal_copy!(data, c, 1) == 3
        @test encode!(data, c, 1) == 3
        @test data[1:3] == UInt8[0b00000000, 0b00000000, 0b00000001]

        # length-2 copy with short literal
        c = CommandPair(false, 1, 2, 3)
        @test encode_history_copy!(data, c, 1, 1) == 2
        @test data[1:2] == UInt8[0b00000011, 0b00000000]
        @test encode!(data, c, 1; last_literal_length=1) == 2
        @test data[1:2] == UInt8[0b00000011, 0b00000000]

        # length-2 copy with long literal
        c = CommandPair(false, 1024, 2, 4)
        @test encode_history_copy!(data, c, 1, 1) == 2
        @test data[1:2] == UInt8[0b00001100, 0b11111111]
        @test encode!(data, c, 1; last_literal_length=1) == 3
        @test data[1:3] == UInt8[0b00001100, 0b11111111, 0b00000001]

        # length-2 copy with invalid last literals
        @test_throws ErrorException encode_history_copy!(data, c, 1, 0)
        @test_throws ErrorException encode!(data, c, 1; last_literal_length=0)
        @test_throws ErrorException encode_history_copy!(data, c, 1, 4)
        @test_throws ErrorException encode!(data, c, 1; last_literal_length=4)

        # length-2 copy with too long a lookback
        c = CommandPair(false, 1025, 2, 4)
        @test_throws ErrorException encode_history_copy!(data, c, 1, 1)
        @test_throws ErrorException encode!(data, c, 1; last_literal_length=1)

        # length-3 short-distance copy with short literal
        c = CommandPair(false, 1, 3, 3)
        @test encode_history_copy!(data, c, 1, 0) == 2
        @test data[1:2] == UInt8[0b01000011, 0b00000000]
        @test encode!(data, c, 1) == 2
        @test data[1:2] == UInt8[0b01000011, 0b00000000]

        # length-3 short-distance copy with long literal
        c = CommandPair(false, 2048, 3, 4)
        @test encode_history_copy!(data, c, 1, 0) == 2
        @test data[1:2] == UInt8[0b01011100, 0b11111111]
        @test encode!(data, c, 1) == 3
        @test data[1:3] == UInt8[0b01011100, 0b11111111, 0b00000001]

        # length-3 medium-distance copy with short literal
        c = CommandPair(false, 2049, 3, 3)
        @test encode_history_copy!(data, c, 1, 4) == 2
        @test data[1:2] == UInt8[0b00000011, 0b00000000]
        @test encode!(data, c, 1; last_literal_length=4) == 2
        @test data[1:2] == UInt8[0b00000011, 0b00000000]

        # length-3 medium-distance copy with long literal
        c = CommandPair(false, 3072, 3, 4)
        @test encode_history_copy!(data, c, 1, 4) == 2
        @test data[1:2] == UInt8[0b00001100, 0b11111111]
        @test encode!(data, c, 1; last_literal_length=4) == 3
        @test data[1:3] == UInt8[0b00001100, 0b11111111, 0b00000001]

        # length-3 medium-distance copy with invalid last literal
        resize!(data, 4)
        c = CommandPair(false, 3072, 3, 4)
        @test encode_history_copy!(data, c, 1, 0) == 3
        @test data[1:3] == UInt8[0b00100001, 0b11111100, 0b00101111]
        @test encode!(data, c, 1; last_literal_length=0) == 4
        @test data[1:4] == UInt8[0b00100001, 0b11111100, 0b00101111, 0b00000001]

        # length-4 copy with short literal
        c = CommandPair(false, 1, 4, 3)
        @test encode_history_copy!(data, c, 1, 0) == 2
        @test data[1:2] == UInt8[0b01100011, 0b00000000]
        @test encode!(data, c, 1) == 2
        @test data[1:2] == UInt8[0b01100011, 0b00000000]

        # length-4 copy with long literal
        c = CommandPair(false, 2048, 4, 4)
        @test encode_history_copy!(data, c, 1, 0) == 2
        @test data[1:2] == UInt8[0b01111100, 0b11111111]
        @test encode!(data, c, 1) == 3
        @test data[1:3] == UInt8[0b01111100, 0b11111111, 0b00000001]

        # length-4 copy with long lookback
        c = CommandPair(false, 2049, 4, 4)
        @test encode_history_copy!(data, c, 1, 0) == 3
        @test data[1:3] == UInt8[0b00100010, 0b00000000, 0b00100000]
        @test encode!(data, c, 1) == 4
        @test data[1:4] == UInt8[0b00100010, 0b00000000, 0b00100000, 0b00000001]

        # length-5-8 copy with short literal
        c = CommandPair(false, 1, 5, 3)
        @test encode_history_copy!(data, c, 1, 0) == 2
        @test data[1:2] == UInt8[0b10000011, 0b00000000]
        @test encode!(data, c, 1) == 2
        @test data[1:2] == UInt8[0b10000011, 0b00000000]

        # length-5-8 copy with long literal
        c = CommandPair(false, 2048, 8, 4)
        @test encode_history_copy!(data, c, 1, 0) == 2
        @test data[1:2] == UInt8[0b11111100, 0b11111111]
        @test encode!(data, c, 1) == 3
        @test data[1:3] == UInt8[0b11111100, 0b11111111, 0b00000001]

        # length-5-8 copy with long lookback
        c = CommandPair(false, 2049, 8, 4)
        @test encode_history_copy!(data, c, 1, 0) == 3
        @test data[1:3] == UInt8[0b00100110, 0b00000000, 0b00100000]
        @test encode!(data, c, 1) == 4
        @test data[1:4] == UInt8[0b00100110, 0b00000000, 0b00100000, 0b00000001]

        # short lookback with short literal
        c = CommandPair(false, 1, 9, 1)
        @test encode_history_copy!(data, c, 1, 0) == 3
        @test data[1:3] == UInt8[0b00100111, 0b00000001, 0b00000000]
        @test encode!(data, c, 1) == 3
        @test data[1:3] == UInt8[0b00100111, 0b00000001, 0b00000000]

        # short lookback with short literal and run-encoded length
        c = CommandPair(false, 1, 34, 3)
        @test encode_history_copy!(data, c, 1, 0) == 4
        @test data[1:4] == UInt8[0b00100000, 0b00000001, 0b00000011, 0b00000000]
        @test encode!(data, c, 1) == 4
        @test data[1:4] == UInt8[0b00100000, 0b00000001, 0b00000011, 0b00000000]

        # short lookback with long literal and run-encoded length
        resize!(data, 6)
        c = CommandPair(false, 16384, 289, 4)
        @test encode_history_copy!(data, c, 1, 0) == 5
        @test data[1:5] == UInt8[0b00100000, 0b00000000, 0b00000001, 0b11111100, 0b11111111]
        @test encode!(data, c, 1) == 6
        @test data[1:6] == UInt8[0b00100000, 0b00000000, 0b00000001, 0b11111100, 0b11111111, 0b00000001]

        # long lookback with short literal
        c = CommandPair(false, 16385, 3, 1)
        @test encode_history_copy!(data, c, 1, 0) == 3
        @test data[1:3] == UInt8[0b00010001, 0b00000101, 0b00000000]
        @test encode!(data, c, 1) == 3
        @test data[1:3] == UInt8[0b00010001, 0b00000101, 0b00000000]

        # long lookback with short literal and run-encoded length
        c = CommandPair(false, 16385, 10, 3)
        @test encode_history_copy!(data, c, 1, 0) == 4
        @test data[1:4] == UInt8[0b00010000, 0b00000001, 0b00000111, 0b00000000]
        @test encode!(data, c, 1) == 4
        @test data[1:4] == UInt8[0b00010000, 0b00000001, 0b00000111, 0b00000000]

        # long lookback with long literal and run-encoded length
        c = CommandPair(false, 49151, 10, 4)
        @test encode_history_copy!(data, c, 1, 0) == 4
        @test data[1:4] == UInt8[0b00011000, 0b00000001, 0b11111100, 0b11111111]
        @test encode!(data, c, 1) == 5
        @test data[1:5] == UInt8[0b00011000, 0b00000001, 0b11111100, 0b11111111, 0b00000001]

        # long lookback, run-encoded literal, run-encoded length (as big as it gets!)
        c = CommandPair(false, 49151, 265, 4)
        @test encode_history_copy!(data, c, 1, 0) == 5
        @test data[1:5] == UInt8[0b00011000, 0b00000000, 0b00000001, 0b11111100, 0b11111111]
        @test encode!(data, c, 1) == 6
        @test data[1:6] == UInt8[0b00011000, 0b00000000, 0b00000001, 0b11111100, 0b11111111, 0b00000001]

        # too long a lookback
        c = CommandPair(false, 49152, 265, 4)
        @test_throws ErrorException encode_history_copy!(data, c, 1, 0)

        # EOS-lookalike
        c = CommandPair(false, CodecLZO.END_OF_STREAM_LOOKBACK, CodecLZO.END_OF_STREAM_COPY_LENGTH, 0)
        @test encode_history_copy!(data, c, 1, 0) == 3
        @test data[1:3] == UInt8[0b00100001, 0b00000000, 0b00000000]

    end
end

@testitem "unsafe_decode LiteralCopyCommand" begin
    data = zeros(UInt8, 3)
    let
        # Valid first literals
        data[1] = 17
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.LiteralCopyCommand, pointer(data), 1) == CodecLZO.LiteralCopyCommand(1,0)
        data[2] = 255
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.LiteralCopyCommand, pointer(data), 2) == CodecLZO.LiteralCopyCommand(1,238)

        # Invalid first literal
        data[3] = 16
        @test_throws ErrorException @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.LiteralCopyCommand, pointer(data), 3)

        # Long literals
        data[1] = 0b00000001
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.LiteralCopyCommand, pointer(data), 1) == CodecLZO.LiteralCopyCommand(1,4)
        data[2] = 0b00001111
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.LiteralCopyCommand, pointer(data), 2) == CodecLZO.LiteralCopyCommand(1,18)
        data[2:3] = UInt8[0b00000000,0b00000001]
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.LiteralCopyCommand, pointer(data), 2) == CodecLZO.LiteralCopyCommand(2,19)
        data[1:2] = UInt8[0b00000000,0b11111111]
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.LiteralCopyCommand, pointer(data), 1) == CodecLZO.LiteralCopyCommand(2,273)
        data[1:3] = UInt8[0b00000000,0b00000000,0b00000001]
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.LiteralCopyCommand, pointer(data)) == CodecLZO.LiteralCopyCommand(3,274)
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

@testitem "decode HistoryCopyCommand" begin
    let
        # Length 2 copies
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0, 0]; last_literals_copied=1) == CodecLZO.HistoryCopyCommand(1, 2, 0; last_literals_copied=1)
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b00001111, 0b11111111]; last_literals_copied=3) == CodecLZO.HistoryCopyCommand(1024, 2, 3; last_literals_copied=3)
        
        # Invalid length 2 copies
        @test_throws ErrorException CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0, 0]; last_literals_copied=0)

        # Length 3 copies
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0, 0]; last_literals_copied=4) == CodecLZO.HistoryCopyCommand(2049, 3, 0; last_literals_copied=4)
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b00001111, 0b11111111]; last_literals_copied=typemax(Int)) == CodecLZO.HistoryCopyCommand(3072, 3, 3; last_literals_copied=typemax(Int))

        # Broken short command
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0]; last_literals_copied=4) == CodecLZO.NULL_HISTORY_COMMAND

        # Long-distance copies
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b00010001, 0b00000000, 0b00000000]) == CodecLZO.HistoryCopyCommand(16384, 3, 0) == CodecLZO.END_OF_STREAM_COMMAND
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b00011111, 0b11111111, 0b11111111]) == CodecLZO.HistoryCopyCommand(49151, 9, 3)
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b00011000, 0b00000001, 0b11111111, 0b11111111]) == CodecLZO.HistoryCopyCommand(49151, 10, 3)
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b00011000, 0b00000000, 0b00000001, 0b11111111, 0b11111111]) == CodecLZO.HistoryCopyCommand(49151, 265, 3)

        # Broken length run
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b00011000]) == CodecLZO.NULL_HISTORY_COMMAND

        # Broken distance 
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b00010001, 0b0000000]) == CodecLZO.NULL_HISTORY_COMMAND

        # Medium-distance copies
        # Note: the full constructor with command length is used here because this can be more efficiently expressed in a 2-byte command, below.
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b00100001, 0b00000000, 0b00000000]) == CodecLZO.HistoryCopyCommand(3, 1, 3, 0)
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b00111111, 0b11111111, 0b11111111]) == CodecLZO.HistoryCopyCommand(16384, 33, 3)
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b00100000, 0b00000001, 0b11111111, 0b11111111]) == CodecLZO.HistoryCopyCommand(16384, 34, 3)
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b00100000, 0b00000000, 0b00000001, 0b11111111, 0b11111111]) == CodecLZO.HistoryCopyCommand(16384, 289, 3)

        # Broken length run
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b00100000]) == CodecLZO.NULL_HISTORY_COMMAND

        # Broken distance 
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b00100001, 0b00000000]) == CodecLZO.NULL_HISTORY_COMMAND
        
        # Short-distance copies
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b01000000, 0b00000000]) == CodecLZO.HistoryCopyCommand(1, 3, 0)
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b01111111, 0b11111111]) == CodecLZO.HistoryCopyCommand(2048, 4, 3)

        # Broken command
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b01000000]) == CodecLZO.NULL_HISTORY_COMMAND

        # Short-distance copies
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b10000000, 0b00000000]) == CodecLZO.HistoryCopyCommand(1, 5, 0)
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b11111111, 0b11111111]) == CodecLZO.HistoryCopyCommand(2048, 8, 3)

        # Broken command
        @test CodecLZO.decode(CodecLZO.HistoryCopyCommand, UInt8[0b10000000]) == CodecLZO.NULL_HISTORY_COMMAND
    end
end

@testitem "unsafe_decode HistoryCopyCommand" begin
    data = zeros(UInt8, 5)
    let
        # Length 2 copies
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.HistoryCopyCommand, pointer(data); last_literals_copied=1) == CodecLZO.HistoryCopyCommand(1, 2, 0; last_literals_copied=1)
        data[1:2] = UInt8[0b00001111, 0b11111111]
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.HistoryCopyCommand, pointer(data), 1; last_literals_copied=3) == CodecLZO.HistoryCopyCommand(1024, 2, 3; last_literals_copied=3)
        
        # Invalid length 2 copies
        @test_throws ErrorException @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.HistoryCopyCommand, pointer(data), 3; last_literals_copied=0)

        # Length 3 copies
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.HistoryCopyCommand, pointer(data), 3; last_literals_copied=4) == CodecLZO.HistoryCopyCommand(2049, 3, 0; last_literals_copied=4)
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.HistoryCopyCommand, pointer(data), 1; last_literals_copied=typemax(Int)) == CodecLZO.HistoryCopyCommand(3072, 3, 3; last_literals_copied=typemax(Int))

        # Long-distance copies
        data[1:3] = UInt8[0b00010001, 0b00000000, 0b00000000]
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.HistoryCopyCommand, pointer(data), 1) == CodecLZO.HistoryCopyCommand(16384, 3, 0) == CodecLZO.END_OF_STREAM_COMMAND
        data[3:5] = UInt8[0b00011111, 0b11111111, 0b11111111]
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.HistoryCopyCommand, pointer(data), 3) == CodecLZO.HistoryCopyCommand(49151, 9, 3)
        data[2:5] = UInt8[0b00011000, 0b00000001, 0b11111111, 0b11111111]
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.HistoryCopyCommand, pointer(data), 2) == CodecLZO.HistoryCopyCommand(49151, 10, 3)
        data[1:5] = UInt8[0b00011000, 0b00000000, 0b00000001, 0b11111111, 0b11111111]
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.HistoryCopyCommand, pointer(data), 1) == CodecLZO.HistoryCopyCommand(49151, 265, 3)

        # Medium-distance copies
        # Note: the full constructor with command length is used here because this can be more efficiently expressed in a 2-byte command, below.
        data[1:3] = UInt8[0b00100001, 0b00000000, 0b00000000]
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.HistoryCopyCommand, pointer(data), 1) == CodecLZO.HistoryCopyCommand(3, 1, 3, 0)
        data[3:5] = UInt8[0b00111111, 0b11111111, 0b11111111]
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.HistoryCopyCommand, pointer(data), 3) == CodecLZO.HistoryCopyCommand(16384, 33, 3)
        data[2:5] = UInt8[0b00100000, 0b00000001, 0b11111111, 0b11111111]
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.HistoryCopyCommand, pointer(data), 2) == CodecLZO.HistoryCopyCommand(16384, 34, 3)
        data[1:5] = UInt8[0b00100000, 0b00000000, 0b00000001, 0b11111111, 0b11111111]
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.HistoryCopyCommand, pointer(data), 1) == CodecLZO.HistoryCopyCommand(16384, 289, 3)
        
        # Short-distance copies
        data[1:2] = UInt8[0b01000000, 0b00000000]
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.HistoryCopyCommand, pointer(data), 1) == CodecLZO.HistoryCopyCommand(1, 3, 0)
        data[3:4] = UInt8[0b01111111, 0b11111111]
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.HistoryCopyCommand, pointer(data), 3) == CodecLZO.HistoryCopyCommand(2048, 4, 3)

        # Short-distance copies
        data[2:3] = UInt8[0b10000000, 0b00000000]
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.HistoryCopyCommand, pointer(data), 2) == CodecLZO.HistoryCopyCommand(1, 5, 0)
        data[4:5] = UInt8[0b11111111, 0b11111111]
        @test @GC.preserve data CodecLZO.unsafe_decode(CodecLZO.HistoryCopyCommand, pointer(data), 4) == CodecLZO.HistoryCopyCommand(2048, 8, 3)
    end
end

@testitem "encode HistoryCopyCommand" begin
    output = zeros(UInt8, 5)
    let
        # Length 2 copy from short distance
        for llc in 1:3
            CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(1, 2, 0; last_literals_copied=llc); last_literals_copied=llc)
            @test output[1:2] == UInt8[0b00000000,0b00000000]
        end
        CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(1024, 2, 3; last_literals_copied=1); last_literals_copied=1)
        @test output[1:2] == UInt8[0b00001111,0b11111111]

        # Bad LLC
        @test_throws ErrorException CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(1, 2, 0; last_literals_copied=1); last_literals_copied=0)

        # Length 3 copy from short distance
        CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(2049, 3, 0; last_literals_copied=4); last_literals_copied=4)
        @test output[1:2] == UInt8[0b00000000,0b00000000]
        CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(3072, 3, 3; last_literals_copied=typemax(Int)); last_literals_copied=typemax(Int))
        @test output[1:2] == UInt8[0b00001111,0b11111111]

        # Copies from long distances
        # Note that this is ambiguous with the short-to-medium command below and is never chosen by the encoder!
        # CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(16384, 3, 0))
        # @test output[1:3] == UInt8[0b00010001,0b00000000,0b00000000]
        CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(16385, 3, 0))
        @test output[1:3] == UInt8[0b00010001,0b00000100,0b00000000]
        CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(49151, 9, 3))
        @test output[1:3] == UInt8[0b00011111,0b11111111,0b11111111]
        CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(49151, 10, 3))
        @test output[1:4] == UInt8[0b00011000,0b00000001,0b11111111,0b11111111]
        CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(49151, 264, 3))
        @test output[1:4] == UInt8[0b00011000,0b11111111,0b11111111,0b11111111]
        CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(49151, 265, 3))
        @test output[1:5] == UInt8[0b00011000,0b00000000,0b00000001,0b11111111,0b11111111]

        # Copies from short to medium distances
        # Note that any length shorter than 9 bytes and closer than 2kB distance is more efficiently stored as a fixed 2-byte command
        CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(1, 9, 0))
        @test output[1:3] == UInt8[0b00100111,0b00000000,0b00000000]
        CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(16384, 33, 3))
        @test output[1:3] == UInt8[0b00111111,0b11111111,0b11111111]
        CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(16384, 34, 3))
        @test output[1:4] == UInt8[0b00100000,0b00000001,0b11111111,0b11111111]
        CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(16384, 288, 3))
        @test output[1:4] == UInt8[0b00100000,0b11111111,0b11111111,0b11111111]
        CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(16384, 289, 3))
        @test output[1:5] == UInt8[0b00100000,0b00000000,0b00000001,0b11111111,0b11111111]

        # Short copies from short distances
        CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(1, 3, 0))
        @test output[1:2] == UInt8[0b01000000,0b00000000]
        CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(2048, 4, 3))
        @test output[1:2] == UInt8[0b01111111,0b11111111]
        CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(1, 5, 0))
        @test output[1:2] == UInt8[0b10000000,0b00000000]
        CodecLZO.encode!(output, CodecLZO.HistoryCopyCommand(2048, 8, 3))
        @test output[1:2] == UInt8[0b11111111,0b11111111]
    end
end

@testitem "unsafe_encode HistoryCopyCommand" begin
    output = zeros(UInt8, 5)
    let
        # Length 2 copy from short distance
        for llc in 1:3
            @GC.preserve output @test 2 == CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(1, 2, 0; last_literals_copied=llc); last_literals_copied=llc)
            @test output[1:2] == UInt8[0b00000000,0b00000000]
        end
        @GC.preserve output @test 2 == CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(1024, 2, 3; last_literals_copied=1); last_literals_copied=1)
        @test output[1:2] == UInt8[0b00001111,0b11111111]

        # Bad LLC
        @test_throws ErrorException @GC.preserve output CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(1, 2, 0; last_literals_copied=1); last_literals_copied=0)

        # Length 3 copy from short distance
        @GC.preserve output @test 2 == CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(2049, 3, 0; last_literals_copied=4); last_literals_copied=4)
        @test output[1:2] == UInt8[0b00000000,0b00000000]
        @GC.preserve output @test 2 == CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(3072, 3, 3; last_literals_copied=typemax(Int)); last_literals_copied=typemax(Int))
        @test output[1:2] == UInt8[0b00001111,0b11111111]

        # Copies from long distances
        # Note that this is ambiguous with the short-to-medium command below and is never chosen by the encoder!
        # @GC.preserve output CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(16384, 3, 0))
        # @test output[1:3] == UInt8[0b00010001,0b00000000,0b00000000]
        @GC.preserve output @test 3 == CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(16385, 3, 0))
        @test output[1:3] == UInt8[0b00010001,0b00000100,0b00000000]
        @GC.preserve output @test 3 == CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(49151, 9, 3))
        @test output[1:3] == UInt8[0b00011111,0b11111111,0b11111111]
        @GC.preserve output @test 4 == CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(49151, 10, 3))
        @test output[1:4] == UInt8[0b00011000,0b00000001,0b11111111,0b11111111]
        @GC.preserve output @test 4 == CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(49151, 264, 3))
        @test output[1:4] == UInt8[0b00011000,0b11111111,0b11111111,0b11111111]
        @GC.preserve output @test 5 == CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(49151, 265, 3))
        @test output[1:5] == UInt8[0b00011000,0b00000000,0b00000001,0b11111111,0b11111111]

        # Copies from short to medium distances
        # Note that any length shorter than 9 bytes and closer than 2kB distance is more efficiently stored as a fixed 2-byte command
        @GC.preserve output @test 3 == CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(1, 9, 0))
        @test output[1:3] == UInt8[0b00100111,0b00000000,0b00000000]
        @GC.preserve output @test 3 == CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(16384, 33, 3))
        @test output[1:3] == UInt8[0b00111111,0b11111111,0b11111111]
        @GC.preserve output @test 4 == CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(16384, 34, 3))
        @test output[1:4] == UInt8[0b00100000,0b00000001,0b11111111,0b11111111]
        @GC.preserve output @test 4 == CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(16384, 288, 3))
        @test output[1:4] == UInt8[0b00100000,0b11111111,0b11111111,0b11111111]
        @GC.preserve output @test 5 == CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(16384, 289, 3))
        @test output[1:5] == UInt8[0b00100000,0b00000000,0b00000001,0b11111111,0b11111111]

        # Short copies from short distances
        @GC.preserve output @test 2 == CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(1, 3, 0))
        @test output[1:2] == UInt8[0b01000000,0b00000000]
        @GC.preserve output @test 2 == CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(2048, 4, 3))
        @test output[1:2] == UInt8[0b01111111,0b11111111]
        @GC.preserve output @test 2 == CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(1, 5, 0))
        @test output[1:2] == UInt8[0b10000000,0b00000000]
        @GC.preserve output @test 2 == CodecLZO.unsafe_encode!(pointer(output), CodecLZO.HistoryCopyCommand(2048, 8, 3))
        @test output[1:2] == UInt8[0b11111111,0b11111111]
    end
end

@testitem "ModuloBuffer constructor" begin
    using Random
    # TODO fix this when LTS is bumped past 1.7
    rng = Random.MersenneTwister(42)

    # constructor
    let
        # Type and capacity
        for T in (UInt8, Int, String, Union{Float64,Missing}, Nothing)
            n = rand(rng, 0:1000)
            mb = CodecLZO.ModuloBuffer{T}(n)
            @test eltype(mb) == T
            @test CodecLZO.capacity(mb) == n
            @test length(mb) == 0
            @test isempty(mb)
        end

        # limiting case
        mb = CodecLZO.ModuloBuffer{Nothing}(0)
        @test eltype(mb) == Nothing
        @test CodecLZO.capacity(mb) == 0
        @test length(mb) == 0
        @test isempty(mb)

        # Iterable
        mb = CodecLZO.ModuloBuffer(rand(rng, UInt8, 10))
        @test eltype(mb) == UInt8
        @test CodecLZO.capacity(mb) == 10
        @test length(mb) == 10
        @test CodecLZO.isfull(mb)
    end
end

@testitem "ModuloBuffer pushing and popping" begin
    let
        # size, length, and capacity with push! and pop!
        mb = CodecLZO.ModuloBuffer{UInt8}(10)
        @test CodecLZO.capacity(mb) == 10
        @test size(mb) == (0,)
        @test length(mb) == 0

        @test typeof(push!(mb, 1)) == typeof(mb)
        @test CodecLZO.capacity(mb) == 10
        @test size(mb) == (1,)
        @test length(mb) == 1

        @test pop!(mb) == 1
        @test CodecLZO.capacity(mb) == 10
        @test size(mb) == (0,)
        @test length(mb) == 0

        @test_throws ArgumentError pop!(mb)

        # pushfirst! and popfirst! behavior
        @test typeof(pushfirst!(mb, 3, 2, 1)) == typeof(mb)
        @test length(mb) == 3
        @test CodecLZO.capacity(mb) == 10
        @test popfirst!(mb) == 3
        @test length(mb) == 2
        @test CodecLZO.capacity(mb) == 10
        @test pop!(mb) == 1
        @test popfirst!(mb) == 2

        @test_throws ArgumentError popfirst!(mb)
    end
end

@testitem "ModuloBuffer setindex and getindex" begin
    let
        mb = CodecLZO.ModuloBuffer{UInt8}(10)

        # getindex and setindex! behavior
        @test_throws BoundsError mb[1] = 1

        push!(mb, 1)
        @test mb[1] == 1
        push!(mb, 2)
        @test mb[2] == 2
        mb[1] = 3
        @test mb[1] == 3
        @test CodecLZO.capacity(mb) == 10
        popfirst!(mb)
        @test mb[1] == 2
    end
end

@testitem "ModuloBuffer empty" begin
    let
        mb = CodecLZO.ModuloBuffer{UInt8}(10)

        # empty! and isempty behavior
        @test isempty(mb)
        push!(mb, 1)
        @test length(mb) > 0
        @test !isempty(mb)
        @test typeof(empty!(mb)) == typeof(mb)
        @test length(mb) == 0
        @test isempty(mb)
        @test CodecLZO.capacity(mb) == 10
    end
end

@testitem "ModuloBuffer append and prepend" begin
    let
        mb = CodecLZO.ModuloBuffer{UInt8}(10)

        # append! and prepend! behavior
        @test typeof(append!(mb, [1, 2, 3])) == typeof(mb)
        @test length(mb) == 3
        @test CodecLZO.capacity(mb) == 10
        @test mb[1:3] == [1, 2, 3]
        @test typeof(append!(mb, [4, 5], [6])) == typeof(mb)
        @test length(mb) == 6
        @test mb[1:6] == [1, 2, 3, 4, 5, 6]
        
        empty!(mb)
        @test typeof(prepend!(mb, [1, 2, 3])) == typeof(mb)
        @test length(mb) == 3
        @test CodecLZO.capacity(mb) == 10
        @test mb[1:3] == [1, 2, 3]
        @test typeof(prepend!(mb, [4, 5], [6])) == typeof(mb)
        @test length(mb) == 6
        @test mb[1:6] == [4, 5, 6, 1, 2, 3]
    end
end

@testitem "ModuloBuffer modulo indexing and periodic boundary conditions" begin
    let 
        mb = CodecLZO.ModuloBuffer{UInt8}(10)

        # modulo indexing
        append!(mb, [1, 2, 3])
        @test mb[1] == mb[CodecLZO.capacity(mb) + 1] == 1
        @test mb[2:3] == mb[12:13] == mb[-8:-7] == [2, 3]
        @test_throws BoundsError mb[4]
        @test_throws BoundsError mb[0]
        @test_throws BoundsError mb[14]

        # periodic boundary conditions
        append!(mb, 4:10)
        @test length(mb) == CodecLZO.capacity(mb) == 10
        @test mb[1] == mb[11] == mb[-9] == 1
        @test mb[10] == mb[20] == mb[0] == 10
        push!(mb, 11)
        @test length(mb) == 10
        @test mb[1] == mb[11] == mb[-9] == 2
        @test mb[10] == mb[20] == mb[0] == 11
        pushfirst!(mb, 1)
        @test mb[1] == mb[11] == mb[-9] == 1
        @test mb[10] == mb[20] == mb[0] == 10
        push!(mb, 11)
        @test popfirst!(mb) == 2
        @test length(mb) == 9
    end
end

@testitem "ModuloBuffer oversized append and prepend" begin
    let
        mb = CodecLZO.ModuloBuffer{UInt8}(10)

        # oversize append! and prepend!
        append!(mb, 1:20)
        @test mb[1:10] == 11:20
        prepend!(mb, 1:20)
        @test mb[1:10] == 1:10
    end
end

@testitem "ModuloBuffer resizing" begin
    let
        mb = CodecLZO.ModuloBuffer{UInt8}(10)
        append!(mb, 1:10)

        # resize! and resize_front!
        @test typeof(resize!(mb, 5)) == typeof(mb)
        @test length(mb) == CodecLZO.capacity(mb) == 5
        @test mb[1:5] == 1:5
        resize!(mb, 10)
        @test length(mb) == 5
        @test CodecLZO.capacity(mb) == 10
        @test mb[1:5] == 1:5

        append!(mb, 6:10)
        @test typeof(CodecLZO.resize_front!(mb, 5)) == typeof(mb)
        @test length(mb) == CodecLZO.capacity(mb) == 5
        @test mb[1:5] == 6:10
        CodecLZO.resize_front!(mb, 10)
        @test length(mb) == 5
        @test CodecLZO.capacity(mb) == 10
        @test mb[1:5] == 6:10
    end
end

@testitem "ModuloBuffer noninteger indexing" begin
    let
        mb = CodecLZO.ModuloBuffer{UInt8}(10)
        append!(mb, 6:10)

        # Nonstandard indexing
        @test firstindex(mb) == 1
        @test lastindex(mb) == 5
        prepend!(mb, 1:5)
        @test lastindex(mb) == 10
        @test mb[1] == mb[begin]
        @test mb[10] == mb[end]
        @test mb[:] == mb[begin:end] == mb[1:10] == mb[-9:0] == mb[11:20] == 1:10
        @test mb[1:20] == repeat(1:10, 2)
    end
end

@testitem "ModuloBuffer shift_copy!" begin
    let 
        mb = CodecLZO.ModuloBuffer{UInt8}(10)
        sink = UInt8[]
        source = Vector{UInt8}(1:100)

        # shift nothing
        @test CodecLZO.shift_copy!(mb, source, 1, sink, 1, 0) == (0,0)
        @test length(mb) == 0
        @test length(sink) == 0

        # shift less than capacity, no push to sink
        @test CodecLZO.shift_copy!(mb, source, 1, sink, 1, 5) == (5,0)
        @test length(mb) == 5
        @test length(sink) == 0
        @test mb[:] == 1:5

        # shift more than remaining, sink blocks
        @test CodecLZO.shift_copy!(mb, source, 6, sink, 1) == (5,0)
        @test length(mb) == 10
        @test length(sink) == 0
        @test mb[:] == 1:10
        @test CodecLZO.shift_copy!(mb, source, 11, sink, 1) == (0,0)

        # shift more than remaining, sink takes partial
        resize!(mb, 15)
        resize!(sink, 2)
        @test CodecLZO.shift_copy!(mb, source, 11, sink, 1) == (7,2)
        @test mb[:] == 3:17
        @test sink == 1:2

    end
end


# @testitem "LZO1X1CompressorCodec constructor" begin
#     c1 = LZO1X1CompressorCodec()
#     c2 = LZOCompressorCodec()
#     @test true
# end

# @testitem "LZO1X1CompressorCodec transcode" begin
#     using TranscodingStreams
#     using Random
    
#     let
#         small_array = UInt8.(collect(0:255)) # no repeats, so should be one long literal
#         small_array_compressed = transcode(LZOCompressorCodec, small_array)
#         @test length(small_array_compressed) == 2 + length(small_array) + 3

#         # The first command should be a copy of the entire 256-byte literal.
#         # The 0b0000XXXX command copies literals with a length encoding of either 3 + XXXX or 18 + (zero bytes following command) * 255 + (non-zero trailing byte).
#         @test small_array_compressed[1:2] == UInt8[0b00000000, 256 - 18]

#         # The last command is boilerplate: a copy of 3 bytes from distance 16384
#         @test small_array_compressed[end-2:end] == UInt8[0b00010001, 0, 0]
        
#         double_small_array = vcat(small_array, small_array) # this should add an additional 5 bytes to the literal because the skip logic, followed by a long copy command
#         double_small_array_compressed = transcode(LZOCompressorCodec, double_small_array)
#         @test length(double_small_array_compressed) == 2 + (length(small_array) + 5) + 4 + 3

#     end
# end

@run_package_tests verbose = true