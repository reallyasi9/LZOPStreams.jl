const MAX_FIRST_LITERAL_LENGTH = 0xff - 17
const MAX_SMALL_LITERAL_LENGTH = 3
const LITERAL_MASK_BITS = 4
const SHORT_DISTANCE_HISTORY_MASK_BITS = 5
const LONG_DISTANCE_HISTORY_MASK_BITS = 3

"""
    AbstractCommand

A type representing either a literal copy (`LiteralCopyCommand`) or a history lookback copy (`HistoryCopyCommand`).

Types that inherit from `AbstractCommand` must implement the following methods:
- `command_length(::AbstractCommand)::Int`, which returns the length of the encoded command in bytes;
- `copy_length(::AbstractCommand)::Int`, which returns the number of bytes to be copied to the output;
- one or both of:
    - `decode(::Type{T}, ::AbstractVector{UInt8})::T where {T <: AbstractCommand}`, which decodes a command of type `T` from the start of an `AbstractVector{UInt8}`;
    - `unsafe_decode(::Type{T}, ::Ptr{UInt8}, ::Integer)::T where {T <: AbstractCommand}`, which decodes a command of type `T` from the memory pointed to by the pointer at a given (one-indexed) offset;
- one or both of:
    - `encode!(::T, ::AbstractCommand)::T where {T <: AbstractVector{UInt8}}`, which encodes the command to the given vector and returns the modified vector;
    - `unsafe_encode!(::Ptr{UInt8}, ::AbstractCommand, ::Integer)::Int`, which encodes the command to the memory pointed to at a given (one-indexed offset) and returns the number of bytes written.
"""
abstract type AbstractCommand end

"""
    command_length(command)::Int

Return the number of bytes in the encoded `command`.
"""
function command_length(::AbstractCommand) end

"""
    copy_length(command)::Int

Return the number of bytes that are to be copied to the output by `command`.
"""
function copy_length(::AbstractCommand) end

function unsafe_decode(::Type{T}, ::Ptr{UInt8}, ::Integer=1) where {T <: AbstractCommand} end
decode(::Type{T}, v::AbstractVector{UInt8}) where {T <: AbstractCommand} = GC.@preserve v unsafe_decode(T, pointer(v), 1)
function unsafe_encode!(::Ptr{UInt8}, ::T, ::Integer=1) where {T <: AbstractCommand} end
encode!(v::AbstractVector{UInt8}, c::T) where {T <: AbstractCommand} = GC.@preserve v unsafe_encode(pointer(v), c, 1)

"""
    encode_run!(output, len, bits)::Int

Emit the number of zero bytes necessary to encode a length `len` in a command expecting `bits` leading bits, returning the number of bytes written to the output.

Literal and copy lengths are always encoded as either a single byte or a sequence of three or more bytes. If `len < (1 << bits)`, the length will be encoded in the lower `bits` bits of the starting byte of `output` so the return will be 0. Otherwise, the return will be the number of additional bytes needed to encode the length. The returned number of bytes does not include the zeros in the first byte (the command) used to signal that a run encoding follows, but it does include the remainder.

Note: the argument `len` is expected to be the _adjusted length_ for the command. Literals use an adjusted length of `len = length(literal) - 3` and copy commands use an adjusted literal length of `len = length(copy) - 2`.
"""
function encode_run!(output::AbstractVector{UInt8}, len::Integer, bits::Integer)
    output[1] = zero(UInt8) # clear the bits just in case
    mask = UInt8((1 << bits) - 1)
    if len <= mask
        output[1] |= len % UInt8
        return 1
    end
    n_zeros, len = divrem(len-mask, 255)
    if len == 0
        len = 255
        n_zeros -= 1
    end
    for j in 1:n_zeros
        output[1+j] = zero(UInt8)
    end
    output[2 + n_zeros] = len % UInt8
    return n_zeros + 2
end

