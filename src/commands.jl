const MAX_FIRST_LITERAL_LENGTH = 0xff - 17
const MAX_SMALL_LITERAL_LENGTH = 3
const LITERAL_MASK_BITS = 4
const SHORT_DISTANCE_HISTORY_MASK_BITS = 5
const LONG_DISTANCE_HISTORY_MASK_BITS = 3
const END_OF_STREAM_LOOKBACK = UInt16(16384)
const END_OF_STREAM_COPY_LENGTH = 3

"""
    CommandPair

A mutable type representing both a history lookback copy and a literal copy.

Except for the first or last command, commands in LZO 1X1 always come in pairs: a history lookback _always_ follows a literal, and if a literal copy of zero bytes is considered, a literal copy _always_ follows a history lookback. This means commands can be efficiently stored, parsed, and encoded as pairs of commands.

# Literal copies

In LZO1X, literal copies come in three varieties:

## Long copies

LZO1X long copy commands begin with a byte with four high zero bits and four low potentially non-zero bits:

    `0000LLLL [Z zero bytes] [XXXXXXXX]`

The low four bits represent the length of the copy _minus three_. This can obviously only represent copies of length 3 to 18, so to encode longer copies, LZO1X uses the following encoding method:

1. If the first byte is non-zero, then `length = 3 + L`
2. If the first byte is zero, then `length = 18 + Z × 255 + 0bXXXXXXXX`

This means a length of 18 is encoded as `[0b00001111]`, a length of 19 is encoded as `[0b00000000, 0b00000001]`, a length of 274 is encoded as `[0b00000000, 0b00000000, 0b00000001]`, and so on.

## Short copies

The long copy command cannot encode copies shorter than four bytes by design. If a literal of three or fewer bytes needs to be copied, it is encoded in the two least significant bits of the previous history lookback copy command. This works because literal copies and history lookback copies always alternate in LZO1X streams.

## First literal copies

LZO1X streams always begin with a literal copy command of at least four bytes. Because the first command is always a literal copy, a special format is used to copy runs of literals that are between 18 and 238 bytes that compacts the command into a single byte. If the first byte of the stream has the following values, they are interpreted as the corresponding literal copy commands:

- `0:15`: Treat as a "long copy" encoding (see above).
- `17:255`: Treat as a copy of `(byte - 17)` literals.

Note that `17:20` are technically invalid values for a first copy command in LZO1X streams because history lookback copy lengths must always be four or more bytes. A value of `16` in the first position is _always_ invalid because it signals a history lookback copy command, which cannot come before any literals are copied to the output.

!!! note
    The official `liblzo2` version of LZO1X properly _decodes_ these first literal copy codes, but never _encodes_ them when compressing data. This is likely because the first literal copy codes only save at most one byte in the output stream (if the number of bytes to copy is `∈ 19:272`).

# History lookback copies

In LZO1X, history lookback copies come in five varieties, the format of which is determined by the number of bytes copied, the lookback distance, and whether or not the previous command had a short literal copy tagged on the end:

## Very short copy, short distance

Copies of three to four bytes with a lookback distance within 2048 bytes are encoded as two bytes, with bits encoding the length and distance. The command is to be interpreted in the following way (MSB first):

    `01LDDDSS HHHHHHHH`

This means copy `3 + 0bL` from a distance of `0b00000HHH_HHHHHDDD + 1`.

The last two bits of the MSB instruct the decoder to copy `0bSS` literals from the input to the output immediately following the history lookback copy.

## Short copy, short distance

Copies of five to eight bytes with a lookback distance within 2048 bytes are encoded as two bytes, with bits encoding the length and distance. The command is to be interpreted in the following way (MSB first):

    `1LLDDDSS HHHHHHHH`

This means copy `5 + 0bLL` bytes from a distance of `0b00000HHH_HHHHHDDD + 1`.

The last two bits of the MSB instruct the decoder to copy 0 through 3 literals from the input to the output immediately following the history lookback copy.

## Any length copy, short to medium distance

Copies of any length greater than two with a lookback distance within 16384 bytes are incoded with at least three bytes and with as many as necessary to encode the run length. The command is to be interpreted in the following way (MSB first):

    `001LLLLL [Z zero bytes] [XXXXXXXX] EEEEEESS DDDDDDDD`

The lower five bits of the first byte represent the length of the copy _minus two_. To encode copies longer than 33 bytes, LZO1X uses the following encoding method:

1. If `0bLLLLL` is non-zero, then `length = 2 + 0bLLLLL`
2. If `0bLLLLL` is zero, then `length = 33 + Z × 255 + 0bXXXXXXXX`

The lookback distance is encoded in LE order in the last two bytes: that is, the last byte of the command holds the MSB of the distance, and the second-to-last byte holds the LSB of the distance. The distance is interpreted as `distance = 0b00DDDDDD_DDEEEEEE + 1`.

The last two bits of the second-to-last byte instruct the decoder to copy `0bSS` literals from the input to the output immediately following the history lookback copy.

## Any length copy, long distance

Copies of any length greater than two with a lookback distance between 16385 and 49151 bytes are incoded with at least three bytes and with as many as necessary to encode the run length. The command is to be interpreted in the following way (MSB first):

    `0001HLLL [Z zero bytes] [XXXXXXXX] EEEEEESS DDDDDDDD`

As with other variable length runs, LZO1X uses the following encoding method with this command:

1. If `0bLLL` is non-zero, then `length = 2 + 0bLLL`
2. If `0bLLL` is zero, then `length = 9 + Z × 255 + 0bXXXXXXXX`

The lookback distance is encoded with one bit in the first command byte (`H`), then in LE order in the last two bytes: that is, the last byte of the command holds the MSB of the distance, and the second-to-last byte holds the LSB of the distance. The distance is interpreted as `distance = 16384 + 0b0HDDDDDD_DDEEEEEE`.

The last two bits of the second-to-last byte instruct the decoder to copy `0bSS` literals from the input to the output immediately following the history lookback copy.

!!! info "Special End-of-Stream Encoding"
    End-of-stream is signaled by a history lookback copy of 3 bytes from a distance of 16384 bytes with no subsequent literal copies. This corresponds to two possible commands, so by convention the end-of-stream command uses the long distance version (`0b00010001 0b00000000 0b00000000`) while an actual copy of 3 bytes from a distance of 16384 uses the short distance version (`0b00100001 0b00000000 0b00000000`).

!!! note
    The maximum lookback distance that LZO1X can encode is `16384 + 0b01111111_11111111 == 49151` bytes.

## Short copies from short distances following literal copies

If the previous history lookback command included a short literal copy (`1 ≤ 0bSS ≤ 3`, as encoded in the above commands), then a special two-byte command can be used to copy two bytes with a lookback distance within 1024 bytes. The command is to be interpreted in the following way (MSB first):

    `0000DDSS HHHHHHHH`

The number of bytes to copy is always `length = 2`, and the lookback distance is `0b000000HH_HHHHHHDD + 1`.

The last two bits of the first byte instruct the decoder to copy `0bSS` literals from the input to the output immediately following the history lookback copy.

If the previous command was a long literal copy (of four of more bytes), then the same two-byte command means something different: it encodes a three-byte copy with a lookback distance between 2049 and 3072 bytes. The command is interpreted the same as above, but `length = 3` and `distance = 0b000000HH_HHHHHHDD + 2049`.

!!! note
    Because encoding these special commands require a historical match of fewer than four bytes, they are never _encoded_ by the LZO1X algorithm: however, they are valid LZO1X commands, and the LZO1X _decoder_ will interpret them correctly.

See also: [`decode`](@ref) and [`encode`](@ref).
"""
struct CommandPair
    first_literal::Bool
    eos::Bool
    lookback::UInt16
    copy_length::Int
    literal_length::Int
