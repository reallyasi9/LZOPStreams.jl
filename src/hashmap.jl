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

"""
    replace_all_matching!(h::HashMap, input, input_start, output, output_start)

Count the number of elements at the start of `input` that match the elements at the start of `output`, putting the matching indices of `input` as values into `h` keyed by the `K` integer read from `input` at that index.

Returns the number of matching bytes found (not necessarily equal to the number of `K`s put into `h`).
"""
function replace_all_matching!(h::HashMap{K,V}, input::Union{AbstractVector{UInt8}, Memory}, input_start::Int, output::Union{AbstractVector{UInt8}, Memory}, output_start::Int) where {K<:Integer,V}
    n = min(length(input) - input_start, length(output) - output_start)
    # the first sizeof(K) elements need to be checked byte-by-byte
    for i in 0:sizeof(K)-1
        if input[input_start + i] != output[output_start + i]
            return i
        end
    end
    # now all keys can be put into the HashMap
    input_value = reinterpret_get(K, input, input_start)
    setindex!(h, input_start, input_value)
    
    @inbounds for i in sizeof(K):n-sizeof(K)+1
        if input[input_start + i] != output[output_start + i]
            return i-1
        end
        input_value = reinterpret_next(input_value, input, input_start + i)
        setindex!(h, input_start + i, input_value)
    end

    # we cannot match on the last sizeof(K)-1 values
    return n-sizeof(K)+1
end