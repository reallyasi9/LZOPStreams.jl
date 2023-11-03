# A dict-like struct that maps integers of type K into a flat vector of fixed size elements of type V
# using the same algorithm as the LZO1X1 compressor. Default (unmatched) values are always zero.
# This is not an AbstractDict because one cannot iterate over values in the map.
struct HashMap{K<:Integer, V<:Integer}
    data::Vector{V}
    magic_number::Int64
    bits::Int
    mask::V
    function HashMap{K,V}(size_bits::Int, magic_number::Int64 = 889523592379, precision_bits::Int = 28, mask::V = (1 << size_bits - 1) % V) where {K<:Integer, V<:Integer}
        len = 1 << size_bits
        return new{K,V}(zeros(V, len), magic_number, precision_bits, mask)
    end
end

Base.empty!(hm::HashMap) = fill!(hm.data, zero(eltype(hm.data)))
Base.resize!(hm::HashMap, nl::Integer) = resize!(hm.data, nl)

# Perform `floor(value * frac(a))` where `a = m / 2^b` is a fixed-width decimal number of
# fractional precision 2^b with a good mix of 1s and 0s in its binary representation.
function hash(value::Integer, magic_number::Int64, bits::Int, mask::V) where {V<:Integer}
    return ((value * magic_number >>> bits) & mask) % V
end

function Base.getindex(h::HashMap{K,V}, key::K) where {K<:Integer, V<:Integer}
    return h.data[hash(key, h.magic_number, h.bits, h.mask)+1]
end

function Base.setindex!(h::HashMap{K,V}, value::V, key::K) where {K<:Integer, V<:Integer}
    h.data[hash(key, h.magic_number, h.bits, h.mask)+1] = value
    return h
end

function replace!(h::HashMap{K,V}, key::K, value::V) where {K<:Integer, V<:Integer}
    idx = hash(key, h.magic_number, h.bits, h.mask)+1
    old_value = hm.data[idx]
    hm.data[idx] = value
    return old_value
end