end

const END_OF_STREAM_DATA = UInt8[0b00010001, 0b00000000, 0b00000000]
const END_OF_STREAM_COMMAND = CommandPair(false, true, END_OF_STREAM_LOOKBACK, END_OF_STREAM_COPY_LENGTH, 0)
const NULL_COMMAND = CommandPair(false, false, 0, 0, 0)

function _validate_commands(cp::CommandPair, last_literal_length::Integer=0)
    if !cp.first_literal 
        cp.copy_length < 2 && throw(ErrorException("history copy length ($(cp.copy_length)) not allowed"))
        cp.lookback < 1 && throw(ErrorException("history copy lookback ($(cp.lookback)) not allowed"))
        cp.copy_length == 2 && (cp.lookback > 1 << 10 || last_literal_length < 1 || last_literal_length > 3) && throw(ErrorException("history copy length 2 must have a lookback ≤ $(1<<10) (got $(cp.lookback)) and last literals copied ∈ [1,3] (got $(last_literal_length))"))
        cp.eos && (cp.copy_length != END_OF_STREAM_COPY_LENGTH || cp.lookback != END_OF_STREAM_LOOKBACK || cp.literal_length != 0) && throw(ErrorException("EOS must have a lookback of $END_OF_STREAM_LOOKBACK (got $(cp.copy_length)), a history copy length of $END_OF_STREAM_COPY_LENGTH (got $(cp.copy_length)), and no literal copy (got $(cp.literal_length))"))
    else
        cp.eos && throw(ErrorException("EOS not allowed in first literal (empty data must be encoded as empty data)"))
        (cp.copy_length != 0 || cp.lookback != 0) && throw(ErrorException("history copies not allowed before first literal"))
        cp.literal_length < LZO1X1_MIN_MATCH && throw(ErrorException("first literal cannot copy fewer than $LZO1X1_MIN_MATCH bytes, got $(cp.literal_length)"))
    end
    cp.literal_length < 0 && throw(ErrorException("literal length ($(cp.literal_length)) not allowed"))
