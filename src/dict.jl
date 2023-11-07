# Dictionary definitions

# Compute the minimum safe compressed length required
function max_compressed_length(in_length::Int)
    return in_length + (in_length+1) >> 8 + 16
end

# Get some number of bytes from an array and reinterpret as an LE-ordered value of type T
function reinterpret_get(::Type{T}, input::AbstractVector{UInt8}, index::Int = 1) where {T}
    return htol(only(reinterpret(T, input[index:index+sizeof(T)-1])))
end