"""
    unsafe_encode_run!(p::Ptr{UInt8}, len, bits, [i=1])::Int

Emit the number of zero bytes necessary to encode a length `len` in a command expecting `bits` leading bits, returning the number of bytes written to the output.

Literal and copy lengths are always encoded as either a single byte or a sequence of three or more bytes. If `len < (1 << bits)`, the length will be encoded in the lower `bits` bits of the starting byte of `output` so the return will be 0. Otherwise, the return will be the number of additional bytes needed to encode the length. The returned number of bytes does not include the zeros in the first byte (the command) used to signal that a run encoding follows, but it does include the remainder.

This method is "unsafe" in that it does not check if `p` points to an area of memory large enough to hold the resulting run before clobbering it.

Note: the argument `len` is expected to be the _adjusted length_ for the command. Literals use an adjusted length of `len = length(literal) - 3` and copy commands use an adjusted literal length of `len = length(copy) - 2`.
"""
function unsafe_encode_run!(p::Ptr{UInt8}, len::Integer, bits::Integer, i::Integer=1)
    unsafe_store!(p, zero(UInt8), i) # clear the bits just in case
    mask = UInt8((1 << bits) - 1)
    if len <= mask
        unsafe_store!(p, unsafe_load(p, i) | len % UInt8, i)
        return 1
    end
    n_zeros, len = divrem(len-mask, 255)
    if len == 0
        len = 255
        n_zeros -= 1
    end
    for j in 1:n_zeros
        unsafe_store!(p, zero(UInt8), i + j)
    end
    unsafe_store!(p, len % UInt8, i + n_zeros + 1)
    return n_zeros + 2
end

"""
    decode_run(input::Vector{UInt8}, bits)::Tuple{Int, Int}

Decode the length of the run in bytes and the number of bytes to copy from `input` given a mask of `bits` bits.
"""
function decode_run(input::AbstractVector{UInt8}, bits::Integer)
    mask = ((1 << bits) - 1) % UInt8
    byte = first(input) & mask
    len = byte % Int
    if len != 0
        return 1, len
    end

    first_non_zero = findfirst(!=(0), @view(input[2:end]))
    if isnothing(first_non_zero)
        return 0, 0 # code that we never found a non-zero byte
    end
    len += mask + (first_non_zero - 1) * 255 + input[1+first_non_zero]
    
    return first_non_zero + 1, len
end

"""
    unsafe_decode_run(p::Ptr{UInt8}, i, bits)::Tuple{Int, Int}

Decode the length of the run in bytes and the number of bytes to copy from the memory address pointed to by `p` offset by `i` given a mask of `bits` bits.

This method is "unsafe" in that it will not stop reading from memory addresses after `p` until it finds a non-zero byte, whatever the consequences.
"""
function unsafe_decode_run(p::Ptr{UInt8}, i::Integer, bits::Integer)
    mask = ((1 << bits) - 1) % UInt8
    byte = unsafe_load(p, i) & mask
    len = byte % Int
    if len != 0
        return 1, len
    end

    bytes = 1
    byte = unsafe_load(p, i + bytes)
    while byte == 0
        len += 255
        bytes += 1
        byte = unsafe_load(p, i + bytes)
    end

    return bytes + 1, len + byte + mask
end

"""
    struct LiteralCopyCommand <: AbstractCommand

An encoded command representing a copy of a number of bytes from input straight to output.

In LZO1X, literal copies come in three varieties:

## Long copies

LZO1X long copy commands begin with a byte with four high zero bits and four low potentially non-zero bits:

    0 0 0 0 L L L L

The low four bits represent the length of the copy _minus three_. This can obviously only represent copies of length 3 to 18, so to encode longer copies, LZO1X uses the following encoding method:

1. If the first byte is non-zero, then `length = 3 + L`
2. If the first byte is zero, then `length = 18 + (number of zero bytes after the first) × 255 + (first non-zero byte)`

This means a length of 18 is encoded as `[0b00001111]`, a length of 19 is encoded as `[0b00000000, 0b00000001]`, a length of 274 is encoded as `[0b00000000, 0b00000000, 0b00000001]`, and so on.

## Short copies

The long copy command cannot encode copies shorter than four bytes by design. If a literal of three or fewer bytes needs to be copied, it is encoded in the two least significant bits of the previous history lookback copy command. This works because literal copies and history lookback copies always alternate in LZO1X streams.

## First literal copies

LZO1X streams always begin with a literal copy command of at least four bytes. Because the first command is always a literal copy, a special format is used to copy runs of literals that are between 18 and 238 bytes that compacts the command into a single byte. If the first byte of the stream has the following values, they are interpreted as the corresponding literal copy commands:

- `0:15`: Treat as a "long copy" encoding (see above).
- `17:255`: Treat as a copy of `(byte - 17)` literals.

Note that `17:20` are invalid values for a first copy command in LZO1X streams because history lookback copy lengths must always be four or more bytes. A value of `16` in the first position is always invalid.

!!! note
    The official `liblzo2` version of LZO1X properly _decodes_ these first literal copy codes, but never _encodes_ them when compressing data.

See also [`CodecLZO.HistoryCopyCommand`](@ref).
"""
struct LiteralCopyCommand <: AbstractCommand
    command_length::Int
    copy_length::Int
