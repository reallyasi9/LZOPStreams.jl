# Dictionary definitions

const LZO1X1_LAST_LITERAL_SIZE = 5  # the number of bytes in the last literal
const LZO1X1_MIN_MATCH = 4  # the smallest number of bytes to consider in a dictionary lookup
const LZO1X1_MAX_INPUT_SIZE = 0x7e00_0000  # 2133929216 bytes
const LZO1X1_HASH_LOG = 12  # 1 << 12 = 4 KB maximum dictionary size
const LZO1X1_MIN_TABLE_SIZE = 16
const LZO1X1_MAX_TABLE_SIZE = 1 << LZO1X1_HASH_LOG
const LZO1X1_COPY_LENGTH = 8  # copy this many bytes at a time, if possible
const LZO1X1_MATCH_FIND_LIMIT = LZO1X1_COPY_LENGTH + LZO1X1_MIN_MATCH  # 12
const LZO1X1_MIN_LENGTH = LZO1X1_MATCH_FIND_LIMIT + 1
const LZO1X1_ML_BITS = 4  # match lengths can be up to 1 << 4 - 1 = 15
const LZO1X1_RUN_BITS = 8 - ML_BITS  # runs can be up to 1 << 4 - 1 = 15
const LZO1X1_RUN_MASK = (1 << RUN_BITS) - 1

const LZO1X1_MAX_DISTANCE = 0b11000000_00000000 - 1  # 49151 bytes, if a match starts further back in the buffer than this, it is considered a miss
const LZO1X1_SKIP_TRIGGER = 6  # This tunes the compression ratio: higher values increases the compression but runs slower on incompressable data

const LZO1X1_HASH_MAGIC_NUMBER = 889523592379
const LZO1X1_HASH_BITS = 28

# Compute the minimum safe compressed length required
function max_compressed_length(in_length::Int)
    return in_length + (in_length+1) >> 8 + 16
end

# Get 8 bytes from an array and reinterpret as an LE-ordered value of type T
function reinterpret_get(::Type{T}, input::AbstractVector{UInt8}, index::Int = 1) where {T}
    return htol(reinterpret(T, input[index:index+sizeof(T)-1]))
end