using CodecLZO
using TestItemRunner


@testitem "HashMap setindex!, getindex, replace!, and empty!" begin
    h = CodecLZO.HashMap{UInt8,Int}(8, UInt8(2^8 - 45)) # that's prime
    @test h[0x01] == 0
    h[0x01] = 1
    @test h[0x01] == 1
    # overwrite
    h[0x01] = 2
    @test h[0x01] == 2
    # replace
    @test replace!(h, 0x01, 3) == 2
    @test h[0x01] == 3
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
        @test_throws CodecLZO.CommandEncodeException command_length(CodecLZO.NULL_COMMAND)

        # first literal with copy command
        cp = CommandPair(true, false, 100, 100, 4)
        @test_throws CodecLZO.CommandEncodeException command_length(cp)

        # negative literal length
        cp = CommandPair(false, false, 100, 100, -1)
        @test_throws CodecLZO.CommandEncodeException command_length(cp)

        # small copy
        cp = CommandPair(false, false, 100, 1, 100)
        @test_throws CodecLZO.CommandEncodeException command_length(cp)

        # zero lookback
        cp = CommandPair(false, false, 0, 100, 100)
        @test_throws CodecLZO.CommandEncodeException command_length(cp)

        # illegal length-2 copies
        # bad last literals
        cp = CommandPair(false, false, 100, 2, 100)
        @test_throws CodecLZO.CommandEncodeException command_length(cp)
        @test_throws CodecLZO.CommandEncodeException command_length(cp, 4)
        # lookback too long
        cp = CommandPair(false, false, 1<<10 + 1, 2, 100)
        @test_throws CodecLZO.CommandEncodeException command_length(cp, 1)

        # small first literals
        cp = CommandPair(true, false, 0, 0, 0)
        @test command_length(cp) == 0 + 1
        cp = CommandPair(true, false, 0, 0, 4)
        @test command_length(cp) == 0 + 1
        cp = CommandPair(true, false, 0, 0, 0xff - 17)
        @test command_length(cp) == 0 + 1

        # longer first literals with run encoding
        cp = CommandPair(true, false, 0, 0, 0xff - 16)
        @test command_length(cp) == 0 + 2
        cp = CommandPair(true, false, 0, 0, 273)
        @test command_length(cp) == 0 + 2
        cp = CommandPair(true, false, 0, 0, 274)
        @test command_length(cp) == 0 + 3

        # length-2 copies, short literals
        cp = CommandPair(false, false, 100, 2, 3)
        @test command_length(cp, 1) == 2 + 0
        # length-2 copies, long literals
        cp = CommandPair(false, false, 100, 2, 274)
        @test command_length(cp, 1) == 2 + 3
        # length-3 copies (weird)
        cp = CommandPair(false, false, 2049, 3, 274)
        @test command_length(cp, 4) == 2 + 3
        # short, nearby copies
        cp = CommandPair(false, false, 100, 8, 274)
        @test command_length(cp, 4) == 2 + 3
        # short, nearby copies with run-encoded longer literals
        cp = CommandPair(false, false, 100, 8, 18)
        @test command_length(cp, 4) == 2 + 1
        cp = CommandPair(false, false, 100, 8, 19)
        @test command_length(cp, 4) == 2 + 2
        cp = CommandPair(false, false, 100, 8, 19)
        @test command_length(cp, 4) == 2 + 2
        cp = CommandPair(false, false, 100, 8, 273)
        @test command_length(cp, 4) == 2 + 2
        cp = CommandPair(false, false, 100, 8, 274)
        @test command_length(cp, 4) == 2 + 3

        # longer nearby copies with run encoding
        cp = CommandPair(false, false, 1 << 11 + 1, 33, 274)
        @test command_length(cp, 4) == 3 + 3
        cp = CommandPair(false, false, 1 << 11 + 1, 34, 274)
        @test command_length(cp, 4) == 4 + 3

        # longer long-distance copies with run encoding
        cp = CommandPair(false, false, 1 << 14 + 1, 9, 274)
        @test command_length(cp, 4) == 3 + 3
        cp = CommandPair(false, false, 1 << 14 + 1, 10, 274)
        @test command_length(cp, 4) == 4 + 3

        # EOS
        cp = CodecLZO.END_OF_STREAM_COMMAND
        @test command_length(cp) == 3

        # EOS Lookalike
        cp = CommandPair(false, false, CodecLZO.END_OF_STREAM_LOOKBACK, CodecLZO.END_OF_STREAM_COPY_LENGTH, 0)
        @test command_length(cp) == 3

        # Bad EOS
        # first literal
        cp = CommandPair(true, true, CodecLZO.END_OF_STREAM_LOOKBACK, CodecLZO.END_OF_STREAM_COPY_LENGTH, 0)
        @test_throws CodecLZO.CommandEncodeException command_length(cp)
        # bad lookback
        cp = CommandPair(false, true, CodecLZO.END_OF_STREAM_LOOKBACK + 1, CodecLZO.END_OF_STREAM_COPY_LENGTH, 0)
        @test_throws CodecLZO.CommandEncodeException command_length(cp)
        # bad copy length
        cp = CommandPair(false, true, CodecLZO.END_OF_STREAM_LOOKBACK, CodecLZO.END_OF_STREAM_COPY_LENGTH+1, 0)
        @test_throws CodecLZO.CommandEncodeException command_length(cp)
        # post-copy literals
        cp = CommandPair(false, true, CodecLZO.END_OF_STREAM_LOOKBACK, CodecLZO.END_OF_STREAM_COPY_LENGTH, 1)
        @test_throws CodecLZO.CommandEncodeException command_length(cp)

    end