end

const NULL_LITERAL_COMMAND = LiteralCopyCommand(0, 0)

function LiteralCopyCommand(n::Int; first_literal::Bool = false)
    if n == 0
        return NULL_LITERAL_COMMAND
    end
    if first_literal && n <= MAX_SMALL_LITERAL_LENGTH
        throw(ErrorException("first literal cannot copy fewer than $MAX_SMALL_LITERAL_LENGTH, got $n"))
    elseif first_literal && n <= MAX_FIRST_LITERAL_LENGTH
        return LiteralCopyCommand(1, n)
    elseif n <= MAX_SMALL_LITERAL_LENGTH
        return LiteralCopyCommand(0, n)
    else
        l = n - MAX_SMALL_LITERAL_LENGTH
        b, _ = compute_run_remainder(l, LITERAL_MASK_BITS)
        return LiteralCopyCommand(b, n)
    end
end

command_length(l::LiteralCopyCommand) = l.command_length
copy_length(l::LiteralCopyCommand) = l.copy_length

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

function decode(::Type{LiteralCopyCommand}, data::AbstractVector{UInt8})
    command = first(data)
    if command == 16
        throw(ErrorException("invalid literal copy command detected"))
    end
    if command < 0b00010000
        bytes, len = decode_run(data, LITERAL_MASK_BITS)
        if bytes == 0
            return NULL_LITERAL_COMMAND
        end
        return LiteralCopyCommand(bytes, len + MAX_SMALL_LITERAL_LENGTH)
    else
        return LiteralCopyCommand(1, command - 17)
    end
end

function unsafe_decode(::Type{LiteralCopyCommand}, p::Ptr{UInt8}, i::Integer=1)
    command = unsafe_load(p, i)
    if command == 16
        throw(ErrorException("invalid literal copy command detected"))
    end
    if command < 0b00010000
        bytes, len = unsafe_decode_run(p, i, 4)
        return LiteralCopyCommand(bytes, len + 3)
    else
        return LiteralCopyCommand(1, command - 17)
    end
end

function encode!(data::AbstractVector{UInt8}, c::LiteralCopyCommand; first_literal::Bool=false)
    if first_literal
        # This is completely valid for the first literal, but liblzo2 doesn't use this special encoding
        if c.copy_length <= MAX_FIRST_LITERAL_LENGTH && c.command_length == 1
            data[1] = (c.copy_length+17) % UInt8
            return data
        else
            data[1] = zero(UInt8)
            encode_run!(data, c.copy_length - 3, 4)
            return data
        end
    end

    # 2-bit literal lengths are encoded in the low two bits of the previous command.
    # Interestingly, because the distance is encoded in LE, the 2-bit literal incoding is always on the first byte of the output buffer.
    if c.copy_length < 4
        data[1] &= 0b11111100
        data[1] |= c.copy_length % UInt8
        return data
    end

    # everything else is encoded raw or as a run of unary zeros plus a remainder
    data[1] = zero(UInt8)
    encode_run!(data, c.copy_length - 3, 4)
    return data
end

