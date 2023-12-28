
"""
    ModuloBuffer{T}(n::Integer)
    ModuloBuffer(v::AbstractVector{T}[, n::Integer])
    ModuloBuffer(iter[, n::Integer])

An `AbstractVector{T}` of fixed capacity `n` with periodic boundary conditions.

If not given, `n` defaults to the length of the `Vector` or iterator passed to the
constructor. If `n < length(v)`, only the first `n` elements will be copied to the buffer.

If a new element added (either with `push!`, `pushfirst!`, or `append!`) would increase the
size of the buffer past the capacity `n`, the oldest element added will be overwritten (or
the newest element added in the case of `pushfirst!`) to maintain the fixed capacity.
"""
struct ModuloBuffer{T} <: AbstractVector{T}
    data::CircularBuffer{T}

    ModuloBuffer{T}(n::Integer) where T = new{T}(CircularBuffer{T}(n))
end

ModuloBuffer(n::Integer) = ModuloBuffer{Any}(n)

ModuloBuffer(iter, n::Integer) = ModuloBuffer{eltype(iter)}(CircularBuffer(iter, n))

ModuloBuffer(iter) = ModuloBuffer{eltype(iter)}(CircularBuffer(iter))

for op in (:size, :length, :pop!, :popfirst!, :eltype, :isempty, :empty!)
    @eval Base.$op(mb::ModuloBuffer) = $op(mb.data)
end

for op in (:push!, :pushfirst!, :append!, :resize!)
    @eval Base.$op(mb::ModuloBuffer, value) = $op(mb.data, value)
end

"""
    capacity(buffer::ModuloBuffer)::Int

Return the maximum number of elements `buffer` can contain.
"""
@inline function capacity(mb::ModuloBuffer)
    return mb.data.capacity
end

@inline function _index(mb::ModuloBuffer, i::Integer)
    return mod1(mb.data.first + i - 1, mb.data.capacity)
end

Base.@propagate_inbounds function _index_checked(mb::ModuloBuffer, i::Integer)
    idx = _index(mb, i)
    @boundscheck if idx > mb.data.length
        throw(BoundsError(mb, i))
    end
    return idx
end

@inline Base.@propagate_inbounds function Base.getindex(mb::ModuloBuffer, i::Integer)
    return mb.data[_index_checked(mb, i)]
end

@inline Base.@propagate_inbounds function Base.setindex!(mb::ModuloBuffer, value, i::Integer)
    mb.data[_index_checked(mb, i)] = value
    return mb
end

@inline Base.checkbounds(::Type{Bool}, mb::ModuloBuffer, i) = true

"""
    resize!(buffer::ModuloBuffer, n::Integer)::ModuloBuffer

Resize `buffer` to a capacity of `n` elements efficiently.

If `n < capacity(buffer)`, only first `n` elements of `buffer` will be retained.

Attempts to avoid allocating new memory by manipulating and resizing the internal vector in
place.
"""
function Base.resize!(mb::ModuloBuffer{T}, n::Integer) where T
    shift = 1 - mb.data.first
    circshift!(mb.data.buffer, shift)
    mb.data.first = 1
    mb.data.capacity = n
    mb.data.length = min(mb.data.length, n)
    resize!(mb.data.buffer, n)
    return mb
end