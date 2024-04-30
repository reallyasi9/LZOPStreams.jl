@flagset LZOPFlags{Symbol, UInt32} begin
    1 --> :ADLER32_D
    2 --> :ADLER32_C
    3 --> :STDIN
    4 --> :STDOUT
    5 --> :NAME_DEFAULT
    6 --> :DOSISH
    7 --> :H_EXTRA_FIELD
    8 --> :H_GMTDIFF
    9 --> :CRC32_D
    10 --> :CRC32_C
    11 --> :MULTIPART
    12 --> :H_FILTER
    13 --> :H_CRC32
    14 --> :H_PATH
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

@kwarg struct LZOPArchiveHeader{M <: AbstractLZOAlgorithm, F <: AbstractLZOPFilter}
    version::VersionNumber = VersionNumber(0, 0, 0)
    lib_version::VersionNumber = VersionNumber(0, 0, 0)
    version_needed_to_extract::VersionNumber = VersionNumber(0, 9, 0)
    method::M = LZO1X_1
    flags::LZOPFlags = 0x00000000
    filter::F = NoopFilter()
    mode::UInt32 = 0o000
    mtime::DateTime = Dates.unix2datetime(0)
    header_checksum::UInt32 = 0x00000000
    extra_field_checksum::UInt32 = 0x00000000

    method_name::String16 = "unknown"
    name::String255 = "" # unnamed means using STDIN/STDOUT
    extra_field::Vector{UInt8} = Vector{UInt8}() # not used
end

mutable struct ChecksumReader{T <: IO} <: IO
    io::T
    crc::UInt32
    adler::UInt32

    ChecksumReader(io::T) where (T <: IO) = new{T}(io, 0x00000000, 0x00000001)
end

function read_le(cr::ChecksumReader, ::Type{T}) where (T)
    value = read(cr.io, T)
    cr.crc = _crc32(value, cr.crc)
    cr.adler = adler32(value, cr.adler)
    return ltoh(value)
end

function read_bytes(cr::ChecksumReader, n::Integer)
    value = Vector{UInt8}(undef, n)
    nr = readbytes!(cr.io, value, n)
    if nr != n
        throw(ErrorException("unable to read bytes from IO: exepected to read $n, read $nr"))
    end
    cr.crc = _crc32(value, cr.crc)
    cr.adler = adler32(value, cr.adler)
    return value
end

"""
    clean_filename(name) -> String

    Convert a file name to LZOP's cannonical representation.

LZOP's cannonical represention of a file name is one that removes all drive and root path information, normalizes relative traversals within the path (i.e., "." and ".."), and enforces forward slash ('/') as the directory separator.
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

function compute_lzo_method(method::UInt8, level::UInt8)::AbstractLZOAlgorithm
    if method ∉ (M_LZO1X_1, M_LZO1X_1_15, M_LZO1X_999)
        throw(ErrorException("unrecognized LZO method: $method"))
    end
    if level > 9
        throw(ErrorException("invalid LZO compression level: $level"))
    end

    # set default level based on method used
    # NOTE: levels for LZO1X_1 and LZO1X_1_15 are not used
    if level == 0
        if method == M_LZO1X_1
            level = 0x03
        elseif method == M_LZO1X_1_15
            level = 0x01
        elseif method == M_LZO1X_999
            level = 0x09
        end
    end

    method == M_LZO1X_1 && return LZO1X_1()
    method == M_LZO1X_1_15 && return LZO1X_1_15()
    method == M_LZO1X_999 && return LZO1X_999(level)
end

"""
    compute_version(ver::UInt16) -> VersionNumber

    Convert LZO/LZOP's version format to a semver VersionNumber.
"""
function compute_version(ver::UInt16)
    major = (ver & (0xf000)) >> 12
    minor = (ver & (0x0ff0)) >> 8
    patch = (ver & (0x000f))
    return VersionNumber(major, minor, patch)
end

function compute_lzo_filter(f::UInt32)
    
end

function Base.read(io::IO, ::Type{LZOPArchiveHeader})
    # until flags are read, we don't know whether CRC32 or Adler32 should be used.
    checksum_io = ChecksumReader(io)
    
    version = read_le(checksum_io, UInt16)
    if version < 0x0900
        throw(ErrorException("archive was created with a prerelease version of lzop: $version < 0x0900"))
    end
    version_needed_to_extract = 0x0000
    if version > 0x0940
        version_needed_to_extract = read_le(checksum_io, UInt16)
        if version_needed_to_extract > LibLZO.version()
            throw(ErrorException("version needed to extract archive is greater than installed version of LibLZO: $version_needed_to_extract > $(LibLZO.version())"))
        end
        if version_needed_to_extract < 0x0900
            throw(ErrorException("version needed to extract archive is a prerelease version of lzop: $version_needed_to_extract < 0x0900"))
        end
    end

    lib_version = read_le(checksum_io, UInt16)

    method = read_le(checksum_io, UInt8)
    if version >= 0x0940
        level = read_le(checksum_io, UInt8)
    else
        level = 0x00
    end

    flags = read_le(checksum_io, LZOPFlags)

    if flags & :H_FILTER
        filter = read_le(checksum_io, UInt32)
    else
        filter = 0x00000000
    end

    mode = read_le(checksum_io, UInt32)
    if flags & :STDIN
        mode = 0x00000000
    end

    mtime_low = read_le(checksum_io, UInt32)
    if version >= 0x0940
        mtime_high = read_le(checksum_io, UInt32)
    else
        mtime_high = 0x00000000
    end
    if version < 0x0120
        mtime_high = 0x00000000
        if mtime_low == typemax(UInt32)
            mtime_low = 0x00000000
        end
    end

    name_length = read_le(checksum_io, UInt8)
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
    checksum = (flags & :H_CRC32) ? checksum_io.crc : checksum_io.adler
    header_checksum = read_le(checksum_io, UInt32)
    if checksum != header_checksum
        throw(ErrorException("header checksum does not match: expected $header_checksum (H_CRC32=$(flags & :H_CRC32)), read $checksum"))
    end

    # extra data is not used, but we check it anyway
    if flags & :H_EXTRA_FIELD
        # reset the checksum calculation
        checksum_io.crc = 0x00000000
        checksum_io.adler = 0x00000001

        extra_length = read_le(checksum_io, UInt32)
        if extra_length > 0
            extra = read_bytes(checksum_io, extra_length)
        else
            extra = Vecotr{UInt8}(undef, 0)
        end

        extra_field_checksum = read_le(checksum_io, UInt32)
        extra_checksum = (flags & :H_CRC32) ? checksum_io.crc : checksum_io.adler
        if extra_checksum != extra_field_checksum
            throw(ErrorException("extra field checksum does not match: expected $extra_field_checksum (H_CRC32=$(flags & :H_CRC32)), read $extra_checksum"))
        end
    else
        extra = Vector{UInt8}(undef, 0)
        extra_field_checksum = 0x00000000
    end

    # post-compute the necessary information for extraction
    v_version = compute_version(version)
    v_lib_version = compute_version(lib_version)
    v_version_needed_to_extract = compute_version(version_needed_to_extract)

    lzo_method = compute_lzo_method(method, level)

    lzo_filter = compute_lzo_filter(filter)

end