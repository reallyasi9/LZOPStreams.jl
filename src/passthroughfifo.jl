"""
    PassThroughFIFO <: AbstractVector{UInt8}

A FIFO (first in, first out) that buffers data pushed into it and pushes out older data to a sink when new data is prepended.
"""
mutable struct PassThroughFIFO <: AbstractVector{UInt8}
    data::CircularVector{UInt8}
    write_head::Int

    PassThroughFIFO(length::Integer) = new(CircularVector{UInt8}(zeros(UInt8, length)), 1)
end

capacity(p::PassThroughFIFO) = length(p.data)
Base.size(p::PassThroughFIFO) = (min(capacity(p), p.write_head-1),)
Base.checkbounds(::Type{Bool}, p::PassThroughFIFO, i::Integer) = 1 <= i < p.write_head
function Base.getindex(p::PassThroughFIFO, i)
    @boundscheck checkbounds(p, i)
    getindex(p.data, i)
end
function Base.empty!(p::PassThroughFIFO)
    p.write_head = 1
    return p
end

function flush!(p::PassThroughFIFO, sink::Union{Memory, AbstractVector{UInt8}}, sink_start::Integer)
    to_flush = length(p)
    start_idx = p.write_head <= to_flush ? 1 : p.write_head

    copyto!(sink, sink_start, p.data, start_idx, to_flush)
    empty!(p)
    return to_flush
end

"""
    prepend!(p::PassThroughFIFO, source, source_start, sink, sink_start)

Push as much of `source` (starting at `source_start`) into the FIFO as it can hold, pushing out stored data to `sink` (starting at `sink_start`).

Until `p` is full, elements from `source` will be added to the FIFO and no elements will be pushed out to `sink`. Once `p` is full, elements of `source` up to `capacity(p)` will be added to the FIFO and the older elements will be pushed to `sink`.

Returns a tuple of the number of elements read from `source` and the number of elements written to `sink`.
"""
function prepend!(p::PassThroughFIFO, source::Union{Memory, AbstractVector{UInt8}}, source_start::Integer, sink::Union{Memory, AbstractVector{UInt8}}, sink_start::Integer, N::Integer)
    source_length = (length(source) - source_start + 1) % Int
    to_copy = min(source_length, length(p.data), N)
    
    # if it fits, just put it in
    available = length(p.data) - p.write_head + 1
    if available > 0
        to_expel = 0
        to_copy = min(available, to_copy)
    else
        to_expel = to_copy
        copyto!(sink, sink_start, p.data, p.write_head, to_expel)
    end

    copyto!(p.data, p.write_head, source, source_start, to_copy)
    p.write_head += to_copy

    return to_copy, to_expel
end

function pushout!(p::PassThroughFIFO, value::UInt8, sink::Union{Memory, AbstractVector{UInt8}}, sink_start::Int)
    # if it fits, just put it in
    available = length(p.data) - p.write_head + 1
    if available > 0
        p.data[p.write_head] = value
        p.write_head += 1
        return 0
    end

    sink[sink_start], p.data[p.write_head] = p.data[p.write_head], value
    p.write_head += 1
    return 1
end

function self_copy_and_output!(p::PassThroughFIFO, lookback::Int, sink::Union{Memory, AbstractVector{UInt8}}, sink_start::Int, N::Int)
    n_written = 0
    while N >= lookback
        _, expelled = prepend!(p, p.data, p.write_head - lookback, sink, sink_start + n_written, lookback)
        N -= lookback
        n_written += expelled
    end
    _, expelled = prepend!(p, p.data, p.write_head - lookback, sink, sink_start + n_written, N)
    n_written += expelled
    return n_written
end