function unsafe_encode!(p::Ptr{UInt8}, c::LiteralCopyCommand, i::Integer=1; first_literal::Bool=false)
    if first_literal
        # This is completely valid for the first literal, but liblzo2 doesn't use this special encoding
        if c.copy_length <= MAX_FIRST_LITERAL_LENGTH && c.command_length == 1
            unsafe_store!(p, (c.copy_length+17) % UInt8, i)
            return 1
        else
            unsafe_store!(p, zero(UInt8), i)
            return unsafe_encode_run!(p, c.copy_length - 3, 4, i)
        end
    end

    # 2-bit literal lengths are encoded in the low two bits of the previous command.
    # Interestingly, because the distance is encoded in LE, the 2-bit literal incoding is always on the first byte of the output buffer.
    if c.copy_length < 4
        unsafe_store!(p, (unsafe_load(p, i) & 0b11111100) | (c.copy_length % UInt8), i)
        return 1
    end

    # everything else is encoded raw or as a run of unary zeros plus a remainder
    return unsafe_encode_run!(p, c.copy_length - 3, 4, i)
end

"""
    struct HistoryCopyCommand <: AbstractCommand

An encoded command representing a copy of a number of bytes from the already produced output back to the output.

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

Copies of any length greater than two with a lookback distance within 16384 bytes is incoded with at least three bytes and with as many as necessary to encode the run length. The command is to be interpreted in the following way (MSB first):

    `001LLLLL [Z zero bytes] [XXXXXXXX] EEEEEESS DDDDDDDD`

The lower five bits of the first byte represent the length of the copy _minus two_. This can obviously only represent copies of length 2 to 33, so to encode longer copies, LZO1X uses the following encoding method:

1. If `0bLLLLL` is non-zero, then `length = 2 + 0bLLLLL`
2. If `0bLLLLL` is zero, then `length = 33 + (number of zero bytes after the first) × 255 + (first non-zero byte)`

The lookback distance is encoded in LE order in the last two bytes: that is, the last byte of the command holds the MSB of the distance, and the second-to-last byte holds the LSB of the distance. The distance is interpreted as `distance = 0b00DDDDDD_DDEEEEEE + 1`.

The last two bits of the second-to-last byte instruct the decoder to copy `0bSS` literals from the input to the output immediately following the history lookback copy.

## Any length copy, long distance

Copies of any length greater than two with a lookback distance between 16385 and 49151 bytes is incoded with at least three bytes and with as many as necessary to encode the run length. The command is to be interpreted in the following way (MSB first):

    `0001HLLL [Z zero bytes] [XXXXXXXX] EEEEEESS DDDDDDDD`

As with other variable length runs,, LZO1X uses the following encoding method with this command:

1. If `0bLLL` is non-zero, then `length = 2 + 0bLLL`
2. If `0bLLL` is zero, then `length = 9 + (number of zero bytes after the first) × 255 + (first non-zero byte)`

The lookback distance is encoded with one bit in the first command byte (`H`), then in LE order in the last two bytes: that is, the last byte of the command holds the MSB of the distance, and the second-to-last byte holds the LSB of the distance. The distance is interpreted as `distance = 16384 + 0b0HDDDDDD_DDEEEEEE`.

The last two bits of the second-to-last byte instruct the decoder to copy `0bSS` literals from the input to the output immediately following the history lookback copy.

!!! info "Special End-of-Stream Encoding"
    End-of-stream is signaled by a history lookback copy of 3 bytes from a distance of 16384 bytes with no subsequent literal copies. This corresponds to a long historical lookback copy command of `0b00010001 0b00000000 0b00000000`.

!!! note
    The maximum lookback distance that LZO1X can encode is `16384 + 0b01111111_11111111 == 49151` bytes.

## Short copies from short distances following literal copies

If the previous history lookback command included a short literal copy (`1 ≤ 0bSS ≤ 3`, as encoded in the above commands), then a special two-byte command can be used to copy two bytes with a lookback distance within 1024 bytes. The command is to be interpreted in the following way (MSB first):

    `0000DDSS HHHHHHHH`

The number of bytes to copy is always `length = 2`, and the lookback distance is `0b000000HH_HHHHHHDD + 1`.

The last two bits of the first byte instruct the decoder to copy `0bSS` literals from the input to the output immediately following the history lookback copy.

If the previous command was a long literal copy (of four of more bytes), then the same two-byte command means something different: it encodes a three-byte copy with a lookback distance between 2049 and 3071 bytes. The command is interpreted the same as above, but `length = 3` and `distance = 0b000000HH_HHHHHHDD + 2049`.

!!! note
    Because encoding these special commands require a historical match of fewer than four bytes, they are never _encoded_ by the LZO1X algorithm: however, they are valid LZO1X commands, and the LZO1X _decoder_ will interpret them correctly.

See also [`CodecLZO.LiteralCopyCommand`](@ref).
"""
struct HistoryCopyCommand <: AbstractCommand
    command_length::Int
    lookback::Int
    copy_length::Int
    post_copy_literals::UInt8