end

@testitem "CommandPair encode" begin
    using CodecLZO: CommandPair, encode!, encode_literal_copy!, encode_history_copy!

    let
        # No space to write
        data = UInt8[]
        c = CommandPair(true, false, 0, 0, 4)
        @test encode_literal_copy!(data, c, 1) == 0
        @test encode!(data, c, 1) == 0

        # valid first literals
        resize!(data, 2)
        c = CommandPair(true, false, 0, 0, 4)
        @test encode_literal_copy!(data, c, 1) == 1
        @test encode!(data, c, 1) == 1
        @test data[1:1] == UInt8[0b00010101]

        # offset
        fill!(data, zero(UInt8))
        @test encode_literal_copy!(data, c, 2) == 1
        @test encode!(data, c, 2) == 1
        @test data[1:2] == UInt8[0b00000000, 0b00010101]

        c = CommandPair(true, false, 0, 0, 238)
        @test encode_literal_copy!(data, c, 1) == 1
        @test encode!(data, c, 1) == 1
        @test data[1:1] == UInt8[0b11111111]

        # Run-encoded first literal
        c = CommandPair(true, false, 0, 0, 239)
        @test encode_literal_copy!(data, c, 1) == 2
        @test encode!(data, c, 1) == 2
        @test data[1:2] == UInt8[0b00000000, 0b11011101]
        c = CommandPair(true, false, 0, 0, 273)
        @test encode_literal_copy!(data, c, 1) == 2
        @test encode!(data, c, 1) == 2
        @test data[1:2] == UInt8[0b00000000, 0b11111111]

        # No space to write
        c = CommandPair(true, false, 0, 0, 274)
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
        c = CommandPair(false, false, 1, 2, 3)
        @test encode_history_copy!(data, c, 1, 1) == 2
        @test data[1:2] == UInt8[0b00000011, 0b00000000]
        @test encode!(data, c, 1; last_literal_length=1) == 2
        @test data[1:2] == UInt8[0b00000011, 0b00000000]

        # length-2 copy with long literal
        c = CommandPair(false, false, 1024, 2, 4)
        @test encode_history_copy!(data, c, 1, 1) == 2
        @test data[1:2] == UInt8[0b00001100, 0b11111111]
        @test encode!(data, c, 1; last_literal_length=1) == 3
        @test data[1:3] == UInt8[0b00001100, 0b11111111, 0b00000001]

        # length-2 copy with invalid last literals
        @test_throws CodecLZO.CommandEncodeException encode_history_copy!(data, c, 1, 0)
        @test_throws CodecLZO.CommandEncodeException encode!(data, c, 1; last_literal_length=0)
        @test_throws CodecLZO.CommandEncodeException encode_history_copy!(data, c, 1, 4)
        @test_throws CodecLZO.CommandEncodeException encode!(data, c, 1; last_literal_length=4)

        # length-2 copy with too long a lookback
        c = CommandPair(false, false, 1025, 2, 4)
        @test_throws CodecLZO.CommandEncodeException encode_history_copy!(data, c, 1, 1)
        @test_throws CodecLZO.CommandEncodeException encode!(data, c, 1; last_literal_length=1)

        # length-2 copy with no space
        c = CommandPair(false, false, 1024, 2, 4)
        @test encode_history_copy!(UInt8[], c, 1, 1) == 0
        @test encode!(UInt8[], c, 1; last_literal_length=1) == 0

        # length-3 short-distance copy with short literal
        c = CommandPair(false, false, 1, 3, 3)
        @test encode_history_copy!(data, c, 1, 0) == 2
        @test data[1:2] == UInt8[0b01000011, 0b00000000]
        @test encode!(data, c, 1) == 2
        @test data[1:2] == UInt8[0b01000011, 0b00000000]

        # length-3 short-distance copy with long literal
        c = CommandPair(false, false, 2048, 3, 4)
        @test encode_history_copy!(data, c, 1, 0) == 2
        @test data[1:2] == UInt8[0b01011100, 0b11111111]
        @test encode!(data, c, 1) == 3
        @test data[1:3] == UInt8[0b01011100, 0b11111111, 0b00000001]

        # length-3 short-distance copy with no space
        c = CommandPair(false, false, 1, 3, 3)
        @test encode_history_copy!(UInt8[], c, 1, 0) == 0
        @test encode!(UInt8[], c, 1; last_literal_length=0) == 0

        # length-3 medium-distance copy with short literal
        c = CommandPair(false, false, 2049, 3, 3)
        @test encode_history_copy!(data, c, 1, 4) == 2
        @test data[1:2] == UInt8[0b00000011, 0b00000000]
        @test encode!(data, c, 1; last_literal_length=4) == 2
        @test data[1:2] == UInt8[0b00000011, 0b00000000]

        # length-3 medium-distance copy with long literal
        c = CommandPair(false, false, 3072, 3, 4)
        @test encode_history_copy!(data, c, 1, 4) == 2
        @test data[1:2] == UInt8[0b00001100, 0b11111111]
        @test encode!(data, c, 1; last_literal_length=4) == 3
        @test data[1:3] == UInt8[0b00001100, 0b11111111, 0b00000001]

        # length-3 medium-distance copy with invalid last literal
        resize!(data, 4)
        c = CommandPair(false, false, 3072, 3, 4)
        @test encode_history_copy!(data, c, 1, 0) == 3
        @test data[1:3] == UInt8[0b00100001, 0b11111100, 0b00101111]
        @test encode!(data, c, 1; last_literal_length=0) == 4
        @test data[1:4] == UInt8[0b00100001, 0b11111100, 0b00101111, 0b00000001]

        # length-3 medium-distance copy with no space
        c = CommandPair(false, false, 2049, 3, 3)
        @test encode_history_copy!(UInt8[], c, 1, 4) == 0
        @test encode!(UInt8[], c, 1; last_literal_length=4) == 0

        # length-4 copy with short literal
        c = CommandPair(false, false, 1, 4, 3)
        @test encode_history_copy!(data, c, 1, 0) == 2
        @test data[1:2] == UInt8[0b01100011, 0b00000000]
        @test encode!(data, c, 1) == 2
        @test data[1:2] == UInt8[0b01100011, 0b00000000]

        # length-4 copy with long literal
        c = CommandPair(false, false, 2048, 4, 4)
        @test encode_history_copy!(data, c, 1, 0) == 2
        @test data[1:2] == UInt8[0b01111100, 0b11111111]
        @test encode!(data, c, 1) == 3
        @test data[1:3] == UInt8[0b01111100, 0b11111111, 0b00000001]

        # length-4 copy with long lookback
        c = CommandPair(false, false, 2049, 4, 4)
        @test encode_history_copy!(data, c, 1, 0) == 3
        @test data[1:3] == UInt8[0b00100010, 0b00000000, 0b00100000]
        @test encode!(data, c, 1) == 4
        @test data[1:4] == UInt8[0b00100010, 0b00000000, 0b00100000, 0b00000001]

        # length-4 copy with no space
        c = CommandPair(false, false, 2048, 4, 4)
        @test encode_history_copy!(UInt8[], c, 1, 0) == 0
        @test encode!(UInt8[], c, 1; last_literal_length=0) == 0

        # length-5-8 copy with short literal
        c = CommandPair(false, false, 1, 5, 3)
        @test encode_history_copy!(data, c, 1, 0) == 2
        @test data[1:2] == UInt8[0b10000011, 0b00000000]
        @test encode!(data, c, 1) == 2
        @test data[1:2] == UInt8[0b10000011, 0b00000000]

        # length-5-8 copy with long literal
        c = CommandPair(false, false, 2048, 8, 4)
        @test encode_history_copy!(data, c, 1, 0) == 2
        @test data[1:2] == UInt8[0b11111100, 0b11111111]
        @test encode!(data, c, 1) == 3
        @test data[1:3] == UInt8[0b11111100, 0b11111111, 0b00000001]

        # length-5-8 copy with long lookback
        c = CommandPair(false, false, 2049, 8, 4)
        @test encode_history_copy!(data, c, 1, 0) == 3
        @test data[1:3] == UInt8[0b00100110, 0b00000000, 0b00100000]
        @test encode!(data, c, 1) == 4
        @test data[1:4] == UInt8[0b00100110, 0b00000000, 0b00100000, 0b00000001]

        # length-5-8 copy with no space
        c = CommandPair(false, false, 1, 5, 3)
        @test encode_history_copy!(UInt8[], c, 1, 0) == 0
        @test encode!(UInt8[], c, 1; last_literal_length=0) == 0

        # short lookback with short literal
        c = CommandPair(false, false, 1, 9, 1)
        @test encode_history_copy!(data, c, 1, 0) == 3
        @test data[1:3] == UInt8[0b00100111, 0b00000001, 0b00000000]
        @test encode!(data, c, 1) == 3
        @test data[1:3] == UInt8[0b00100111, 0b00000001, 0b00000000]

        # short lookback with short literal and run-encoded length
        c = CommandPair(false, false, 1, 34, 3)
        @test encode_history_copy!(data, c, 1, 0) == 4
        @test data[1:4] == UInt8[0b00100000, 0b00000001, 0b00000011, 0b00000000]
        @test encode!(data, c, 1) == 4
        @test data[1:4] == UInt8[0b00100000, 0b00000001, 0b00000011, 0b00000000]

        # short lookback with long literal and run-encoded length
        resize!(data, 6)
        c = CommandPair(false, false, 16384, 289, 4)
        @test encode_history_copy!(data, c, 1, 0) == 5
        @test data[1:5] == UInt8[0b00100000, 0b00000000, 0b00000001, 0b11111100, 0b11111111]
        @test encode!(data, c, 1) == 6
        @test data[1:6] == UInt8[0b00100000, 0b00000000, 0b00000001, 0b11111100, 0b11111111, 0b00000001]

        # short lookback with no space
        c = CommandPair(false, false, 1, 9, 1)
        @test encode_history_copy!(UInt8[], c, 1, 0) == 0
        @test encode!(UInt8[], c, 1; last_literal_length=0) == 0

        # long lookback with short literal
        c = CommandPair(false, false, 16385, 3, 1)
        @test encode_history_copy!(data, c, 1, 0) == 3
        @test data[1:3] == UInt8[0b00010001, 0b00000101, 0b00000000]
        @test encode!(data, c, 1) == 3
        @test data[1:3] == UInt8[0b00010001, 0b00000101, 0b00000000]

        # long lookback with short literal and run-encoded length
        c = CommandPair(false, false, 16385, 10, 3)
        @test encode_history_copy!(data, c, 1, 0) == 4
        @test data[1:4] == UInt8[0b00010000, 0b00000001, 0b00000111, 0b00000000]
        @test encode!(data, c, 1) == 4
        @test data[1:4] == UInt8[0b00010000, 0b00000001, 0b00000111, 0b00000000]

        # long lookback with long literal and run-encoded length
        c = CommandPair(false, false, 49151, 10, 4)
        @test encode_history_copy!(data, c, 1, 0) == 4
        @test data[1:4] == UInt8[0b00011000, 0b00000001, 0b11111100, 0b11111111]
        @test encode!(data, c, 1) == 5
        @test data[1:5] == UInt8[0b00011000, 0b00000001, 0b11111100, 0b11111111, 0b00000001]

        # long lookback with no space
        c = CommandPair(false, false, 16385, 3, 1)
        @test encode_history_copy!(UInt8[], c, 1, 0) == 0
        @test encode!(UInt8[], c, 1; last_literal_length=0) == 0

        # long lookback, run-encoded literal, run-encoded length (as big as it gets!)
        c = CommandPair(false, false, 49151, 265, 4)
        @test encode_history_copy!(data, c, 1, 0) == 5
        @test data[1:5] == UInt8[0b00011000, 0b00000000, 0b00000001, 0b11111100, 0b11111111]
        @test encode!(data, c, 1) == 6
        @test data[1:6] == UInt8[0b00011000, 0b00000000, 0b00000001, 0b11111100, 0b11111111, 0b00000001]

        # too long a lookback
        c = CommandPair(false, false, 49152, 265, 4)
        @test_throws CodecLZO.CommandEncodeException encode_history_copy!(data, c, 1, 0)

        # EOS
        c = CodecLZO.END_OF_STREAM_COMMAND
        @test encode_history_copy!(data, c, 1, 0) == 3
        @test data[1:3] == CodecLZO.END_OF_STREAM_DATA

        # EOS-lookalike
        c = CommandPair(false, false, CodecLZO.END_OF_STREAM_LOOKBACK, CodecLZO.END_OF_STREAM_COPY_LENGTH, 0)
        @test encode_history_copy!(data, c, 1, 0) == 3
        @test data[1:3] == UInt8[0b00100001, 0b11111100, 0b11111111]

    end
