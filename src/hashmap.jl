# A dict-like struct that maps integers of type K into a flat vector of fixed size elements of type V
# using the same algorithm as the LZO1X1 compressor. Default (unmatched) values are always zero.
# This is not an AbstractDict because one cannot iterate over values in the map.
"""
    HashMap{K,V}

A super-fast dictionary-like hash table of fixed size for integer keys.
"""
struct HashMap{K<:Integer, V}
    data::Vector{V}
    magic_number::K
    bits::Int
    mask::K
    function HashMap{K,V}(size_bits::Integer, magic_number::K) where {K<:Integer, V<:Number}
        len = 1 << size_bits
        mask = clamp(len-1, K)
        return new{K,V}(zeros(V, len), magic_number, size_bits, mask)
    end
    function HashMap{K,V}(size_bits::Integer, magic_number::K) where {K<:Integer, V}
        len = 1 << size_bits
        mask = clamp(len-1, K)
        return new{K,V}(Vector{V}(undef, len), magic_number, size_bits, mask)
    end
end

Base.empty!(hm::HashMap) = fill!(hm.data, zero(eltype(hm.data)))

# Perform `floor(value * frac(a))` where `a = m / 2^b` is a fixed-width decimal number of
# fractional precision 2^b with a good mix of 1s and 0s in its binary representation.
"""
    multiplicative_hash(value, magic_number, bits, [mask::V = typemax(UInt64)])

Hash `value` into a type `V` using multiplicative hashing.

This method performs `floor((value * magic_number % W) / (W / M))` where `W = 2^64`, `M = 2^m`, and
`magic_number` is relatively prime to `W`, is large, and has a good mix of 1s and 0s in its
binary representation. In modulo `2^64` arithmetic, this becomes `(value * magic_number) >>> m`.
"""
function multiplicative_hash(value::T, magic_number::Integer, bits::Int) where {T<:Integer}
    return ((unsigned(value) * unsigned(magic_number)) >>> (sizeof(T)*8 - bits)) & ((1 << bits) - 1) % T
end

function Base.getindex(h::HashMap{K,V}, key::K) where {K<:Integer, V}
    return h.data[multiplicative_hash(key, h.magic_number, h.bits)+1]
end

function Base.setindex!(h::HashMap{K,V}, value::V, key::K) where {K<:Integer, V}
    h.data[multiplicative_hash(key, h.magic_number, h.bits)+1] = value
    return h
end

function replace!(h::HashMap{K,V}, key::K, value::V) where {K<:Integer, V}
    idx = multiplicative_hash(key, h.magic_number, h.bits)+1
    old_value = h.data[idx]
    h.data[idx] = value
    return old_value
end