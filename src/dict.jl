# Dictionary definitions

const SHORT_SIZE = 2
const INT_SIZE = 4
const LONG_SIZE = 8

const LAST_LITERAL_SIZE = 5  # the number of bytes in the last literal
const MIN_MATCH = 4  # the smallest number of bytes to consider in a dictionary lookup
const MAX_INPUT_SIZE = 0x7e000000  # 2133929216 bytes
const HASH_LOG = 12  # 1 << 12 = 4 KB maximum dictionary size
const MIN_TABLE_SIZE = 16
const MAX_TABLE_SIZE = 1 << HASH_LOG
const COPY_LENGTH = 8  # copy this many bytes at a time, if possible
const MATCH_FIND_LIMIT = COPY_LENGTH + MIN_MATCH  # 12
const MIN_LENGTH = MATCH_FIND_LIMIT + 1
const ML_BITS = 4  # match lengths can be up to 1 << 4 - 1 = 15
const RUN_BITS = 8 - ML_BITS  # runs can be up to 1 << 4 - 1 = 15
const RUN_MASK = (1 << RUN_BITS) - 1

const MAX_DISTANCE = 0b1100000000000000 - 1  # 49151 bytes, this is the maximum chunk size allowed before the dictionary has to be rebuilt
const SKIP_TRIGGER = 6  # This tunes the compression ratio: higher values increases the compression but runs slower on incompressable data

const _HASH_MAGIC_NUMBER = 889523592379
const _HASH_BITS = 28

# A dict-like struct that maps integers of type K into a flat vector of fixed size elements of type V
# using the same algorithm as the LZO1X1 compressor. Default values are always zero.
# This is not an AbstractDict because one cannot iterate over values in the map.
struct HashMap{K<:Integer, V<:Integer}
    data::Vector{V}
    function HashMap{K,V}(length::Int) where {K<:Integer, V<:Integer}
        return new{K,V}(zeros(V, length))
    end
end

empty!(hm::HashMap) = fill!(hm.data, zero(eltype(hm.data)))

# Perform `value * frac(a)` for `a` with a good mix of 1s and 0s in its binary representation.
function hash(value::Integer, mask::V = -1 % V, magic_number::Int64 = _HASH_MAGIC_NUMBER, bits::Int = _HASH_BITS) where {V<:Integer}
    return ((value * magic_number >>> bits) & mask) % V
end

function Base.getindex(h::HashMap{K,V}, key::K, mask::V = -1 % V) where {K<:Integer, V<:Integer}
    return h.data[hash(key, mask)+1]
end

function Base.setindex!(h::HashMap{K,V}, value::V, key::K, mask::V = -1 % V) where {K<:Integer, V<:Integer}
    h.data[hash(key, mask)+1] = value
    return h
end

# Compute the minimum safe compressed length required
function max_compressed_length(in_length::Int)
    return in_length + (in_length+1) >> 8 + 16
end

# Get 8 bytes from an array and reinterpret as an LE-ordered value of type T
function reinterpret_get(::Type{T}, input::AbstractVector{UInt8}, index::Int = 1) where {T}
    return htol(reinterpret(T, input[index:index+sizeof(T)-1]))
end