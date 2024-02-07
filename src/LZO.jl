module LZO
using LZO_jll

function __init__()
    # The LZO library initialization method takes parameters that check that the following values are consistent between the compiled library and the code calling it:
    # 1. the version of the library (must be != 0)
    # 2. sizeof(short)
    # 3. sizeof(int)
    # 4. sizeof(long)
    # 5. sizeof(lzo_uint32_t) (required to be 4 bytes, irrespective of machine architecture)
    # 6. sizeof(lzo_uint) (required to be 8 bytes, irrespective of machine architecture)
    # 7. lzo_sizeof_dict_t (size of a pointer)
    # 8. sizeof(char *)
    # 9. sizeof(lzo_voidp) (size of void *)
    # 10. sizeof(lzo_callback_t) (size of a complex callback struct)
    # If any of these arguments except the first is -1, the check is skipped.
    e = ccall((:__lzo_init_v2, liblzo2),
        Cint,
        (Cuint, Cint, Cint, Cint, Cint, Cint, Cint, Cint, Cint, Cint),
        1, -1, -1, -1, -1, -1, -1, -1, -1, -1)
    if e != 0
        throw(ErrorException("initialization of liblzo2 failed: $e"))
    end
end

function compress_minoutsize(input_len::Integer)
    # The worst-case scenario is a super-long literal, in which case the input has to be emitted in its entirety 
    # plus the appropriate commands to start a long literal and end the stream.
    # CMD(1) + LITERAL_RUN + LITERAL_REMAINDER(1) + LITERAL + EOS(3)
    return input_len ÷ 255 + input_len + 5
end

"""
    unsafe_lzo_compress!(dest::Vector{UInt8}, src, [working_memory=zeros(UInt8, 1<<12)])::Int

Compress `src` to `dest` using the LZO 1X1 algorithm.

The method is "unsafe" in that it does not check to see if the compressed output can fit into `dest` before proceeding, and may write out of bounds or crash your program if the number of bytes required to compress `src` is larger than the number of bytes available in `dest`. The method returns the number of bytes written to `dest`, which may be greater than `length(dest)`.

Pass `working_memory`, a `Vector{UInt8}` with `length(working_memory) >= 1<<12`, to reuse pre-allocated memory required by the algorithm.
"""
function unsafe_lzo_compress!(dest::Union{Vector{UInt8}, Ptr{UInt8}}, src::AbstractVector{UInt8}, working_memory::Vector{UInt8} = zeros(UInt8, 1 << 16))
    @boundscheck checkbounds(working_memory, 1<<16)
    fill!(working_memory, UInt8(0))
    size_ptr = Ref{Csize_t}()
    @ccall liblzo2.lzo1x_1_compress(src::Ptr{Cuchar}, sizeof(src)::Csize_t, dest::Ptr{Cuchar}, size_ptr::Ptr{Csize_t}, working_memory::Ptr{Cvoid})::Cint # always returns LZO_E_OK
    return size_ptr[]
end

unsafe_lzo_compress!(dest, src::AbstractString, working_memory::Vector{UInt8} = zeros(UInt8, 1 << 16)) = unsafe_lzo_compress!(dest, Base.CodeUnits(src), working_memory)

"""
    lzo_compress!(dest::Vector{UInt8}, src, [working_memory=zeros(UInt8, 1<<12)])

Compress `src` to `dest` using the LZO 1X1 algorithm.

The destination vector `dest` will be resized to fit the compressed data if necessary. Returns the modified `dest`.

Pass `working_memory`, a `Vector{UInt8}` with `length(working_memory) >= 1<<12`, to reuse pre-allocated memory required by the algorithm.
"""
function lzo_compress!(dest::Vector{UInt8}, src::AbstractVector{UInt8}, working_memory::Vector{UInt8} = zeros(UInt8, 1 << 16))
    old_size = length(dest)
    min_size = compress_minoutsize(length(src))
    if old_size < min_size
        resize!(dest, min_size)
    end

    new_size = unsafe_lzo_compress!(dest, src, working_memory)
    resize!(dest, max(new_size, old_size))
    return dest
end

lzo_compress!(dest::Vector{UInt8}, src::AbstractString, working_memory::Vector{UInt8} = zeros(UInt8, 1 << 16)) = lzo_compress!(dest, Base.CodeUnits(src), working_memory)