end

const NULL_HISTORY_COMMAND = HistoryCopyCommand(0, 0, 0, 0)
const END_OF_STREAM_COMMAND = HistoryCopyCommand(3, 16384, 3, 0) # Corresponds to byte sequence 0x11 0x00 0x00

function HistoryCopyCommand(lookback::Integer, copy_length::Integer, post_copy_literals::Integer; last_literals_copied::Integer=4)
    if copy_length < 2 || lookback < 1 || post_copy_literals > 3
        # history copies of 1 byte or zero distance are not allowed
        throw(ErrorException("copy length ($copy_length), lookback ($lookback), post-copy literal ($post_copy_literals) combination not allowed"))
    end
    command_length = 0
    if copy_length == 2
        if lookback > 1 << 10 || last_literals_copied < 1 || last_literals_copied > 3
            throw(ErrorException("copy length 2 must have a lookback less than $(1<<10) (got $lookback) and last literals copied between 1 and 3 (got $last_literals_copied)"))
        else
            command_length = 2
        end
    elseif copy_length == 3 && 2048 < lookback <= 3072 && last_literals_copied >= 4
        command_length = 2
    elseif lookback <= 1 << 11 && copy_length <= 8
        command_length = 2
    elseif lookback <= 1 << 14
        b, _ = compute_run_remainder(copy_length - 2, SHORT_DISTANCE_HISTORY_MASK_BITS)
        command_length = 2 + b
    else
        b, _ = compute_run_remainder(copy_length - 2, LONG_DISTANCE_HISTORY_MASK_BITS)
        command_length = 2 + b
    end

    return HistoryCopyCommand(command_length, lookback, copy_length, post_copy_literals)
end

command_length(h::HistoryCopyCommand) = h.command_length
copy_length(h::HistoryCopyCommand) = h.copy_length

lookback(h::HistoryCopyCommand) = h.lookback
post_copy_literals(h::HistoryCopyCommand) = h.post_copy_literals