end

@testitem "CommandPair decode" begin
    using CodecLZO: CommandPair, decode_literal_copy, decode_history_copy, decode, NULL_COMMAND, END_OF_STREAM_DATA, END_OF_STREAM_COMMAND, END_OF_STREAM_LOOKBACK, END_OF_STREAM_COPY_LENGTH

    let 
        # first literal
        # bad command
        data = zeros(UInt8, 1)
        data[1] = 0b00010000
        @test_throws CodecLZO.CommandDecodeException decode_literal_copy(data, 1, true)
        @test_throws CodecLZO.CommandDecodeException decode(CommandPair, data, 1; first_literal=true)
        # short first literal
        data[1] = 0b00010001
        @test decode_literal_copy(data, 1, true) == (1, 0)
        @test decode(CommandPair, data, 1; first_literal=true) == (1, CommandPair(true, false, 0, 0, 0))
        # long first literal, too few bytes
        data[1] = 0b00000000
        @test decode_literal_copy(data, 1, true) == (0, 0)
        @test decode(CommandPair, data, 1; first_literal=true) == (0, NULL_COMMAND)
        # long first literal
        resize!(data, 2)
        data[1:2] = UInt8[0b00000000, 0b00000001]
        @test decode_literal_copy(data, 1, true) == (2, 19)
        @test decode(CommandPair, data, 1; first_literal=true) == (2, CommandPair(true, false, 0, 0, 19))
        # offset long first literal
        @test decode_literal_copy(data, 2, true) == (1, 4)
        @test decode(CommandPair, data, 2; first_literal=true) == (1, CommandPair(true, false, 0, 0, 4))
        # run-encoded first literal, too few byes
        data[2] = 0b00000000
        @test decode_literal_copy(data, 1, true) == (0, 0)
        @test decode(CommandPair, data, 1; first_literal=true) == (0, NULL_COMMAND)
        # run-encoded first literal
        resize!(data, 3)
        data[3] = 0b00000001
        @test decode_literal_copy(data, 1, true) == (3, 274)
        @test decode(CommandPair, data, 1; first_literal=true) == (3, CommandPair(true, false, 0, 0, 274))

        # EOS
        data[1:3] = END_OF_STREAM_DATA
        @test decode_history_copy(data, 1, 0) == (3, true, END_OF_STREAM_LOOKBACK, END_OF_STREAM_COPY_LENGTH, 0)
        @test decode(CommandPair, data, 1; first_literal=false) == (3, END_OF_STREAM_COMMAND)
        
        # EOS as first literal is interpreted as a literal copy, interestingly enough
        @test decode(CommandPair, data, 1; first_literal=true) == (1, CommandPair(true, false, 0, 0, 0))

        # 2-byte history copies
        data[1:2] = UInt8[0b00000001, 0b00000000]
        @test decode_history_copy(data, 1, 1) == (2, false, 1, 2, 1)
        @test decode(CommandPair, data, 1; last_literal_length=1) == (2, CommandPair(false, false, 1, 2, 1))
        data[1:2] = UInt8[0b00001111, 0b11111111]
        @test decode_history_copy(data, 1, 3) == (2, false, 1024, 2, 3)
        @test decode(CommandPair, data, 1; last_literal_length=1) == (2, CommandPair(false, false, 1024, 2, 3))
        # 2-byte history copy with no last literals
        @test_throws CodecLZO.CommandDecodeException decode_history_copy(data, 1, 0)
        # 2-byte history with long literal following
        data[1:3] = UInt8[0b00000000, 0b00000000, 0b00000001]
        @test decode_history_copy(data, 1, 1) == (2, false, 1, 2, 0)
        @test decode(CommandPair, data, 1; last_literal_length=1) == (3, CommandPair(false, false, 1, 2, 4))

        # 3-byte history copies
        data[1:2] = UInt8[0b00000001, 0b00000000]
        @test decode_history_copy(data, 1, 4) == (2, false, 2049, 3, 1)
        @test decode(CommandPair, data, 1; last_literal_length=4) == (2, CommandPair(false, false, 2049, 3, 1))
        data[1:2] = UInt8[0b00001111, 0b11111111]
        @test decode_history_copy(data, 1, typemax(Int)) == (2, false, 3072, 3, 3)
        @test decode(CommandPair, data, 1; last_literal_length=typemax(Int)) == (2, CommandPair(false, false, 3072, 3, 3))
        # 3-byte history copy with bad last literals
        @test_throws CodecLZO.CommandDecodeException decode_history_copy(data, 1, 0)
        # 3-byte history copy with long literal following
        data[1:3] = UInt8[0b00000000, 0b00000000, 0b00000001]
        @test decode_history_copy(data, 1, 4) == (2, false, 2049, 3, 0)
        @test decode(CommandPair, data, 1; last_literal_length=4) == (3, CommandPair(false, false, 2049, 3, 4))

        # short-distance very short history copies
        data[1:2] = UInt8[0b01000001, 0b00000000]
        @test decode_history_copy(data, 1, 0) == (2, false, 1, 3, 1)
        @test decode(CommandPair, data, 1) == (2, CommandPair(false, false, 1, 3, 1))
        data[1:2] = UInt8[0b01111111, 0b11111111]
        @test decode_history_copy(data, 1, 0) == (2, false, 2048, 4, 3)
        @test decode(CommandPair, data, 1) == (2, CommandPair(false, false, 2048, 4, 3))
        # with long literal
        data[1:3] = UInt8[0b01000000, 0b00000000, 0b00000001]
        @test decode_history_copy(data, 1, 0) == (2, false, 1, 3, 0)
        @test decode(CommandPair, data, 1) == (3, CommandPair(false, false, 1, 3, 4))
        
        # short-distance short history copies
        data[1:2] = UInt8[0b10000001, 0b00000000]
        @test decode_history_copy(data, 1, 0) == (2, false, 1, 5, 1)
        @test decode(CommandPair, data, 1) == (2, CommandPair(false, false, 1, 5, 1))
        data[1:2] = UInt8[0b11111111, 0b11111111]
        @test decode_history_copy(data, 1, 0) == (2, false, 2048, 8, 3)
        @test decode(CommandPair, data, 1) == (2, CommandPair(false, false, 2048, 8, 3))
        # with long literal
        data[1:3] = UInt8[0b10000000, 0b00000000, 0b00000001]
        @test decode_history_copy(data, 1, 0) == (2, false, 1, 5, 0)
        @test decode(CommandPair, data, 1) == (3, CommandPair(false, false, 1, 5, 4))

        # medium-distance history copies
        data[1:3] = UInt8[0b00100001, 0b00000001, 0b00000000]
        @test decode_history_copy(data, 1, 0) == (3, false, 1, 3, 1)
        @test decode(CommandPair, data, 1) == (3, CommandPair(false, false, 1, 3, 1))
        data[1:3] = UInt8[0b00111111, 0b11111111, 0b11111111]
        @test decode_history_copy(data, 1, 0) == (3, false, 16384, 33, 3)
        @test decode(CommandPair, data, 1) == (3, CommandPair(false, false, 16384, 33, 3))
        # run-encoded length
        resize!(data, 4)
        data[1:4] = UInt8[0b00100000, 0b00000001, 0b11111111, 0b11111111]
        @test decode_history_copy(data, 1, 0) == (4, false, 16384, 34, 3)
        @test decode(CommandPair, data, 1) == (4, CommandPair(false, false, 16384, 34, 3))

        # long-distance history copies
        data[1:3] = UInt8[0b00010001, 0b00000001, 0b00000000]
        @test decode_history_copy(data, 1, 0) == (3, false, 16384, 3, 1)
        @test decode(CommandPair, data, 1) == (3, CommandPair(false, false, 16384, 3, 1))
        data[1:3] = UInt8[0b00011111, 0b11111111, 0b11111111]
        @test decode_history_copy(data, 1, 0) == (3, false, 49151, 9, 3)
        @test decode(CommandPair, data, 1) == (3, CommandPair(false, false, 49151, 9, 3))
        # run-encoded length
        resize!(data, 4)
        data[1:4] = UInt8[0b00011000, 0b00000001, 0b11111111, 0b11111111]
        @test decode_history_copy(data, 1, 0) == (4, false, 49151, 10, 3)
        @test decode(CommandPair, data, 1) == (4, CommandPair(false, false, 49151, 10, 3))

        # run-encoded everything (as long as it gets)
        resize!(data, 8)
        data[1:8] = UInt8[0b00011000, 0b00000000, 0b11111111, 0b11111100, 0b11111111, 0b00000000, 0b00000000, 0b11111111]
        @test decode_history_copy(data, 1, 0) == (5, false, 49151, 519, 0)
        @test decode(CommandPair, data, 1) == (8, CommandPair(false, false, 49151, 519, 528))
    end
