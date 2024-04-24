abstract type AbstractLZOPFilter end

"""
    ModuloSumFilter{N}

    Apply a reversable modulo sum mapping.

Performs the mapping `data[i] <- (data[i] + data[i-N]) % 256` for all indices `i ∈ 1:length(data)`. All out-of-bounds values are treated as zeros.

## Template parameters
- `N::Integer`: The number of sums to cycle.
"""
struct ModuloSumFilter{N}::AbstractLZOPFilter
    cache::Vector{UInt8}

    function ModuloSumFilter{N}() where {N}
        return new{N}(Vector{UInt8}(undef, N))
    end
end

"""
    MoveToFrontFilter

    Apply a reversable move-to-front mapping.
"""
struct MoveToFrontFilter::AbstractLZOPFilter
    dict::Vector{UInt8}

    function MoveToFrontFilter()
        return new(Vector{UInt8}(undef, 256))
    end
end

"""
    lzop_filter!(f, data) -> data

    Apply a reversable mapping to `data` in-place and return `data`.

## Arguments
- `f::AbstractLZOPFilter`: A struct specific to the kind of LZOP filter to apply to the data.
- `data::AbstractArray{UInt8}`: An array-like object of data to which the mapping is applied.
"""
function lzop_filter!(f::ModuloSumFilter{N}, data::AbstractVector{UInt8}) where {N}
    fill!(f.cache, zero(UInt8))
    i = 0
    for j in eachindex(data)
        i = mod1(i+1, N)
        f.cache[i] += data[j]
        data[j] = f.cache[i]
    end
    return data
end

# special, faster version for N=1 case
function lzop_filter!(::ModuloSumFilter{1}, data::AbstractVector{UInt8})
    cache = zero(UInt8)
    for j in eachindex(data)
        cache += data[j]
        data[j] = cache
    end
    return data
end

function lzop_filter!(f::MoveToFrontFilter, data::AbstractArray{UInt8})
    f.dict .= UInt8.(0:255)

    for j in eachindex(data)
        cache = data[j]
        i = (findfirst(==(cache), f.dict) - 1) % UInt8
        data[j] = i
        while i > 0
            f.dict[i+1] = f.dict[i]
            i -= 1
        end
        f.dict[1] = cache
    end

    return data
end

"""
    lzop_unfilter!(f, data) -> data

    Reverse the mapping to `data` in-place and return `data`.

## Arguments
- `f::AbstractLZOPFilter`: A struct specific to the kind of LZOP filter applied to the data.
- `data::AbstractArray{UInt8}`: An array-like object of data to which the mapping was applied.
"""
function lzop_unfilter!(f::ModuloSumFilter{N}, data::AbstractArray{UInt8}) where {N}
    fill!(f.cache, zero(UInt8))
    i = 0
    for j in eachindex(data)
        i = mod1(i+1, N)
        data[j] -= cache[i]
        cache[i] += data[j]
    end
    return data
end

# special, faster version for N=1 case
function lzop_unfilter!(::ModuloSumFilter{1}, data::AbstractArray{UInt8}) where {N}
    cache = zero(UInt8)
    for j in eachindex(data)
        data[j] -= cache
        cache += data[j]
    end
    return data
end

function lzop_unfilter!(f::MoveToFrontFilter, data::AbstractArray{UInt8})
    f.dict .= UInt8.(0:255)

    for j in eachindex(data)
        i = data[j] + 1
        cache = f.dict[i]
        data[j] = cache
        while i > 1
            f.dict[i] = f.dict[i-1]
            i -= 1
        end
        f.dict[1] = cache
    end

    return data
end