function decode(::Type{HistoryCopyCommand}, data::AbstractVector{UInt8}; last_literals_copied::Integer=0)
    remaining_bytes = length(data)
    command = first(data)

    # 2-byte commands first
    if remaining_bytes < 2
        return NULL_HISTORY_COMMAND
    elseif command < 0b00010000
        after = command & 0b00000011
        if last_literals_copied > 0 && last_literals_copied < 4
            len = 2
            dist = ((data[2] % Int) << 2) + ((command & 0b00001100) >> 2) + 1
        elseif last_literals_copied >= 4
            len = 3
            dist = ((data[2] % Int) << 2) + ((command & 0b00001100) >> 2) + 2049
        else
            throw(ErrorException("command 00000000 with zero last literals copied is a literal copy command: call decode(LiteralCopyCommand, data) instead"))
        end
        return HistoryCopyCommand(2, dist, len, after)
    elseif (command & 0b11000000) != 0
        after = command & 0b00000011
        if command < 0b10000000
            len = 3 + ((command & 0b00100000) >> 5)
            dist = ((data[2] % Int) << 3) + ((command & 0b00011100) >> 2) + 1
        else
            len = 5 + ((command & 0b01100000) >> 5)
            dist = ((data[2] % Int) << 3) + ((command & 0b00011100) >> 2) + 1
        end
        return HistoryCopyCommand(2, dist, len, after)
    elseif command < 0b00100000
        # variable-width length encoding
        msb = ((command & 0b00001000) % Int) << 11
        bytes, len = decode_run(data, LONG_DISTANCE_HISTORY_MASK_BITS)
        if bytes == 0 || remaining_bytes < bytes + 2
            return NULL_HISTORY_COMMAND
        end
        dist = 16384 + msb + ((data[bytes + 2] % Int) << 6) + ((data[bytes + 1] % Int) >> 2)
        after = data[bytes + 1] & 0b00000011
        return HistoryCopyCommand(bytes + 2, dist, len + 2, after)
    else
        # variable-width length encoding
        bytes, len = decode_run(data, SHORT_DISTANCE_HISTORY_MASK_BITS)
        if bytes == 0 || remaining_bytes < bytes + 2
            return NULL_HISTORY_COMMAND
        end
        dist = 1 + ((data[bytes + 2] % Int) << 6) + ((data[bytes + 1] % Int) >> 2)
        after = data[bytes + 1] & 0b00000011
        return HistoryCopyCommand(bytes + 2, dist, len + 2, after)
    end
end

function unsafe_decode(::Type{HistoryCopyCommand}, p::Ptr{UInt8}, i::Integer = 1; last_literals_copied::Integer = 0)
    command = unsafe_load(p, i)

    # 2-byte commands first
    if command < 0b00010000
        after = command & 0b00000011
        if last_literals_copied > 0 && last_literals_copied < 4
            len = 2
            dist = ((unsafe_load(p, i+1) % Int) << 2) + ((command & 0b00001100) >> 2) + 1
        elseif last_literals_copied >= 4
            len = 3
            dist = ((unsafe_load(p, i+1) % Int) << 2) + ((command & 0b00001100) >> 2) + 2049
        else
            throw(ErrorException("command 00000000 with zero last literals copied is a literal copy command: call decode(LiteralCopyCommand, data) instead"))
        end
        return HistoryCopyCommand(2, dist, len, after)
    elseif (command & 0b11000000) != 0
        after = command & 0b00000011
        if command < 0b10000000
            len = 3 + ((command & 0b00100000) >> 5)
            dist = ((unsafe_load(p, i+1) % Int) << 3) + ((command & 0b00011100) >> 2) + 1
        else
            len = 5 + ((command & 0b01100000) >> 5)
            dist = ((unsafe_load(p, i+1) % Int) << 3) + ((command & 0b00011100) >> 2) + 1
        end
        return HistoryCopyCommand(2, dist, len, after)
    elseif command < 0b00100000
        # variable-width length encoding
        msb = ((command & 0b00001000) % Int) << 11
        bytes, len = unsafe_decode_run(p, i, LONG_DISTANCE_HISTORY_MASK_BITS)
        if bytes == 0
            return NULL_HISTORY_COMMAND
        end
        dist = 16384 + msb + ((unsafe_load(p, i + bytes + 1) % Int) << 6) + ((unsafe_load(p, i + bytes) % Int) >> 2)
        after = unsafe_load(p, i + bytes) & 0b00000011
        return HistoryCopyCommand(bytes + 2, dist, len + 2, after)
    else
        # variable-width length encoding
        bytes, len = unsafe_decode_run(p, i, SHORT_DISTANCE_HISTORY_MASK_BITS)
        if bytes == 0
            return NULL_HISTORY_COMMAND
        end
        dist = 1 + ((unsafe_load(p, i + bytes + 1) % Int) << 6) + ((unsafe_load(p, i + bytes) % Int) >> 2)
        after = unsafe_load(p, i + bytes) & 0b00000011
        return HistoryCopyCommand(bytes + 2, dist, len + 2, after)
    end
end