end

"""
    command_length(command, [last_literal_length=0])::Int

Return the number of bytes in the encoded commands.
"""
function command_length(cp::CommandPair, last_literal_length::Integer=0)
    _validate_commands(cp, last_literal_length)

    if cp.eos
        return 3
    end

    history_copy_command_length = 0
    if cp.first_literal
        history_copy_command_length = 0
    elseif cp.copy_length == 2
        history_copy_command_length = 2
    elseif cp.copy_length == 3 && 2048 < cp.lookback <= 3072 && last_literal_length >= 4
        history_copy_command_length = 2
    elseif cp.lookback <= 1 << 11 && cp.copy_length <= 8
        history_copy_command_length = 2
    elseif cp.lookback <= 1 << 14
        b, _ = compute_run_remainder(cp.copy_length - 2, SHORT_DISTANCE_HISTORY_MASK_BITS)
        history_copy_command_length = 2 + b
    else
        b, _ = compute_run_remainder(cp.copy_length - 2, LONG_DISTANCE_HISTORY_MASK_BITS)
        history_copy_command_length = 2 + b
    end

    literal_copy_command_length = 0
    if cp.first_literal && cp.literal_length <= MAX_FIRST_LITERAL_LENGTH
        literal_copy_command_length = 1
    elseif cp.literal_length <= MAX_SMALL_LITERAL_LENGTH
        literal_copy_command_length = 0
    else
        l = cp.literal_length - MAX_SMALL_LITERAL_LENGTH
        literal_copy_command_length, _ = compute_run_remainder(l, LITERAL_MASK_BITS)
    end

    return history_copy_command_length + literal_copy_command_length
end

"""
    encode_run!(output, len, bits, [start_index=1])::Int

Emit the number of zero bytes necessary to encode a length `len` in a command expecting `bits` leading bits to `output`, optionally starting at index `start_index`, returning the number of bytes written.

Literal and history copy lengths are always encoded as either a single byte or a sequence of three or more bytes. If `len < (1 << bits)`, the length will be encoded in the lower `bits` bits of the starting byte of `output` so the return will be 1. Otherwise, the return will be the number of bytes needed to encode the length.

If `output` is not large enough to hold the length of the run, this function returns `0` and `output` is unchanged.

Arguments:
- `output`: The target array-like object that will be written to. The type only needs to implement `setindex!(output, ::UInt8, ::Int)` and `lastindex(output)`.
- `len::Integer`: The _adjusted_ length to encode (see note).
- `bits::Integer`: The number of bits that makes up the length mask of the command.
- `start_index::Integer=1`: Where to begin writing the encoded run in `output`.

!!! note
    The argument `len` is expected to be the _adjusted length_ for the command. Literals use an adjusted length of `len = length(literal) - 3` and copy commands use an adjusted literal length of `len = length(copy) - 2`.
"""
function encode_run!(output, len::Integer, bits::Integer, start_index::Integer=1)
    remaining_bytes = lastindex(output) - start_index + 1
    remaining_bytes < 1 && return 0

    mask = UInt8((1 << bits) - 1)
    
    if len <= mask
        output[start_index] = zero(UInt8) # clear the bits just in case
        output[start_index] |= len % UInt8
        return 1
    end
    
    n_zeros, len = divrem(len-mask, 255)
    if len == 0
        len = 255
        n_zeros -= 1
    end
    
    remaining_bytes < n_zeros + 2 && return 0

    output[start_index] = zero(UInt8) # clear the bits just in case
    for j in 1:n_zeros
        output[start_index+j] = zero(UInt8)
    end
    output[start_index + n_zeros + 1] = len % UInt8
    return n_zeros + 2
