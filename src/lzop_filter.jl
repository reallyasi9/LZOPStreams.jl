@enum FilterType begin
    NO_FILTER = 0
    MOD1_FILTER = 1
    MOD2_FILTER
    MOD3_FILTER
    MOD4_FILTER
    MOD5_FILTER
    MOD6_FILTER
    MOD7_FILTER
    MOD8_FILTER
    MOD9_FILTER
    MOD10_FILTER
    MOD11_FILTER
    MOD12_FILTER
    MOD13_FILTER
    MOD14_FILTER
    MOD15_FILTER
    MOD16_FILTER
    MTF_FILTER = typemax(Int32)
end

"""
    mod_filter!(data, n::Integer)

    Apply a reversable modulo sum mapping to iterable `data` in-place and return `data`.

Performs the mapping `data[i] <- (data[i] + data[i-n]) % 256` for all indices `i ∈ 1:length(data)`. All out-of-bounds values are treated as zeros.

## Arguments
- `data`: An array-like object that implements `getindex`, `setindex`, and `length`, and stores `UInt8` values.
- `n::Integer`: The number of sums to cycle.
"""
function mod_filter!(data::AbstractArray{UInt8}, n::Integer)
    n == 1 && return mod1_filter!(data)
    cache = zeros(UInt8, n)
    for i in eachindex(data)
        j = mod1(i, n)
        cache[j] += data[i]
        data[i] = cache[j]
    end
    return data
end

function mod1_filter!(data::AbstractArray{UInt8})
    cache = UInt8(0)
    for i in eachindex(data)
        cache += data[i]
        data[i] = cache
    end
    return data
end

"""
    unmod_filter!(data, n::Integer)

    Reverse the reversable modulo sum mapping to iterable `data` in-place and return `data`.

Performs the mapping `data[i] <- (data[i] - data[i-n]) % 256` for all indices `i ∈ 1:length(data)`. All out-of-bounds values are treated as zeros.

## Arguments
- `data`: An array-like object that implements `getindex`, `setindex`, and `length`, and stores `UInt8` values.
- `n::Integer`: The number of sums to cycle.
"""
function unmod_filter!(data::AbstractArray{UInt8}, n::Integer)
    n == 1 && return unmod1_filter!(data)
    cache = zeros(UInt8, n)
    for i in eachindex(data)
        j = mod1(i, n)
        data[i] -= cache[j]
        cache[j] += data[i]
    end
    return data
end

function unmod1_filter!(data::AbstractArray{UInt8})
    cache = UInt8(0)
    for i in eachindex(data)
        data[i] -= cache
        cache += data[i]
    end
    return data
end

"""
    mtf_filter!(data)

    Apply a reversable move-to-front mapping to iterable `data` in-place and return `data`.

## Arguments
- `data`: An array-like object that implements `getindex`, `setindex`, and `eachindex`, and stores `UInt8` values.
"""
function mtf_filter!(data::AbstractArray{UInt8})
    dict = UInt8.(0:255)

    for i in eachindex(data)
        cache = data[i]
        j = (findfirst(==(cache), dict) - 1) % UInt8
        data[i] = j
        while j > 0
            dict[j+1] = dict[j]
            j -= 1
        end
        dict[1] = cache
    end

    return data
end

"""
    unmtf_filter!(data)

    Reverse a reversable move-to-front mapping of iterable `data` in-place and return `data`.

## Arguments
- `data`: An array-like object that implements `getindex`, `setindex`, and `eachindex`, and stores `UInt8` values.
"""
function unmtf_filter!(data::AbstractArray{UInt8})
    dict = UInt8.(0:255)

    for i in eachindex(data)
        j = data[i] + 1
        cache = dict[j]
        data[i] = cache
        while j > 1
            dict[j] = dict[j-1]
            j -= 1
        end
        dict[1] = cache
    end

    return data
end

function lzop_filter!(data::AbstractArray{UInt8}, filter::FilterType)
    length(data) == 0 && return data
    filter == NO_FILTER && return data
    filter == MOD1_FILTER && return mod1_filter!(data)
    filter < MTF_FILTER && return mod_filter!(data, filter)
    filter == MTF_FILTER && return mtf_filter!(data)
    throw(ArgumentError("unknown filter type $filter"))
end

function lzop_unfilter!(data::AbstractArray{UInt8}, filter::FilterType)
    length(data) == 0 && return data
    filter == NO_FILTER && return data
    filter == MOD1_FILTER && return unmod1_filter!(data)
    filter < MTF_FILTER && return unmod_filter!(data, filter)
    filter == MTF_FILTER && return unmtf_filter!(data)
    throw(ArgumentError("unknown filter type $filter"))
end