"""
    reinterpret_get(T::Type, input, [index::Integer = 1])::T

Reinterpret bytes from `input` as an LE-ordered value of type `T`, optionally starting at `index`. This tries to be faster than `reinterpret(T, input[index:index+sizeof(T)-1])`.

`input` can be anything that is linearly indexed and `getindex(input, ::Int)` returns a type `S` for which the operator `|(::T, ::S)` is defined.
"""
function reinterpret_get(::Type{T}, input, index::Integer = 1) where {T<:Integer}
    @boundscheck checkbounds(input, index + sizeof(T) - 1)
    out = zero(T)
    @inbounds for i in 0:sizeof(T)-1
        out |= input[index + i]
        out = bitrotate(out, -8)
    end
    return out
end
reinterpret_get(::Type{UInt8}, input, index::Integer = 1) = input[index] % UInt8
reinterpret_get(::Type{Int8}, input, index::Integer = 1) = input[index] % Int8

"""
    reinterpret_next(previous::T, input::AbstractVector{UInt8}, [index::Int = 1])::T

Get the byte from `input` at `index` and push it to the LSB of `previous`, rotating off the MSB. This tries to be faster than doing `reinterpret(T, input[index:index+sizeof(T)-1])` twice by reusing the already read LSBs.
"""
function reinterpret_next(previous::T, input, index::Integer = 1) where {T<:Integer}
    @boundscheck checkbounds(input, index)
    previous <<= 8
    @inbounds previous |= input[index]
    return previous
end
reinterpret_next(::UInt8, input, index::Integer = 1) = input[index] % UInt8
reinterpret_next(::Int8, input, index::Integer = 1) = input[index] % Int8

function Base.pointer(m::Memory, i::Integer = 1)
    @boundscheck checkbounds(m, i)
    return m.ptr + i - 1
end

function Base.copyto!(d::Memory, doffs::Integer, src::AbstractArray{UInt8}, soffs::Integer, n::Integer)
    n == 0 && return d
    @boundscheck checkbounds(d, doffs + n - 1)
    @boundscheck checkbounds(src, soffs + n - 1)
    GC.@preserve d src unsafe_copyto!(pointer(d, doffs), pointer(src, soffs), n)
    return d
end

function Base.copyto!(d::AbstractArray{UInt8}, doffs::Integer, src::Memory, soffs::Integer, n::Integer)
    n == 0 && return d
    @boundscheck checkbounds(d, doffs + n - 1)
    @boundscheck checkbounds(src, soffs + n - 1)
    GC.@preserve d src unsafe_copyto!(pointer(d, doffs), pointer(src, soffs), n)
    return d
end

"""
    copyto!(dest::CircularVector, do, src::Memory, so, N)

Copy `N` elements from collection `src` starting at the linear index `so` to array `dest` starting at the index `do`. Return `dest`.

Because `CircularVector`s have circular boundary conditions on the indices, the linear index `do` may be negative, zero, or greater than `lastindex(dest)`, and the number of elements copied `N` may be greater than `length(dest)`.
"""
function Base.copyto!(dest::CircularVector{UInt8}, doffs::Integer, src::Memory, soffs::Integer, n::Integer)
    n == 0 && return dest
    soffs = n > length(dest) ? soffs + n - length(dest) : soffs
    n = min(n, length(dest))
    offset = 0
    while offset < n
        dest[doffs + offset] = src[soffs + offset]
        offset += 1
    end
    dest
end


"""
    copyto!(dest::CircularVector{T}, do, src::AbstractVector{T}, so, N)

Copy `N` elements from collection `src` starting at the linear index `so` to array `dest` starting at the index `do`. Return `dest`.

Because `CircularVector`s have circular boundary conditions on the indices, the linear index `do` may be negative, zero, or greater than `lastindex(dest)`, and the number of elements copied `N` may be greater than `length(dest)`.
"""
function Base.copyto!(dest::CircularVector{T}, doffs::Integer, src::AbstractVector{T}, soffs::Integer, n::Integer) where {T}
    n == 0 && return dest
    soffs = n > length(dest) ? soffs + n - length(dest) : soffs
    n = min(n, length(dest))
    offset = 0
    while offset < n
        dest[doffs + offset] = src[soffs + offset]
        offset += 1
    end
    dest
end

"""
    copyto!(dest::Memory, do, src::CircularVector, so, N)

Copy `N` elements from collection `src` starting at the linear index `so` to array `dest` starting at the index `do`. Return `dest`.

Because `CircularVector`s have circular boundary conditions on the indices, the linear index `so` may be negative, zero, or greater than `lastindex(src)`, and the number of elements copied `N` may be greater than `length(src)`.
"""
function Base.copyto!(dest::Memory, doffs::Integer, src::CircularVector{UInt8}, soffs::Integer, n::Integer)
    n == 0 && return dest
    offset = 0
    while offset < n
        dest[doffs + offset] = src[soffs + offset]
        offset += 1
    end
    dest
end

"""
    copyto!(dest::CircularVector, do, src::CircularVector, so, N)

Copy `N` elements from collection `src` starting at the linear index `so` to array `dest` starting at the index `do`. Return `dest`.

Because `CircularVector`s have circular boundary conditions on the indices, the linear indices `do` and `so` may be negative, zero, or greater than the last indices of `dest` and `src`, respective, and the number of elements copied `N` may be greater than the lengths of either.
"""
function Base.copyto!(dest::CircularVector, doffs::Integer, src::CircularVector, soffs::Integer, n::Integer)
    n == 0 && return dest
    offset = 0
    while offset < n
        dest[doffs + offset] = src[soffs + offset]
        offset += 1
    end
    dest
end

function Base.append!(dest::AbstractVector{UInt8}, src::Memory, start_index::Integer = 1)
    to_copy = length(src) - start_index + 1
    to_copy <= 0 && return dest
    back = length(dest) + 1
    resize!(dest, length(dest) + to_copy)
    @inbounds unsafe_copyto!(pointer(dest, back), pointer(src, start_index), to_copy)
    return dest
end


"""
    maxcopy!(dest, start_index, src)::Int

Copy as much of `src` into `dest` starting at index `start_index` as possible.

Requires `lastindex(dest)`, `length(src)`, and `copyto!(dest, start_index, src, 1, ::Int)` to be defined for `dest` and `src` types.

Returns the number of bytes copied.
"""
function maxcopy!(dest, start_index, src)
    n = min(lastindex(dest) - start_index + 1, length(src))
    @inbounds copyto!(dest, start_index, src, 1, n)
    return n
end