end

@testitem "Corner case compression round trip" begin
    import CodecLZO.LZO: lzo_compress, lzo_decompress
    let 
        # this covers a corner case where the command encoding the run length of the last literal called for one too many bytes
        a = UInt8[1,2,1,2,1,2,9,8,7,6,5,4,3,2,1,0]
        c = transcode(LZOCompressor, a)
        @test a == lzo_decompress(c)

        # this covers a corner case where a search for the next history match in the input overran the end of the input buffer and caused a phantom match
        a = UInt8[1,2,3,4,5,6,7,8,0,9,0,0,0,1,2,3,4,5,6,7,8,9]
        c = transcode(LZOCompressor, a)
        @test a == lzo_decompress(c)
    end
end

@testitem "Canterbury Corpus compression round trip" begin
    using LazyArtifacts
    import CodecLZO.LZO: lzo_compress, lzo_decompress

    let 
        artifact_path = artifact"CanterburyCorpus"
        for fn in readdir(artifact_path; sort=true, join=true)
            a = read(fn)
            c = transcode(LZOCompressor, a)
            @test length(c) <= first(CodecLZO.compute_run_remainder(length(a)-3, 4)) + length(a) + length(CodecLZO.END_OF_STREAM_DATA)
            @test a == lzo_decompress(c)
        end
    end