function encode!(data::AbstractVector{UInt8}, c::HistoryCopyCommand; last_literals_copied::Integer=0)
    if c == END_OF_STREAM_COMMAND
        data[1:3] = UInt8[0b00010001,0b00000000,0b00000000]
        return data
    end

    # All LZO1X1 matches are 4 bytes or more, so command codes 0-15 and 64-95 are never used, but we add the logic for completeness
    if c.copy_length == 2
        if last_literals_copied == 0
            throw(ErrorException("invalid length 2 copy command with zero last literals copied"))
        elseif last_literals_copied < 4 && c.lookback <= 1024
            # 0b0000DDSS_HHHHHHHH, distance = (H << 2) + D + 1
            distance = c.lookback - 1
            D = UInt8(distance & 0b00000011)
            H = UInt8((distance - D) >> 2)
            data[1] = (D << 2) | c.post_copy_literals
            data[2] = H
            return data
        else
            throw(ErrorException("invalid length 2 copy command with last literals copied greater than 3 (got $last_literals_copied) or lookback greater than 1024 (got $(c.lookback))"))
        end
    elseif last_literals_copied >= 4 && c.copy_length == 3 && 2049 <= c.lookback <= 3072
        # 0b0000DDSS_HHHHHHHH, distance = (H << 2) + D + 2049
        distance = c.lookback - 2049
        D = UInt8(distance & 0b00000011)
        H = UInt8((distance - D) >> 2)
        data[1] = (D << 2) | c.post_copy_literals
        data[2] = H
        return data
    elseif 3 <= c.copy_length <= 4 && c.lookback < 2049
        # 0b01LDDDSS_HHHHHHHH, distance = (H << 3) + D + 1
        distance = c.lookback - 1
        D = UInt8(distance & 0b00000111)
        H = UInt8((distance - D) >> 3)
        L = UInt8(c.copy_length - 3)
        data[1] = 0b01000000 | (L << 5) | (D << 2) | c.post_copy_literals
        data[2] = H
        return data
    elseif 5 <= c.copy_length <= 8 && c.lookback <= 2049
        # 0b1LLDDDSS_HHHHHHHH, distance = (H << 3) + D + 1
        distance = c.lookback - 1
        D = UInt8(distance & 0b00000111)
        H = UInt8((distance - D) >> 3)
        L = UInt8(c.copy_length - 5)
        data[1] = 0b10000000 | (L << 5) | (D << 2) | c.post_copy_literals
        data[2] = H
        return data
    else
        distance = c.lookback
        # NOTE: a distance of 16384 can be encoded in two different ways (this and the command that follows)
        # HOWEVER, end-of-stream is identical to a copy of 3 bytes from a lookback of 16384, so
        # lookbacks of 16384 are always encoded with this command.
        if distance <= 16384
            # 0b001LLLLL_*_DDDDDDSS_DDDDDDDD, distance = D + 1, length = 2 + (L ?: *)
            # Note that D is encoded LE in the last 16 bits!
            n_written = encode_run!(data, c.copy_length - 2, SHORT_DISTANCE_HISTORY_MASK_BITS)
            data[1] |= 0b00100000
            distance -= 1
        else
            # 0b0001HLLL_*_DDDDDDSS_DDDDDDDD, distance = 16384 + (H << 14) + D, length = 2 + (L ?: *)
            # Note that D is encoded LE in the last 16 bits!
            n_written = encode_run!(data, c.copy_length - 2, LONG_DISTANCE_HISTORY_MASK_BITS)
            data[1] |= 0b00010000
            distance -= 16384
            H = UInt8((distance >> 14) & 1)
            data[1] |= H << 3
        end
        DH = UInt8((distance >> 6) & 0b11111111)
        DL = UInt8(distance & 0b00111111)
        data[n_written+1] = (DL << 2) | c.post_copy_literals # This is popped off the top with popfirst! when encoding the next literal length
        data[n_written+2] = DH
        return data
    end
end

