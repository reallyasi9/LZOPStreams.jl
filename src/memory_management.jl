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

function Base.pointer(m::Memory, i::Int = 1)
    return m.ptr + i - 1
end

function Base.unsafe_copyto!(dest::AbstractVector{UInt8}, di::Integer, src::Memory, si::Integer, N::Integer)
    GC.@preserve dest unsafe_copyto!(pointer(dest, di), pointer(src, si), N)
    return dest
end

function Base.unsafe_copyto!(dest::Memory, di::Integer, src::AbstractVector{UInt8}, si::Integer, N::Integer)
    GC.@preserve src unsafe_copyto!(pointer(dest, di), pointer(src, si), N)
    return dest
end

function Base.copyto!(dest::Memory, di::Integer, src::AbstractVector{UInt8}, si::Integer, N::Integer)
    @boundscheck checkbounds(dest, di + N - 1)
    unsafe_copyto!(dest, di, src, si, N)
    return dest
end

function Base.copyto!(dest::AbstractVector{UInt8}, di::Integer, src::Memory, si::Integer, N::Integer)
    @boundscheck checkbounds(dest, di + N - 1)
    unsafe_copyto!(dest, di, src, si, N)
    return dest
end

function Base.copyto!(dest::CircularVector{UInt8}, di::Integer, src::Memory, si::Integer, N::Integer)
    @inbounds for i in 0:N-1
        dest[di+i] = src[si+i]
    end
    return dest
end

function Base.copyto!(dest::Memory, di::Integer, src::CircularVector{UInt8}, si::Integer, N::Integer)
    @boundscheck checkbounds(dest, di + N - 1)
    @inbounds for i in 0:N-1
        dest[di+i] = src[si+i]
    end
    return dest
end

function Base.append!(dest::AbstractVector{UInt8}, src::Memory, si::Integer = 1)
    return append!(dest, @view(unsafe_wrap(Vector{UInt8}, src.ptr, src.size)[si:end]))
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