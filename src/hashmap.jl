# A dict-like struct that maps integers of type K into a flat vector of fixed size elements of type V
# using the same algorithm as the LZO1X1 compressor. Default (unmatched) values are always zero.
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
