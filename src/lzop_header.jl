@flagset LZOPFlags {Symbol, UInt32} begin
    0x1 --> :ADLER32_D
    0x2 --> :ADLER32_C
    0x4 --> :STDIN
    0x8 --> :STDOUT
    0x10 --> :NAME_DEFAULT
    0x20 --> :DOSISH
    0x40 --> :H_EXTRA_FIELD
    0x80 --> :H_GMTDIFF
    0x100 --> :CRC32_D
    0x200 --> :CRC32_C
    0x400 --> :MULTIPART
    0x800 --> :H_FILTER
    0x1000 --> :H_CRC32
    0x2000 --> :H_PATH
end

@enum LZOPOS begin
    OS_FAT = 0
    OS_AMIGA = 0x01000000
    OS_VMS = 0x02000000
    OS_UNIX = 0x03000000
    OS_VM_CMS = 0x04000000
    OS_ATARI = 0x05000000
    OS_OS2 = 0x06000000
    OS_MAC9 = 0x07000000
    OS_Z_SYSTEM = 0x08000000
    OS_CPM = 0x09000000
    OS_TOPS20 = 0x0a000000
    OS_NTFS = 0x0b000000
    OS_QDOS = 0x0c000000
    OS_ACORN = 0x0d000000
    OS_VFAT = 0x0e000000
    OS_MFS = 0x0f000000
    OS_BEOS = 0x10000000
    OS_TANDEM = 0x11000000
end

@enum LZOPCharacterSet begin
    CS_NATIVE = 0x00000000
    CS_LATIN1 = 0x00100000
    CS_DOS = 0x00200000
    CS_WIN32 = 0x00300000
    CS_WIN16 = 0x00400000
    CS_UTF8 = 0x00500000
end

# LZOP only allows three methods for LZO compresison
@enum LZOPMethod begin
    M_LZO1X_1 = 0x01
    M_LZO1X_1_15 = 0x02
    M_LZO1X_999 = 0x03
end

@kwdef struct LZOPArchiveHeader{M <: AbstractLZOAlgorithm, F <: AbstractLZOPFilter}
    version::VersionNumber = LZOP_VERSION_NUMBER
    lib_version::VersionNumber = LZO_LIB_VERSION_NUMBER
    version_needed_to_extract::VersionNumber = LZOP_MIN_VERSION_NUMBER
    method::M = M()
    flags::LZOPFlags = typemin(LZOPFlags)
    filter::F = F()
    mode::UInt32 = 0o0000
    mtime::DateTime = unix2datetime(0)

    name::String255 = "" # unnamed means using STDIN/STDOUT
    extra_field::Vector{UInt8} = Vector{UInt8}(undef, 0) # not used
end

"""
    write_be(io, value) -> Int

    Write `value` to `io` in "big-endian" (network) byte order.
"""
write_be(io::IO, x) = write(io, hton(x))

"""
    read_through_be(src, dest, T) -> value::T

    Read a value of type 'T' from 'src', copying it _verbatim_ to 'dest' and returning the value _converted_ to host byte order from "big-endian" (network) byte order.
"""
function read_through_be(src::IO, dest::IO, T::Type)
    value = read(src, T)
    write(dest, value)
    return ntoh(value)
end

"""
    clean_name(name) -> String

    Convert a file name to LZOP's cannonical representation.

LZOP's cannonical represention of a file name is one that removes all drive and root path information, normalizes relative traversals within the path (i.e., "." and ".."), and enforces forward slash ('/') as the directory separator.

Note that LZOP has the facilities to understand path string encodings, but the official version does not use them and simply uses the native representation on the machine that is compressing/decompressing the file.
"""
function clean_name(name::AbstractString)
    drive_path = splitdrive(name)
    norm_path = normpath(drive_path[2])
    if isdirpath(norm_path)
        throw(ErrorException("path appears to be a directory: $name"))
    end
    splits = splitpath(norm_path)
    if isabspath(norm_path)
        popfirst!(splits)
    end
    return join(splits, "/")
end

"""
    translate_method(method::UInt8, level::UInt8) -> AbstractLZOAlgorithm

    Translate the encoded `method` and `level` bytes from an LZOP header to an LZO algorithm.

`level` is ignored for all algorithms except for LZO1X_999.
"""
function translate_method(method::UInt8, level::UInt8)::AbstractLZOAlgorithm
    if method ∉ UInt8.((M_LZO1X_1, M_LZO1X_1_15, M_LZO1X_999))
        throw(ErrorException("unrecognized LZO method: $method"))
    end
    if level > 9
        throw(ErrorException("invalid LZO compression level: $level"))
    end

    # set default level based on method used
    # NOTE: levels for LZO1X_1 and LZO1X_1_15 are not used
    if level == 0 && method == UInt8(M_LZO1X_999)
        level = 0x09
    end

    method == UInt8(M_LZO1X_1) && return LZO1X_1()
    method == UInt8(M_LZO1X_1_15) && return LZO1X_1_15()
    method == UInt8(M_LZO1X_999) && return LZO1X_999(compression_level=level)