end

"""
    encode_run(len::Integer, bits::Integer)::Vector{UInt8}

Emit a vector of the number of zero bytes necessary to encode a length `len` in a command expecting `bits` leading bits.

See: [`encode_run!`](@ref).
"""
function encode_run(len::Integer, bits::Integer)
    l, _ = compute_run_remainder(len, bits)
    output = zeros(UInt8, l)
    encode_run!(output, len, bits)
    return output
end

"""
    decode_run(input, bits::Integer, [start_index::Integer = 1])::Tuple{Int, Int}

Decode the number of bytes in the encoding and the length of the run in bytes of the run in `input` given a mask of `bits` bits, optionally starting decoding at index `start_index`.
"""
function decode_run(input, bits::Integer, start_index::Integer = 1)
    remaining_bytes = lastindex(input) - start_index + 1
    remaining_bytes < 1 && return 0, 0

    mask = ((1 << bits) - 1) % UInt8
    byte = input[start_index] & mask
    len = byte % Int
    if len != 0
        return 1, len
    end

    remaining_bytes < 2 && return 0, 0
    first_non_zero = start_index + 1
    while first_non_zero < lastindex(input)
        input[first_non_zero] != 0 && break
        first_non_zero += 1
    end

    if input[first_non_zero] == 0
        return 0, 0 # code that we never found a non-zero byte
    end
    len += mask + (first_non_zero - start_index - 1) * 255 + input[first_non_zero]
    
    return first_non_zero - start_index + 1, len
end


"""
    compute_run_remainder(n, bits)::Tuple{Int, Int}

Compute the number of bytes necessary to encode a run of length `n` given a first-byte mask of length `bits`, also returning the remainder byte.

!!! note
    This method does not adjust `n` before computing the run length. Perform adjustments before calling this method.
"""
function compute_run_remainder(n::Integer, bits::Integer)
    mask = UInt8((1 << bits) - 1)
    if n <= mask
        return 1, n
    end
    b, n = divrem(n-mask, 255)
    if n == 0
        return b+1, 255
    else
        return b+2, n
    end
end

function decode(::Type{CommandPair}, data, start_index::Integer = 1; first_literal::Bool = false, last_literal_length::Integer = 0)
    if !first_literal
        n_read, eos, lookback, copy_length, post_copy_literals = decode_history_copy(data, start_index, last_literal_length)
        if eos
            return n_read, END_OF_STREAM_COMMAND
        elseif lookback == 0
            return 0, NULL_COMMAND
        end
    else
        n_read = lookback = copy_length = post_copy_literals = 0
    end

    if post_copy_literals == 0
        r, literal_length = decode_literal_copy(data, start_index + n_read, first_literal)
        if r == 0
            return 0, NULL_COMMAND
        end
        n_read += r
    else
        literal_length = post_copy_literals
    end

    return n_read, CommandPair(first_literal, false, lookback, copy_length, literal_length)
end


