"""
    reinterpret_get(T::Type, input::AbstractVector{UInt8}, [index::Int = 1])::T

Reinterpret bytes from `input` as an LE-ordered value of type `T`, optionally starting at `index`.
"""
function reinterpret_get(::Type{T}, input::AbstractVector{UInt8}, index::Int = 1) where {T}
    return htol(only(reinterpret(T, input[index:index+sizeof(T)-1])))
end

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

"""
    count_matching(a::AbstractVector, b::AbstractVector)

Count the number of elements at the start of `a` that match the elements at the start of `b`.

Equivalent to `findfirst(a .!= b)`, but faster and limiting itself to the first `min(length(a), length(b))` elements.
"""
function count_matching(a::AbstractVector{T}, b::AbstractVector{T}) where {T}
    # TODO: there has to be a SIMD way to do this, but aliasing might get in the way...
    n = min(length(a), length(b))
    for i in 1:n
        if @inbounds a[i] != b[i]
            return i-1
        end
    end
    return n
end
