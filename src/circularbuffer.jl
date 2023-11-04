"""
    CircularBuffer{T} <: AbstractVector{T}

A buffer for simultaneous writing to and reading from a contiguous array of memory with periodic boundries.
"""
mutable struct CircularBuffer <: AbstractVector{UInt8}
    data::CircularVector{UInt8}
    read_head::Int
    write_head::Int
    is_anchored::Bool
    anchor::Int

    CircularBuffer(vec::AbstractVector{UInt8}) = new(CircularVector{UInt8}(vec), 1, 1, false, 0)
    CircularBuffer(vec::AbstractVector{T}) where {T} = new(CircularVector{UInt8}(collect(reinterpret(UInt8, vec))), 1, 1, false, 0)
    CircularBuffer(size::Int) = new(CircularVector(Vector{UInt8}(undef, size)), 1, 1, false, 0)
    CircularBuffer() = new(CircularVector(UInt8[]), 1, 1, false, 0)
end

anchor(cb::CircularBuffer) = cb.anchor
is_anchored(cb::CircularBuffer) = cb.is_anchored
read_head(cb::CircularBuffer) = cb.read_head
write_head(cb::CircularBuffer) = cb.write_head
start(cb::CircularBuffer) = is_anchored(cb) ? anchor(cb) : read_head(cb)
free(cb::CircularBuffer) = length(cb) - (write_head(cb) - start(cb)) % length(cb)
remaining_to_read(cb::CircularBuffer) = (write_head(cb) - read_head(cb)) % length(cb)

function Base.circshift!(cb::CircularBuffer, i::Integer)
    cb.read_head += i
    cb.write_head += i
    if is_anchored(cb)
        cb.anchor += i
    end
    return circshift!(cb.data, i)
end

rebase!(cb::CircularBuffer) = length(cb) == 0 ? cb : circshift!(cb, -(start(cb) - 1) % length(cb))

function trim!(cb::CircularBuffer)
    rebase!(cb)
    resize!(parent(cb.data), write_head(cb) % length(cb) - 1)
end

Base.size(cb::CircularBuffer) = size(cb.data)
Base.getindex(cb::CircularBuffer, i::Integer) = getindex(cb.data, i)
Base.setindex!(cb::CircularBuffer, value, i::Integer) = setindex!(cb.data, value, i)

get(T::Type, cb::CircularBuffer, i::Integer) = only(reinterpret(T, cb.data[i:i+sizeof(T)-1]))
get_bytes(cb::CircularBuffer, i::Integer = read_head(cb), n::Integer = remaining_to_read(cb)) = @view(cb[i:i+n-1])

function Base.push!(cb::CircularBuffer, val)
    # If we are about to clobber the start of the circular array, shift and grow the parent at the end
    if length(cb) == 0 || (write_head(cb) % length(cb) == start(cb) % length(cb) && write_head(cb) != start(cb))
        rebase!(cb)
        push!(parent(cb.data), val)
    else
        cb[write_head(cb)] = val
    end
    cb.write_head += 1
    return cb
end

function Base.append!(cb::CircularBuffer, collections::AbstractVector...)
    for collection in collections
        if length(collection) > free(cb)
            # If we are about to clobber the start, shift and grow the parent at the end
            rebase!(cb)
            append!(parent(cb.data), collection)
        else
            cb.data[write_head(cb):write_head(cb)+length(collection)-1] = collection[:]
        end
        cb.write_head += length(collection)
    end
    return cb
end

function Base.pop!(cb::CircularBuffer)
    if (write_head(cb)-1) % length(cb) == read_head(cb) % length(cb)
        throw(ArgumentError("cannot pop buffer past read head"))
    end
    cb.write_head -= 1
    return cb[write_head(cb)]
end

function drop_anchor!(cb::CircularBuffer, i::Integer = read_head(cb))
    if is_anchored(cb)
        throw(ErrorException("buffer already anchored at $(anchor(cb))"))
    end
    cb.anchor = i
    cb.is_anchored = true
    return i
end

function weigh_anchor!(cb::CircularBuffer)
    if !is_anchored(cb)
        throw(ErrorException("buffer is not anchored"))
    end
    cb.is_anchored = false
    return anchor(cb)
end

function shift_anchor!(cb::CircularBuffer, skip::Integer = 1)
    if !is_anchored(cb)
        throw(ErrorException("buffer is not anchored"))
    end
    return cb.anchor += skip
end

shift_read_head!(cb::CircularBuffer, skip::Integer = 1) = cb.read_head += skip