end

@testitem "Calgary Corpus compression round trip" begin
    using LazyArtifacts
    import CodecLZO.LZO: lzo_compress, lzo_decompress

    let 
        artifact_path = artifact"CalgaryCorpus"
        for fn in readdir(artifact_path; sort=true, join=true)
            a = read(fn)
            c = transcode(LZOCompressor, a)
            @test length(c) <= first(CodecLZO.compute_run_remainder(length(a)-3, 4)) + length(a) + length(CodecLZO.END_OF_STREAM_DATA)
            @test a == lzo_decompress(c)
        end
    end
end

@testitem "Canterbury Artificial Corpus compression round trip" begin
    using LazyArtifacts
    import CodecLZO.LZO: lzo_compress, lzo_decompress

    let 
        artifact_path = artifact"CanterburyArtificialCorpus"
        for fn in readdir(artifact_path; sort=true, join=true)
            a = read(fn)
            c = transcode(LZOCompressor, a)
            @test length(c) <= first(CodecLZO.compute_run_remainder(length(a)-3, 4)) + length(a) + length(CodecLZO.END_OF_STREAM_DATA)
            @test a == lzo_decompress(c)
        end
    end
end

@testitem "Canterbury Large Corpus compression round trip" begin
    using LazyArtifacts
    import CodecLZO.LZO: lzo_compress, lzo_decompress

    let 
        artifact_path = artifact"CanterburyLargeCorpus"
        for fn in readdir(artifact_path; sort=true, join=true)
            a = read(fn)
            c = transcode(LZOCompressor, a)
            @test length(c) <= first(CodecLZO.compute_run_remainder(length(a)-3, 4)) + length(a) + length(CodecLZO.END_OF_STREAM_DATA)
            @test a == lzo_decompress(c)
        end
    end