end

"""
    translate_method(algorithm, [level::Integer]) -> (method,level)

    Translate the given `AbstractLZOAlgorithm` to LZOP-encoded method and level bytes for writing to an LZOP header.

If `level` is given, that level will overwrite the defaulf value for the algorithm.
"""
function translate_method(::LZO1X_1, level::Integer = 0x03)
    if level > 9
        throw(ErrorException("invalid LZO compression level: $level"))
    end
    return UInt8(M_LZO1X_1), UInt8(level)
end

function translate_method(::LZO1X_1_15, level::Integer = 0x01)
    if level > 9
        throw(ErrorException("invalid LZO compression level: $level"))
    end
    return UInt8(M_LZO1X_1_15), UInt8(level)
end

function translate_method(m::LZO1X_999, level::Integer = UInt8(m.compression_level))
    if level > 9
        throw(ErrorException("invalid LZO compression level: $level"))
    end
    return UInt8(M_LZO1X_999), UInt8(level)
end


"""
    translate_version(ver::UInt16) -> VersionNumber

    Convert LZO/LZOP's version format to a semver VersionNumber.
"""
function translate_version(ver::UInt16)
    major = (ver & (0xf000)) >> 12
    minor = (ver & (0x0f00)) >> 8
    patch = (ver & (0x00f0)) >> 4
    prerelease = (ver & (0x000f))
    prerelease_tuple = prerelease == 0 ? () : (prerelease,)
    return VersionNumber(major, minor, patch, prerelease_tuple)
end

"""
    translate_version(ver::VersionNumber) -> UInt16

    Convert a semver VersionNumber to LZO/LZOP's version format.
"""
function translate_version(ver::VersionNumber)
    return UInt16(((ver.major & 0xf) << 12) | ((ver.minor & 0xf) << 8) | ((ver.patch & 0xf) << 4) | (isempty(ver.prerelease) ? 0x0 : first(ver.prerelease) & 0xf))
end

"""
    translate_filter(f::UInt32) -> AbstractLZOPFilter

    Translate an encoded LZOP filter code to an `AbstractLZOPFilter` struct.
"""
function translate_filter(f::UInt32)::AbstractLZOPFilter
    # Note: there is no way to specify use of the move-to-front filter, even though the filter is defined in the official LZOP code.
    if f == 0 || f > 16
        return NoopFilter()
    else
        N = Int(f)
        return ModuloSumFilter{N}()
    end
end

"""
    translate_filter(f::AbstractLZOPFilter) -> UInt32

    Translate an `AbstractLZOPFilter` struct to an encoded LZOP filter code.
"""
function translate_filter(::ModuloSumFilter{N}) where (N)
    return UInt32(N)
end

function translate_filter(::NoopFilter)
    return zero(UInt32)
end

"""
    translate_mtime(low::UInt32, high::UInt32) -> DateTime

    Translate an encoded low/high number of seconds to a DateTime.
"""
function translate_mtime(low::UInt32, high::UInt32)
    return Dates.unix2datetime((UInt64(high) << 32) | UInt64(low))
end

"""
    translate_mtime(mtime::DateTime) -> (low,high)

    Translate a DateTime an encoded low/high number of seconds.
"""
function translate_mtime(mtime::DateTime)
    seconds = round(UInt64, Dates.datetime2unix(mtime))
    low = UInt32(seconds & 0xffffffff)
    high = UInt32(seconds >> 32)
    return low, high
end

