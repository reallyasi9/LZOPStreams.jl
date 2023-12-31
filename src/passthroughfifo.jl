"""
    PassThroughFIFO <: AbstractVector{UInt8}

A FIFO (first in, first out data structure) that buffers data pushed into the front of it
and, when full, pushes out older data from the back to a sink.
"""
struct PassThroughFIFO <: AbstractVector{UInt8}
    data::ModuloBuffer{UInt8}
    PassThroughFIFO(length::Integer) = new(ModuloBuffer{UInt8}(length))
end

@inline capacity(p::PassThroughFIFO) = capacity(p.data)
@inline Base.size(p::PassThroughFIFO) = size(p.data)
@inline Base.checkbounds(::Type{Bool}, p::PassThroughFIFO, i) = checkbounds(Bool, p.data, i)
@inline Base.getindex(p::PassThroughFIFO, i) = getindex(p.data, i)
@inline Base.empty!(p::PassThroughFIFO) = empty!(p.data)
@inline Base.append!(p::PassThroughFIFO, a) = append!(p.data, a)
@inline available(p::PassThroughFIFO) = capacity(p) - length(p)
@inline Base.isempty(p::PassThroughFIFO) = isempty(p.data)

"""
    flush!(p::PassThroughFIFO, sink::AbstractVector{UInt8})

Copy all the data in `p` to the front of `sink`.

Returns the number of bytes copied, equal to `min(length(p), length(sink))`. If
`length(sink) >= length(p)`, `isempty(p) == true` after the flush, else
`length(p)` will be equal to the number of bytes that could not be pushed to `sink`.
"""
function flush!(p::PassThroughFIFO, sink::AbstractVector{UInt8})
    n = min(length(p), length(sink))
    @inbounds sink[1:n] = p[1:n]
    if n == length(p)
        empty!(p)
    else
        resize_front!(p.data, length(p)-n)
    end
    return n
end

"""
    pushout!(p::PassThroughFIFO, source, sink::AbstractVector{UInt8})

Push as much of `source` into the FIFO as it can hold, pushing out stored data to `sink`.

The argument `source` can be an `AbstractVector{UInt8}` or a single `UInt8` value.

Until `p` is full, elements from `source` will be added to the FIFO and no elements will be
pushed out to `sink`. Once `p` is full, elements of `source` up to `capacity(p)` will be
added to the FIFO and the older elements will be pushed to `sink`.

Returns a tuple of the number of elements read from `source` and the number of elements
written to `sink`.

See [`repeatout!`](@ref).
"""
function pushout!(
    p::PassThroughFIFO,
    source::AbstractVector{UInt8},
    sink::AbstractVector{UInt8},
)
    a = available(p)

    if a > 0
        to_copy = min(length(source), a)
        to_expel = 0
    else
        to_copy = min(capacity(p), length(source), length(sink))
        to_expel = to_copy
    end

    sink[1:to_expel] = p[1:to_expel]
    append!(p, source[1:to_copy])

    return to_copy, to_expel
end

function pushout!(p::PassThroughFIFO, value::UInt8, sink::AbstractVector{UInt8})
    # if it fits, just put it in
    if available(p)
        push!(p, value)
        return 0
    end

    # if nothing can be expelled, don't do anything
    if length(sink) == 0
        return 0
    end

    # otherwise, pop and push
    sink[begin] = popfirst!(p)
    push!(p, value)
    return 1
end

"""
    repeatout!(p::PassThroughFIFO, lookback::Integer, n::Integer, sink::AbstractVector{UInt8})

Append `n` values starting from `lookback` bytes from the end of `p` to the front of `p`.

Once `p` is full, any bytes that are appended to the front of `p` will cause bytes from the
back to be expelled into the front of `sink`.

This method works even if `n > lookback`, in which case the bytes that were appended to the
    front of `p` first will be repeated.

Returns the number of bytes expelled from `p` into `sink`.
"""
function repeatout!(
    p::PassThroughFIFO,
    lookback::Integer,
    n::Integer,
    sink::AbstractVector{UInt8},
)
    n_expelled = 0
    sl = length(sink)
    while n > 0 && n_expelled < sl
        to_expel = min(n, lookback, sl, length(p))
        sink[n_expelled+1:n_expelled+to_expel] = p[-lookback:-lookback+to_expel]
        n -= to_expel
        n_expelled += to_expel
    end
    return n_expelled
end