end

@testitem "Canterbury Miscellaneous Corpus compression round trip" begin
    using LazyArtifacts
    import CodecLZO.LZO: lzo_compress, lzo_decompress

    let 
        artifact_path = artifact"CanterburyMiscellaneousCorpus"
        for fn in readdir(artifact_path; sort=true, join=true)
            a = read(fn)
            c = transcode(LZOCompressor, a)
            @test length(c) <= first(CodecLZO.compute_run_remainder(length(a)-3, 4)) + length(a) + length(CodecLZO.END_OF_STREAM_DATA)
            @test a == lzo_decompress(c)
        end
    end
end

@testitem "Canterbury Corpus decompression round trip" begin
    using LazyArtifacts
    import CodecLZO.LZO: lzo_compress, lzo_decompress

    let 
        artifact_path = artifact"CanterburyCorpus"
        for fn in readdir(artifact_path; sort=true, join=true)
            a = read(fn)
            c = lzo_compress(a)
            @test a == transcode(LZODecompressor, c)
        end
    end
end

@testitem "Calgary Corpus decompression round trip" begin
    using LazyArtifacts
    import CodecLZO.LZO: lzo_compress, lzo_decompress

    let 
        artifact_path = artifact"CalgaryCorpus"
        for fn in readdir(artifact_path; sort=true, join=true)
            a = read(fn)
            c = lzo_compress(a)
            @test a == transcode(LZODecompressor, c)
        end
    end
