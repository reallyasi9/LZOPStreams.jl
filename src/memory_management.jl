"""
    reinterpret_get(T::Type, input::AbstractVector{UInt8}, [index::Int = 1])::T

Reinterpret bytes from `input` as an LE-ordered value of type `T`, optionally starting at `index`. This tries to be faster than `reinterpret(T, input[index:index+sizeof(T)-1])`.
"""
function reinterpret_get(::Type{T}, input::AbstractVector{UInt8}, index::Int = 1) where {T<:Integer}
    @boundscheck checkbounds(input, index + sizeof(T) - 1)
    out = zero(T)
    @inbounds for i in 0:sizeof(T)-1
        out |= input[index + i]
        out = bitrotate(out, -8)
    end
    return out
end
reinterpret_get(::Type{UInt8}, input::AbstractVector{UInt8}, index::Int = 1) = input[index]
reinterpret_get(::Type{Int8}, input::AbstractVector{UInt8}, index::Int = 1) = input[index] % Int8

"""
    reinterpret_next(previous::T, input::AbstractVector{UInt8}, [index::Int = 1])::T

Get the byte from `input` at `index` and push it to the LSB of `previous`, rotating off the MSB. This tries to be faster than doing `reinterpret(T, input[index:index+sizeof(T)-1])` twice by reusing the already read LSBs.
"""
function reinterpret_next(previous::T, input::AbstractVector{UInt8}, index::Int = 1) where {T<:Integer}
    @boundscheck checkbounds(input, index + sizeof(T) - 1)
    previous <<= 8
    previous |= input[index]
    return previous
end
reinterpret_next(::UInt8, input::AbstractVector{UInt8}, index::Int = 1) = input[index]
reinterpret_next(::Int8, input::AbstractVector{UInt8}, index::Int = 1) = input[index] % Int8

Base.@propagate_inbounds function Base.pointer(m::Memory, i::Int = 1)
    @boundscheck if i > m.size
        throw(BoundsError(m, i))
    end
    return m.ptr + i - 1
end

"""
    count_matching(a::AbstractVector, b::AbstractVector)

Count the number of elements at the start of `a` that match the elements at the start of `b`.

Equivalent to `findfirst(a .!= b)`, but faster and limiting itself to the first `min(length(a), length(b))` elements.
"""
function count_matching(a::AbstractVector{T}, b::AbstractVector{T}) where {T}
    # TODO: there has to be a SIMD way to do this, but aliasing might get in the way...
    n = min(length(a), length(b))
    @inbounds for i in 1:n
        if a[i] != b[i]
            return i-1
        end
    end
    return n
end