function Base.read(io::IO, ::Type{LZOPArchiveHeader})
    # until flags are read, we don't know whether CRC32 or Adler32 should be used.
    checksum_io = ChecksumWrapper(io)
    
    version = translate_version(read_be(checksum_io, UInt16))
    if version < LZOP_MIN_VERSION_NUMBER
        throw(ErrorException("archive was created with an unreleased version of lzop: $version < $LZOP_MIN_VERSION_NUMBER"))
    end
    lib_version = translate_version(read_be(checksum_io, UInt16))
    version_needed_to_extract = v"0"
    if version >= v"0.9.4"
        version_needed_to_extract = translate_version(read_be(checksum_io, UInt16))
        if version_needed_to_extract > LZOP_VERSION_NUMBER
            throw(ErrorException("version needed to extract archive is greater than this version understands: $version_needed_to_extract > $LZOP_VERSION_NUMBER"))
        end
        if version_needed_to_extract < LZOP_MIN_VERSION_NUMBER
            throw(ErrorException("version needed to extract archive is an unreleased version of lzop: $version_needed_to_extract < $LZOP_MIN_VERSION_NUMBER"))
        end
    end

    method = read_be(checksum_io, UInt8)
    if version >= v"0.9.4"
        level = read_be(checksum_io, UInt8)
    else
        level = 0x00
    end

    flags = LZOPFlags(read_be(checksum_io, UInt32))

    if :H_FILTER in flags
        filter = read_be(checksum_io, UInt32)
    else
        filter = 0x00000000
    end

    mode = read_be(checksum_io, UInt32)
    if :STDIN in flags
        mode = 0x00000000
    end

    mtime_low = read_be(checksum_io, UInt32)
    if version >= v"0.9.4"
        mtime_high = read_be(checksum_io, UInt32)
    else
        mtime_high = 0x00000000
    end
    # this can never happen
    # if version < v"0.1.2"
    #     mtime_high = 0x00000000
    #     if mtime_low == typemax(UInt32)
    #         mtime_low = 0x00000000
    #     end
    # end

    name_length = read_be(checksum_io, UInt8)
    if name_length > 0
        name = String(read_bytes(checksum_io, name_length))
        # Weirdly, this isn't an error
        try
            name = clean_name(name)
        catch
            name = ""
        end
    else
        name = ""
    end

    # checksum has been computed
    checksum = (:H_CRC32 in flags) ? checksum_io.crc : checksum_io.adler
    header_checksum = read_be(checksum_io, UInt32)
    if checksum != header_checksum
        throw(ErrorException("header checksum does not match: expected $header_checksum (H_CRC32=$(:H_CRC32 in flags)), read $checksum"))
    end

    # extra data is not used, but we check it anyway
    if :H_EXTRA_FIELD in flags
        # reset the checksum calculation
        reset_checksum!(checksum_io)

        extra_length = read_be(checksum_io, UInt32)
        if extra_length > 0
            extra = read_bytes(checksum_io, extra_length)
        else
            extra = Vecotr{UInt8}(undef, 0)
        end

        extra_field_checksum = read_be(checksum_io, UInt32)
        extra_checksum = (:H_CRC32 in flags) ? checksum_io.crc : checksum_io.adler
        if extra_checksum != extra_field_checksum
            throw(ErrorException("extra field checksum does not match: expected $extra_field_checksum (H_CRC32=$(:H_CRC32 in flags)), read $extra_checksum"))
        end
    else
        extra = Vector{UInt8}(undef, 0)
        extra_field_checksum = 0x00000000
    end

    # post-compute the objects in the header
    lzo_method = translate_method(method, level)

    lzo_filter = translate_filter(filter)

    mtime = translate_mtime(mtime_low, mtime_high)

    return LZOPArchiveHeader{lzo_method, lzo_filter}(
        version,
        lib_version,
        version_needed_to_extract,
        lzo_method,
        flags,
        lzo_filter,
        mode,
        mtime,
        name,
        extra_field,
    )
end

function Base.write(io::IO, header::LZOPArchiveHeader)
    checksum_io = ChecksumWrapper(io)

    nb = 0

    nb += write_be(checksum_io, translate_version(header.version))
    nb += write_be(checksum_io, translate_version(header.lib_version))
    nb += write_be(checksum_io, translate_version(header.version_needed_to_extract))
    nb += write_be(checksum_io, translate_method(header.method)) # note: includes level
    nb += write_be(checksum_io, UInt32(header.flags))
    if :H_FILTER in header.flags
        nb += write_be(checksum_io, translate_filter(header.filter))
    end
    nb += write_be(checksum_io, header.mode)
    nb += write_be(checksum_io, translate_mtime(header.mtime)) # note: writes both low and high bytes
    nb += write_be(checksum_io, UInt8(length(header.name)))
    if length(header.name) > 0
        nb += write_bytes(checksum_io, codeunits(header.name))
    end
    if :H_CRC32 in header.flags
        nb += write_be(checksum_io, checksum_io.crc)
    else
        nb += write_be(checksum_io, checksum_io.adler)
    end

    if :H_EXTRA_FIELD in header.flags
        reset!(checksum_io)

        nb += write_be(checksum_io, UInt32(length(header.extra_field)))
        nb += write_bytes(checksum_io, extra.header_field)
        if :H_CRC32 in header.flags
            nb += write_be(checksum_io, checksum_io.crc)
        else
            nb += write_be(checksum_io, checksum_io.adler)
        end
    end

    return nb
end