end

@testitem "Canterbury Artificial Corpus decompression round trip" begin
    using LazyArtifacts
    import CodecLZO.LZO: lzo_compress, lzo_decompress

    let 
        artifact_path = artifact"CanterburyArtificialCorpus"
        for fn in readdir(artifact_path; sort=true, join=true)
            a = read(fn)
            c = lzo_compress(a)
            @test a == transcode(LZODecompressor, c)
        end
    end
end

@testitem "Canterbury Large Corpus decompression round trip" begin
    using LazyArtifacts
    import CodecLZO.LZO: lzo_compress, lzo_decompress

    let 
        artifact_path = artifact"CanterburyLargeCorpus"
        for fn in readdir(artifact_path; sort=true, join=true)
            a = read(fn)
            c = lzo_compress(a)
            @test a == transcode(LZODecompressor, c)
        end
    end
end

@testitem "Canterbury Miscellaneous Corpus decompression round trip" begin
    using LazyArtifacts
    import CodecLZO.LZO: lzo_compress, lzo_decompress

    let 
        artifact_path = artifact"CanterburyMiscellaneousCorpus"
        for fn in readdir(artifact_path; sort=true, join=true)
            a = read(fn)
            c = lzo_compress(a)
            @test a == transcode(LZODecompressor, c)
        end
    end