function decode_history_copy(data, start_index::Integer = 1, last_literal_length::Integer = 0)
    remaining_bytes = length(data)
    command = data[start_index]

    # 2-byte commands first
    if remaining_bytes < 2
        return 0, false, 0, 0, 0
    elseif command < 0b00010000
        after = command & 0b00000011
        if 0 < last_literal_length < 4
            len = 2
            dist = ((data[start_index + 1] % Int) << 2) + ((command & 0b00001100) >> 2) + 1
        elseif last_literal_length >= 4
            len = 3
            dist = ((data[start_index + 1] % Int) << 2) + ((command & 0b00001100) >> 2) + 2049
        else
            throw(ErrorException("command 00000000 with zero last literals copied is a literal copy command: call decode_literal_copy(data) instead"))
        end
        return 2, false, dist, len, after
    elseif (command & 0b11000000) != 0
        after = command & 0b00000011
        if command < 0b10000000
            len = 3 + ((command & 0b00100000) >> 5)
            dist = ((data[start_index + 1] % Int) << 3) + ((command & 0b00011100) >> 2) + 1
        else
            len = 5 + ((command & 0b01100000) >> 5)
            dist = ((data[start_index + 1] % Int) << 3) + ((command & 0b00011100) >> 2) + 1
        end
        return 2, false, dist, len, after
    elseif command < 0b00100000
        # variable-width length encoding
        msb = ((command & 0b00001000) % Int) << 11
        bytes, len = decode_run(data, LONG_DISTANCE_HISTORY_MASK_BITS, start_index)
        if bytes == 0 || remaining_bytes < bytes + 2
            return 0, false, 0, 0, 0
        end
        dist = 16384 + msb + ((data[start_index + bytes + 1] % Int) << 6) + ((data[start_index + bytes] % Int) >> 2)
        after = data[start_index + bytes] & 0b00000011
        if dist == END_OF_STREAM_LOOKBACK && len+2 == END_OF_STREAM_COPY_LENGTH && after == 0
            return 3, true, END_OF_STREAM_LOOKBACK, END_OF_STREAM_COPY_LENGTH, 0
        end
        return bytes + 2, false, dist, len + 2, after
    else
        # variable-width length encoding
        bytes, len = decode_run(data, SHORT_DISTANCE_HISTORY_MASK_BITS, start_index)
        if bytes == 0 || remaining_bytes < bytes + 2
            return 0, false, 0, 0, 0
        end
        dist = 1 + ((data[start_index + bytes + 1] % Int) << 6) + ((data[start_index + bytes] % Int) >> 2)
        after = data[start_index + bytes] & 0b00000011
        return bytes + 2, false, dist, len + 2, after
    end
end

function decode_literal_copy(data, start_index::Integer=1, first_literal::Bool=false)
    command = data[start_index]
    if command == 16
        throw(ErrorException("invalid literal copy command $(bitstring(command)) detected"))
    end
    if command < 0b00010000
        bytes, len = decode_run(data, LITERAL_MASK_BITS, start_index)
        if bytes == 0
            return 0, 0
        end
        return bytes, len + MAX_SMALL_LITERAL_LENGTH
    elseif first_literal
        return 1, command - 17
    else
        throw(ErrorException("invalid literal copy command $(bitstring(command)) detected"))
    end
end


function encode!(data, cp::CommandPair, start_index::Integer=1; last_literal_length::Integer=0)
    _validate_commands(cp, last_literal_length)
    n_written = 0
    if !cp.first_literal
        n_written += encode_history_copy!(data, cp, start_index, last_literal_length)
    end
    n_written += encode_literal_copy!(data, cp, start_index + n_written)
    return n_written
end

