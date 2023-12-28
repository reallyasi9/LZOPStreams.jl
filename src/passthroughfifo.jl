"""
    PassThroughFIFO <: AbstractVector{UInt8}

A FIFO (first in, first out) that buffers data pushed into it and pushes out older data to a sink when new data is prepended.
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

function flush!(p::PassThroughFIFO, sink::AbstractVector{UInt8})
    n = min(length(p), length(sink))
    @inbounds sink[1:n] = p[1:n]
    return n
end

"""
    pushout!(p::PassThroughFIFO, source, source_start, sink, sink_start)

Push as much of `source` into the FIFO as it can hold, pushing out stored data to `sink`.

Until `p` is full, elements from `source` will be added to the FIFO and no elements will be pushed out to `sink`. Once `p` is full, elements of `source` up to `capacity(p)` will be added to the FIFO and the older elements will be pushed to `sink`.

Returns a tuple of the number of elements read from `source` and the number of elements written to `sink`.
"""
function pushout!(p::PassThroughFIFO, source::AbstractVector{UInt8}, sink::AbstractVector{UInt8})
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

function repeatout!(p::PassThroughFIFO, lookback::Integer, n::Integer, sink::AbstractVector{UInt8})
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