end

@testitem "Canterbury Corpus stream-through" begin
    using LazyArtifacts

    let 
        artifact_path = artifact"CanterburyCorpus"
        for fn in readdir(artifact_path; sort=true, join=true)
            truth = read(fn)
            open(fn, "r") do io
                stream = LZODecompressorStream(LZOCompressorStream(io))
                check = read(stream)
                @test check == truth
            end
        end
    end
end

@testitem "Calgary Corpus stream-through" begin
    using LazyArtifacts

    let 
        artifact_path = artifact"CalgaryCorpus"
        for fn in readdir(artifact_path; sort=true, join=true)
            truth = read(fn)
            open(fn, "r") do io
                stream = LZODecompressorStream(LZOCompressorStream(io))
                check = read(stream)
                @test check == truth
            end
        end
    end
end

@testitem "Canterbury Artificial Corpus Corpus stream-through" begin
    using LazyArtifacts

    let 
        artifact_path = artifact"CanterburyArtificialCorpus"
        for fn in readdir(artifact_path; sort=true, join=true)
            truth = read(fn)
            open(fn, "r") do io
                stream = LZODecompressorStream(LZOCompressorStream(io))
                check = read(stream)
                @test check == truth
            end
        end
    end
end

@testitem "Canterbury Large Corpus stream-through" begin
    using LazyArtifacts

    let 
        artifact_path = artifact"CanterburyLargeCorpus"
        for fn in readdir(artifact_path; sort=true, join=true)
            truth = read(fn)
            open(fn, "r") do io
                stream = LZODecompressorStream(LZOCompressorStream(io))
                check = read(stream)
                @test check == truth
            end
        end
    end
end

@testitem "Canterbury Miscellaneous Corpus stream-through" begin
    using LazyArtifacts

    let 
        artifact_path = artifact"CanterburyMiscellaneousCorpus"
        for fn in readdir(artifact_path; sort=true, join=true)
            truth = read(fn)
            open(fn, "r") do io
                stream = LZODecompressorStream(LZOCompressorStream(io))
                check = read(stream)
                @test check == truth
            end
        end
    end
end

@run_package_tests verbose = true