"""
    lzo_compress(src, [working_memory=zeros(UInt8, 1<<12)])::Vector{UInt8}

Compress `src` using the LZO 1X1 algorithm.

Returns a compressed version of `src`.

Pass `working_memory`, a `Vector{UInt8}` with `length(working_memory) >= 1<<12`, to reuse pre-allocated memory required by the algorithm.
"""
function lzo_compress(src::AbstractVector{UInt8}, working_memory::Vector{UInt8} = zeros(UInt8, 1 << 16))
    dest = UInt8[]
    return lzo_compress!(dest, src, working_memory)
end

lzo_compress(src::AbstractString, working_memory::Vector{UInt8} = zeros(UInt8, 1 << 16)) = lzo_compress(Base.CodeUnits(src), working_memory)

"""
    unsafe_lzo_decompress!(dest::Vector{UInt8}, src)::Int

Decompress `src` to `dest` using the LZO 1X1 algorithm.

The method is "unsafe" in that it does not check to see if the decompressed output can fit into `dest` before proceeding, and may write out of bounds or crash your program if the number of bytes required to decompress `src` is larger than the number of bytes available in `dest`. The method returns the number of bytes written to `dest`, which may be greater than `length(dest)`.
"""
function unsafe_lzo_decompress!(dest::Vector{UInt8}, src::AbstractVector{UInt8})
    return GC.@preserve dest unsafe_lzo_decompress!(pointer(dest), src)
end

function unsafe_lzo_decompress!(dest::Ptr{UInt8}, src::AbstractVector{UInt8})
    working_memory = UInt8[] # no working memory needed to decompress
    size_ptr = Ref{Csize_t}()
    @ccall liblzo2.lzo1x_decompress(src::Ptr{Cuchar}, sizeof(src)::Csize_t, dest::Ptr{Cuchar}, size_ptr::Ptr{Csize_t}, working_memory::Ptr{Cvoid})::Cint # always returns LZO_E_OK or crashes!
    return size_ptr[]
end

unsafe_lzo_decompress!(dest, src::AbstractString) = unsafe_lzo_decompress!(dest, Base.CodeUnits(src))

"""
    lzo_decompress!(dest::Vector{UInt8}, src)

Decompress `src` to `dest` using the LZO 1X1 algorithm.

The destination vector `dest` will be resized to fit the decompressed data if necessary. Returns the modified `dest`.
"""
function lzo_decompress!(dest::Vector{UInt8}, src::AbstractVector{UInt8})
    old_size = length(dest)
    if old_size < length(src) # just a guess
        resize!(dest, length(src))
    end

    working_memory = UInt8[] # no working memory needed to decompress
    size_ptr = Ref{Csize_t}(length(dest))
    while true
        e = @ccall liblzo2.lzo1x_decompress_safe(src::Ptr{Cuchar}, length(src)::Csize_t, dest::Ptr{Cuchar}, size_ptr::Ptr{Csize_t}, working_memory::Ptr{Cvoid})::Cint
    
        if e == -5
            resize!(dest, length(dest)*2)
            size_ptr[] = length(dest)
        elseif e != 0
            throw(ErrorException("liblzo2 decompression error: $e"))
        else
            break
        end
    end

    resize!(dest, max(size_ptr[], old_size))
    return dest
end

lzo_decompress!(dest::Vector{UInt8}, src::AbstractString) = lzo_decompress!(dest, Base.CodeUnits(src))

"""
    lzo_decompress(src)::Vector{UInt8}

Decompress `src` using the LZO 1X1 algorithm.

Returns a decompressed version of `src`.
"""
function lzo_decompress(src::AbstractVector{UInt8})
    dest = UInt8[]
    return lzo_decompress!(dest, src)
end

lzo_decompress(src::AbstractString) = lzo_decompress(Base.CodeUnits(src))


function lzo_decompress(a::Vector{UInt8}, b::Vector{UInt8})
    working_memory = UInt8[] # no working memory needed to decompress
    if isempty(b)
        resize!(b, 256)
    end
    size_ptr = Ref{Csize_t}(length(b))
    while true
        e = ccall((:lzo1x_decompress_safe, liblzo2), Cint, (Ptr{Cuchar}, Csize_t, Ptr{Cuchar}, Ptr{Csize_t}, Ptr{Cvoid}), a, sizeof(a), b, size_ptr, working_memory)
    
        if e == LZO_E_OUTPUT_OVERRUN
            resize!(b, length(b)*2)
            size_ptr[] = length(b)
        elseif e != LZO_E_OK
            throw(ErrorException("liblzo2 decompression error: $e"))
        else
            break
        end
    end
    resize!(b, size_ptr[])
    return size_ptr[]

end

end