function unsafe_encode!(p::Ptr{UInt8}, c::HistoryCopyCommand, i::Integer = 1; last_literals_copied::Integer = 0)
    if c == END_OF_STREAM_COMMAND
        unsafe_store!(p, 0b00010001, i)
        unsafe_store!(p, 0b00000000, i+1)
        unsafe_store!(p, 0b00000000, i+2)
        return 3
    end

    # All LZO1X1 matches are 4 bytes or more, so command codes 0-15 and 64-95 are never used, but we add the logic for completeness
    if c.copy_length == 2
        if last_literals_copied == 0
            throw(ErrorException("invalid length 2 copy command with zero last literals copied"))
        elseif last_literals_copied < 4 && c.lookback <= 1024
            # 0b0000DDSS_HHHHHHHH, distance = (H << 2) + D + 1
            distance = c.lookback - 1
            D = UInt8(distance & 0b00000011)
            H = UInt8((distance - D) >> 2)
            unsafe_store!(p, (D << 2) | c.post_copy_literals, i)
            unsafe_store!(p, H, i+1)
            return 2
        else
            throw(ErrorException("invalid length 2 copy command with last literals copied greater than 3 (got $last_literals_copied) or lookback greater than 1024 (got $(c.lookback))"))
        end
    elseif last_literals_copied >= 4 && c.copy_length == 3 && 2049 <= c.lookback <= 3072
        # 0b0000DDSS_HHHHHHHH, distance = (H << 2) + D + 2049
        distance = c.lookback - 2049
        D = UInt8(distance & 0b00000011)
        H = UInt8((distance - D) >> 2)
        unsafe_store!(p, (D << 2) | c.post_copy_literals, i)
        unsafe_store!(p, H, i+1)
        return 2
    elseif 3 <= c.copy_length <= 4 && c.lookback < 2049
        # 0b01LDDDSS_HHHHHHHH, distance = (H << 3) + D + 1
        distance = c.lookback - 1
        D = UInt8(distance & 0b00000111)
        H = UInt8((distance - D) >> 3)
        L = UInt8(c.copy_length - 3)
        unsafe_store!(p, 0b01000000 | (L << 5) | (D << 2) | c.post_copy_literals, i)
        unsafe_store!(p, H, i+1)
        return 2
    elseif 5 <= c.copy_length <= 8 && c.lookback <= 2049
        # 0b1LLDDDSS_HHHHHHHH, distance = (H << 3) + D + 1
        distance = c.lookback - 1
        D = UInt8(distance & 0b00000111)
        H = UInt8((distance - D) >> 3)
        L = UInt8(c.copy_length - 5)
        unsafe_store!(p, 0b10000000 | (L << 5) | (D << 2) | c.post_copy_literals, i)
        unsafe_store!(p, H, i+1)
        return 2
    else
        distance = c.lookback
        # NOTE: a distance of 16384 can be encoded in two different ways (this and the command that follows)
        # HOWEVER, end-of-stream is identical to a copy of 3 bytes from a lookback of 16384, so
        # lookbacks of 16384 are always encoded with this command.
        if distance <= 16384
            # 0b001LLLLL_*_DDDDDDSS_DDDDDDDD, distance = D + 1, length = 2 + (L ?: *)
            # Note that D is encoded LE in the last 16 bits!
            run = unsafe_encode_run!(p, c.copy_length - 2, SHORT_DISTANCE_HISTORY_MASK_BITS, i)
            unsafe_store!(p, unsafe_load(p, i) | 0b00100000, i)
            distance -= 1
        else
            # 0b0001HLLL_*_DDDDDDSS_DDDDDDDD, distance = 16384 + (H << 14) + D, length = 2 + (L ?: *)
            # Note that D is encoded LE in the last 16 bits!
            run = unsafe_encode_run!(p, c.copy_length - 2, LONG_DISTANCE_HISTORY_MASK_BITS, i)
            distance -= 16384
            H = UInt8((distance >> 14) & 1)
            unsafe_store!(p, unsafe_load(p, i) | 0b00010000 | (H << 3), i)
        end
        DH = UInt8((distance >> 6) & 0b11111111)
        DL = UInt8(distance & 0b00111111)
        unsafe_store!(p, (DL << 2) | c.post_copy_literals, i+run) # This is popped off the top with popfirst! when encoding the next literal length
        unsafe_store!(p, DH, i+run+1)
        return run + 2
    end
end


