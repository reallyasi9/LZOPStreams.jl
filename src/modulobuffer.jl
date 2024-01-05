
"""
    ModuloBuffer{T}(n::Integer)
    ModuloBuffer(iter)

An `AbstractVector{T}` of fixed capacity `n` with periodic boundary conditions o nthe index.

The first version of the constructor will create an empty buffer with a capacity of `n`. The
second version will copy all elements of the iterable object `iter` into a new buffer with a
capacity of `length(iter)` and element type `eltype(iter)`.

If a new element added (either with `push!`, `pushfirst!`, or `append!`) would increase the
size of the buffer past the capacity, the oldest element added will be overwritten (or the
newest element added in the case of `pushfirst!`) to maintain the fixed capacity.

If the buffer is not at capacity, then attempts to index into unfilled elements of the
buffer will result in a `BoundsError`.
"""
mutable struct ModuloBuffer{T} <: AbstractVector{T}
    data::Vector{T}
    capacity::Int
    length::Int
    first::Int # the first valid element

    ModuloBuffer{T}(n::Integer) where {T} = new{T}(Vector{T}(undef, n), n, 0, 0)
    ModuloBuffer(v) = new{eltype(v)}(Vector{eltype(v)}(v), length(v), length(v), 1)
end

@inline Base.size(mb::ModuloBuffer) = (mb.length,)
@inline Base.eltype(::ModuloBuffer{T}) where T = T
@inline Base.isempty(mb::ModuloBuffer) = mb.length == 0
@inline Base.checkbounds(::Type{Bool}, mb::ModuloBuffer, i) = true
@inline Base.IndexStyle(::Type{<:ModuloBuffer}) = IndexLinear()
@inline isfull(mb::ModuloBuffer) = mb.length == mb.capacity

@inline function _unsafe_index(mb::ModuloBuffer, i::Integer)
    return mod1(mb.first + i - 1, mb.capacity)
end

function _index(mb::ModuloBuffer, i::Integer)
    idx = _unsafe_index(mb, i)
    @boundscheck !isfull(mb) && mod1(i, mb.capacity) > mb.length && throw(BoundsError(mb, i))
    return idx
end

Base.@propagate_inbounds function Base.getindex(mb::ModuloBuffer, i::Integer)
    return mb.data[_index(mb, i)]
end

Base.@propagate_inbounds function Base.setindex!(mb::ModuloBuffer, value, i::Integer)
    mb.data[_index(mb, i)] = value
    return mb
end

function Base.push!(mb::ModuloBuffer, value)
    if mb.capacity == 0
        throw(ArgumentError("buffer capacity must be non-zero"))
    end
    if isempty(mb)
        mb.first = mb.length = 1
        @inbounds mb.data[1] = value
    else
        @inbounds mb.data[_unsafe_index(mb, mb.length + 1)] = value
        mb.first += isfull(mb) ? 1 : 0
        mb.length += isfull(mb) ? 0 : 1
    end
    return mb
end

function Base.pushfirst!(mb::ModuloBuffer, value)
    if mb.capacity == 0
        throw(ArgumentError("buffer capacity must be non-zero"))
    end
    if isempty(mb)
        mb.first = mb.length = 1
        @inbounds mb.data[1] = value
    else
        @inbounds mb.data[_unsafe_index(mb, 0)] = value
        mb.first -= 1
        mb.length += isfull(mb) ? 0 : 1
    end
    return mb
end

function Base.pop!(mb::ModuloBuffer)
    if isempty(mb)
        throw(ArgumentError("buffer must be non-empty"))
    end
    @inbounds value = mb.data[_unsafe_index(mb, mb.length)]
    mb.length -= 1
    return value
end

function Base.popfirst!(mb::ModuloBuffer)
    if isempty(mb)
        throw(ArgumentError("buffer must be non-empty"))
    end
    @inbounds value = mb.data[_unsafe_index(mb, 1)]
    mb.first += 1
    mb.length -= 1
    return value
end

function Base.append!(mb::ModuloBuffer, items)
    for value in last(items, mb.capacity)
        push!(mb, value)
    end
    return mb
end

function Base.prepend!(mb::ModuloBuffer, items)
    for value in last(reverse(items), mb.capacity)
        pushfirst!(mb, value)
    end
    return mb
end

function Base.empty!(mb::ModuloBuffer)
   mb.first = mb.length = 0
   return mb 
end

"""
    capacity(buffer::ModuloBuffer)::Int

Return the maximum number of elements `buffer` can contain.
"""
@inline function capacity(mb::ModuloBuffer)
    return mb.capacity
end

"""
    resize!(buffer::ModuloBuffer, n::Integer)::ModuloBuffer

Resize `buffer` to a capacity of `n` elements efficiently.

If `n < capacity(buffer)`, only the first `n` elements of `buffer` will be retained.

Attempts to avoid allocating new memory by manipulating and resizing the internal vector in
place.
"""
function Base.resize!(mb::ModuloBuffer{T}, n::Integer) where {T}
    shift = 1 - mb.first
    circshift!(mb.data, shift)
    mb.first = 1
    mb.capacity = n
    mb.length = min(mb.length, n)
    resize!(mb.data, n)
    return mb
end

"""
    resize_front!(buffer::ModuloBuffer, n::Integer)::ModuloBuffer

Resize `buffer` to a capacity of `n` elements efficiently.

If `n < capacity(buffer)`, only the _last_ `n` elements of `buffer` will be retained.

Attempts to avoid allocating new memory by manipulating and resizing the internal vector in
place.
"""
function resize_front!(mb::ModuloBuffer{T}, n::Integer) where {T}
    if n < mb.capacity
        # push the front forward so that the length(mb.data) - n bytes are trimmed from the front instead of the back.
        rot = mod1(mb.capacity - n, mb.capacity)
        mb.first += rot
    end
    return resize!(mb, n)
end

function Base.show_vector(io::IO, mb::ModuloBuffer)
    if isempty(mb)
        larrow = "("
        rarrow = ")"
    elseif isfull(mb)
        larrow = "(⇠"
        rarrow = "⇢)"
    else
        larrow = "(…"
        rarrow = "…)"
    end
    Base.show_vector(io, mb, larrow, rarrow)
    return nothing
end

function Base.summary(io::IO, mb::ModuloBuffer)
    print(io, "$(mb.length)/$(mb.capacity)-element $(typeof(mb))")
    return nothing
end

function Base.print_array(io::IO, mb::ModuloBuffer)
    if isfull(mb)
        larrow = "⇠"
        rarrow = "⇢"
    else
        larrow = rarrow = "…"
    end
    Base.print_matrix(io, mb, larrow, "  ", rarrow)
end