function encode_history_copy!(data, cp::CommandPair, start_index::Integer, last_literal_length::Integer)
    remaining_bytes = lastindex(data) - start_index + 1

    if cp.eos
        remaining_bytes < 3 && return 0
        data[start_index] = UInt8(0b00010001)
        data[start_index + 1] = zero(UInt8)
        data[start_index + 2] = zero(UInt8)
        return 3
    end

    # All LZO1X1 matches are 4 bytes or more, so command codes 0-15 and 64-95 are never used, but we add the logic for completeness
    S = cp.literal_length <= MAX_SMALL_LITERAL_LENGTH ? UInt8(cp.literal_length) : zero(UInt8)
    if cp.copy_length == 2
        if last_literal_length == 0
            throw(ErrorException("invalid length 2 copy command with zero last literals copied"))
        elseif last_literal_length < 4 && cp.lookback <= 1024
            remaining_bytes < 2 && return 0
            # 0b0000DDSS_HHHHHHHH, distance = (H << 2) + D + 1
            distance = cp.lookback - 1
            D = UInt8(distance & 0b00000011)
            H = UInt8((distance - D) >> 2)
            data[start_index] = (D << 2) | S
            data[start_index + 1] = H
            return 2
        else
            throw(ErrorException("invalid length 2 copy command with last literals copied greater than 3 (got $last_literal_length) or lookback greater than 1024 (got $(cp.lookback))"))
        end
    elseif last_literal_length >= 4 && cp.copy_length == 3 && 2049 <= cp.lookback <= 3072
        remaining_bytes < 2 && return 0
        # 0b0000DDSS_HHHHHHHH, distance = (H << 2) + D + 2049
        distance = cp.lookback - 2049
        D = UInt8(distance & 0b00000011)
        H = UInt8((distance - D) >> 2)
        data[start_index] = (D << 2) | S
        data[start_index+1] = H
        return 2
    elseif 3 <= cp.copy_length <= 4 && cp.lookback <= 2048
        remaining_bytes < 2 && return 0
        # 0b01LDDDSS_HHHHHHHH, distance = (H << 3) + D + 1
        distance = cp.lookback - 1
        D = UInt8(distance & 0b00000111)
        H = UInt8((distance - D) >> 3)
        L = UInt8(cp.copy_length - 3)
        data[start_index] = 0b01000000 | (L << 5) | (D << 2) | S
        data[start_index+1] = H
        return 2
    elseif 5 <= cp.copy_length <= 8 && cp.lookback <= 2048
        remaining_bytes < 2 && return 0
        # 0b1LLDDDSS_HHHHHHHH, distance = (H << 3) + D + 1
        distance = cp.lookback - 1
        D = UInt8(distance & 0b00000111)
        H = UInt8((distance - D) >> 3)
        L = UInt8(cp.copy_length - 5)
        data[start_index] = 0b10000000 | (L << 5) | (D << 2) | S
        data[start_index+1] = H
        return 2
    else
        distance = cp.lookback
        # NOTE: a distance of 16384 can be encoded in two different ways (this and the command that follows)
        # HOWEVER, end-of-stream is identical to a copy of 3 bytes from a lookback of 16384, so
        # lookbacks of 16384 are always encoded with this command.
        if distance <= 16384
            # 0b001LLLLL_*_DDDDDDSS_DDDDDDDD, distance = D + 1, length = 2 + (L ?: *)
            # Note that D is encoded LE in the last 16 bits!
            n_written = encode_run!(data, cp.copy_length - 2, SHORT_DISTANCE_HISTORY_MASK_BITS, start_index)
            data[start_index] |= 0b00100000
            distance -= 1
        elseif distance <= LZO1X1_MAX_DISTANCE
            # 0b0001HLLL_*_DDDDDDSS_DDDDDDDD, distance = 16384 + (H << 14) + D, length = 2 + (L ?: *)
            # Note that D is encoded LE in the last 16 bits!
            n_written = encode_run!(data, cp.copy_length - 2, LONG_DISTANCE_HISTORY_MASK_BITS)
            data[start_index] |= 0b00010000
            distance -= 16384
            H = UInt8((distance >> 14) & 1)
            data[start_index] |= H << 3
        else
            throw(ErrorException("history copy command can only encode lookback <= $LZO1X1_MAX_DISTANCE, got $distance"))
        end
        n_written == 0 && return 0
        remaining_bytes < 2 + n_written && return 0
        DH = UInt8((distance >> 6) & 0b11111111)
        DL = UInt8(distance & 0b00111111)
        data[start_index+n_written] = (DL << 2) | S
        data[start_index+n_written+1] = DH
        return n_written+2
    end
end

function encode_literal_copy!(data, cp::CommandPair, start_index::Integer)
    remaining_bytes = lastindex(data) - start_index + 1
    if remaining_bytes < 1
        return 0
    end

    if cp.first_literal
        # This is completely valid for the first literal, but liblzo2 doesn't use this special encoding
        if cp.literal_length <= MAX_FIRST_LITERAL_LENGTH
            data[start_index] = (cp.literal_length+17) % UInt8
            return 1
        else
            return encode_run!(data, cp.literal_length - 3, LITERAL_MASK_BITS, start_index)
        end
    end

    # 2-bit literal lengths are encoded in the low two bits of the previous command.
    # Interestingly, because the distance is encoded in LE, the 2-bit literal incoding is always on the first byte of the output buffer.
    if cp.literal_length <= MAX_SMALL_LITERAL_LENGTH
        return 0
    end

    # everything else is encoded raw or as a run of unary zeros plus a remainder
    return encode_run!(data, cp.literal_length - 3, LITERAL_MASK_BITS, start_index)
end
