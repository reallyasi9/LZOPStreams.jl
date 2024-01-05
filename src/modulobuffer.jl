
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

# copyto! is a little strange because it ignores the buffer length
function Base.copyto!(mb::ModuloBuffer, i::Integer, src::AbstractArray, j::Integer, n::Integer)
    n == 0 && return mb
    i = mod1(i, mb.capacity)
    shift = 2 - mb.first - i
    _circshift!(mb.data, shift)
    mb.first = 1
    nmod = min(n, mb.capacity)
    # instead of writing j:j+n-1, write j+n-nmod:j+n-1
    copyto!(mb.data, 1, src, j+n-nmod, nmod)
    mb.length = max(mb.length, nmod)
    mb.first -= i - 1
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

# one-argument circshift is not defined for Julia < 1.7
# TODO: remove this when LTS is bumped.
# Copied from Julia 1.7+::
function _circshift!(v::AbstractVector, i::Integer)
    length(v) == 0 && return v
    i = mod(i, length(v))
    i == 0 && return v
    l = lastindex(v)
    reverse!(v, firstindex(v), l - i)
    reverse!(v, l - i + 1, l)
    reverse!(v)
    return v
end

"""
    resize!(buffer::ModuloBuffer, n::Integer)::ModuloBuffer

Resize `buffer` to a capacity of `n` elements by adjusting the location of the back of the buffer.

If `n < capacity(buffer)`, only the first `n` elements of `buffer` will be retained.

Attempts to avoid allocating new memory by manipulating and resizing the internal vector in
place.
"""
function Base.resize!(mb::ModuloBuffer{T}, n::Integer) where {T}
    shift = 1 - mb.first
    _circshift!(mb.data, shift)
    mb.first = 1
    mb.capacity = n
    mb.length = min(mb.length, n)
    resize!(mb.data, n)
    return mb
end

"""
    resize_front!(buffer::ModuloBuffer, n::Integer)::ModuloBuffer

Resize `buffer` to a capacity of `n` elements by adjusting the location of the front of the buffer.

If `n < capacity(buffer)`, only the _last_ `n` elements of `buffer` will be retained.

Attempts to avoid allocating new memory by manipulating and resizing the internal vector in
place.
"""
function resize_front!(mb::ModuloBuffer, n::Integer)
    if n < mb.capacity
        # push the front forward so that the length(mb.data) - n bytes are trimmed from the front instead of the back.
        rot = mod1(mb.capacity - n, mb.capacity)
        mb.first += rot
    end
    return resize!(mb, n)
end

"""
    shift_copy!(buffer::ModuloBuffer, source, i, sink, j, [n])::Tuple{Int,Int}

Copy `n` elements `source` starting at `i` to the back of `buffer`, evicting elements from the front of `buffer` to `sink` starting at `j`.

`source` must be a valid source for the `copyto!` method, and `sink` must be a valid
destination.

If not specified, `n` defaults to the minimum of the capacity of `buffer`, the number of
elements that can be copied from `source`, and the amount of free space left in `sink`.

If `n <= capacity(buffer) - length(buffer)`, then all `n` elements will be copied into the
available space in `buffer` and no elements will be evicted from the front of `buffer` into
`sink`.

Returns a tuple of the number of elements copied from `source` and the number of elements
evicted from `buffer` and copied to `sink`.
"""
function shift_copy!(mb::ModuloBuffer, source::AbstractVector, i::Integer, sink::AbstractVector, j::Integer, n::Integer)
    n == 0 && return (0,0)
    lost = max(length(mb) + n - capacity(mb), 0)
    # we can cheat here because we do know how source is indexed
    to_evict = lost
    if to_evict > 0
        eviction = min(length(mb), to_evict)
        copyto!(sink, j, mb, 1, eviction)
        to_evict -= eviction
        j += eviction
        mb.first += eviction
    end
    copyto!(sink, j, source, i, to_evict)
    append!(mb, source[i:i+n-1])
    return (n,lost)
end

function shift_copy!(mb::ModuloBuffer, source::AbstractVector, i::Integer, sink::AbstractVector, j::Integer)
    max_source = lastindex(source)-i+1
    n = min(capacity(mb), max_source)
    remainder = capacity(mb) - length(mb)
    loss = n - remainder
    if loss > 0
        max_loss = lastindex(sink)-j+1
        loss = min(loss, max_loss)
        n = remainder + loss
    end
    return shift_copy!(mb, source, i, sink, j, n)
end


# custom pretty-printing functionality follows

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