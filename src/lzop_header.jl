@flagset LZOPFlags {Symbol, UInt32} begin
    0x1 --> :ADLER32_D # mutually exclusive with CRC32_D
    0x2 --> :ADLER32_C # mutually exclusive with CRC32_C
    0x4 --> :STDIN
    0x8 --> :STDOUT
    0x10 --> :NAME_DEFAULT
    0x20 --> :DOSISH
    0x40 --> :H_EXTRA_FIELD # not used in reference code
    0x80 --> :H_GMTDIFF # not used in reference code
    0x100 --> :CRC32_D # mutually exclusive with ADLER32_D
    0x200 --> :CRC32_C # mutually exclusive with ADLER32_C
    0x400 --> :MULTIPART
    0x800 --> :H_FILTER
    0x1000 --> :H_CRC32
    0x2000 --> :H_PATH
end

# The reference code names these with the prefix "OS", which is preserved here, but these actually enumerate filesystems and not operating systems.
# The reference code defines these values but does not use them.
@enum LZOPFileSystem::UInt32 begin
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
    OS_MASK = 0xff000000
end

# The reference code defines these values but does not use them.
@enum LZOPCharacterSet::UInt32 begin
    CS_NATIVE = 0x00000000
    CS_LATIN1 = 0x00100000
    CS_DOS = 0x00200000
    CS_WIN32 = 0x00300000
    CS_WIN16 = 0x00400000
    CS_UTF8 = 0x00500000
    CS_MASK = 0x00f00000
end

const ENCODING_LOOKUP = Dict{LZOPCharacterSet, String}(
    CS_NATIVE => "UTF-8",
    CS_LATIN1 => "LATIN1",
    CS_DOS => "CP437",
    CS_WIN32 => "UTF-32LE",
    CS_WIN16 => "UTF-16LE",
    CS_UTF8 => "UTF-8",
)

const CODEPAGE_LOOKUP = Dict{String, LZOPCharacterSet}(
    "UTF-8" => CS_NATIVE,
    "LATIN1" => CS_LATIN1,
    "CP437" => CS_DOS,
    "UTF-32LE" => CS_WIN32,
    "UTF-16LE" => CS_WIN16,
    "UTF-8" => CS_UTF8,
)

# The reference code only allows three methods for LZO compresison.
@enum LZOPMethod::UInt8 begin
    M_LZO1X_1 = 0x01
    M_LZO1X_1_15 = 0x02
    M_LZO1X_999 = 0x03
end

"""
    LZOPFileHeader

    A struct that represents the data stored at the head of each file entry in an LZOP archive.

There is no official documentation for the structure of the LZOP file header: this implementation was reverse-engineered from the open-source LZOP code. The data stored in the LZOP file header appears to be dependenant on the version of LZOP that was used to encode it. The table below describes what is present in each of the versions of the header. All word values (integer values of byte length > 1) are stored in network ("big endian", or MSB first) format.

| Value | Number of bytes | Description | Starting byte (v0.1.2) | Starting byte (v0.9.0) | Starting byte (v0.9.4+) |
|----:|:----|:----|:----|:----|:----|
| `version` | 2 | Version of LZOP program used to encode the header | 1 | 1 | 1 |
| `lib_version` | 2 | Version of LZO library used to compress the data | 3 | 3 | 3 |
| `version_needed_to_extract` | 2 | Minimum version of LZOP program needed to correctly extract the file | - | - | 5 |
| `method` | 1 | Compression method used to compress data | 5 | 5 | 7 |
| `level` | 1 | Compression level used to compress data | - | - | 8 |
| `flags` | 4 | Bit set of options used to compress data | 6 | 6 | 9 |
| `mode` | 4 | File mode to be applied to the file after decompressing data | 10 | 10 | 13 |
| `mtime_low` | 4 | File modified time in seconds since Unix epoch (low bytes) | 14 | 14 | 17 |
| `mtime_high` | 4 | File modified time in seconds since Unix epoch (high bytes) | - | 18 | 21 |
| `name_length` | 1 | Length of file name in bytes | 18 | 22 | 25 |
| `name` | `name_length` | File name | 19 | 23 | 26 |
| `checksum` | 4 | CRC-32 or Adler-32 checksum of all bytes read from the header so far | `19 + name_length` | `23 + name_length` | `25 + name_length` |

The `name` field encodes the name of the file at the time of compression. Because it is a single byte, the file name is truncated to the first 255 bytes. The name is stored in Julia native format (UTF-8) by default.

If `flags & 0x800 != 0`, then a 4-byte "filter" field follows the "flag" field. It describes the reversible filter used when compressing the data.

If `flags & 0x40 != 0`, then an additional "extra field" is appended to the header. This extra field has the following byte layout:

| Value | Number of bytes | Description | Starting byte after header |
|----:|:----|:----|:----|
| `extra_length` | 4 | Length of extra field | 1 |
| `data` | `extra_length` | Extra data | 5 |
| `checksum` | 4 | CRC-32 or Adler-32 checksum of all extra field bytes including the length | `5 + extra_length` |

The checksum that is used in both the header and the extra field is determined one of the bit flags: if `flags & 0x1000 != 0`, then CRC-32 is used; otherwise, Adler-32 is used.
"""
@kwdef struct LZOPFileHeader{M <: AbstractLZOAlgorithm, F <: AbstractLZOPFilter}
    version::UInt16 = LZOP_VERSION
    lib_version::UInt16 = LZO_LIB_VERSION
    version_needed_to_extract::UInt16 = LZOP_MIN_VERSION
    method::M = M()
    flags::LZOPFlags = typemin(LZOPFlags)
    filter::F = F()
    mode::UInt32 = 0o0000
    mtime::DateTime = unix2datetime(0)

    name::String = "" # unnamed means using STDIN/STDOUT
    extra_field::Vector{UInt8} = Vector{UInt8}(undef, 0) # not used
end

"""
    write_be(io, value...) -> Int

    Write `value` to `io` in "big-endian" (network) byte order.
"""
write_be(io::IO, x...) = write(io, hton.(x)...)

"""
    read_be(src, T) -> value::T

    Read a value of type 'T' from 'src', returning the value converted to host byte order from "big-endian" (network) byte order.
"""
function read_be(src::IO, T::Type)
    value = read(src, T)
    return ntoh(value)
end

"""
    clean_name(name) -> String

    Convert a file name to LZOP's cannonical representation.

LZOP's cannonical represention of a file name is one that removes all drive and root path information, normalizes relative traversals within the path (i.e., "." and ".."), and enforces forward slash ('/') as the directory separator.

Note that LZOP has the facilities to understand path string encodings, but the reference code simply uses the native representation on the machine that is compressing/decompressing the file.
"""
function clean_name(name::AbstractString)
    drive_path = splitdrive(name)
    norm_path = normpath(drive_path[2])
    if isempty(name)
        return ""
    end
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

function Base.read(io::IO, ::Type{LZOPFileHeader})
    # until flags are read, we don't know whether CRC32 or Adler32 should be used.
    checksum_io = BufferedInputStream(io)
    anchor!(checksum_io)
    
    version = read_be(checksum_io, UInt16)
    if version < LZOP_MIN_VERSION
        throw(ErrorException("archive was created with an unreleased version of lzop: $version < $LZOP_MIN_VERSION"))
    end
    lib_version = read_be(checksum_io, UInt16)
    version_needed_to_extract = zero(UInt16)
    if version >=0x0940
        version_needed_to_extract = read_be(checksum_io, UInt16)
        if version_needed_to_extract > LZOP_VERSION
            throw(ErrorException("version needed to extract archive is greater than this version understands: $version_needed_to_extract > $LZOP_VERSION"))
        end
        if version_needed_to_extract < LZOP_MIN_VERSION
            throw(ErrorException("version needed to extract archive is an unreleased version of lzop: $version_needed_to_extract < $LZOP_MIN_VERSION"))
        end
    end

    method = read_be(checksum_io, UInt8)
    if version >= 0x0940
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
    if version >= 0x0940
        mtime_high = read_be(checksum_io, UInt32)
    else
        mtime_high = 0x00000000
    end
    # this can never happen because we require version to be >= 0x0900
    if version < 0x0120
        mtime_high = 0x00000000
        if mtime_low == typemax(UInt32)
            mtime_low = 0x00000000
        end
    end

    name_length = read_be(checksum_io, UInt8)
    if name_length > 0
        name = String(read_bytes(checksum_io, name_length))
        # Weirdly, the official code simply removes the name of the file if it reads an invalid name
        try
            name = clean_name(name)
        catch
            name = ""
        end
    else
        name = ""
    end

    # checksum up until now has to be computed
    raw_header_data = takeanchored!(checksum_io)
    checksum = (:H_CRC32 in flags) ? crc32(raw_header_data) : adler32(raw_header_data)
    header_checksum = read_be(checksum_io, UInt32)
    if checksum != header_checksum
        throw(ErrorException("header checksum does not match: expected $header_checksum (H_CRC32=$(:H_CRC32 in flags)), read $checksum"))
    end

    # extra data is not used, but we check it anyway
    if :H_EXTRA_FIELD in flags
        # reset the checksum calculation
        anchor!(checksum_io)

        extra_length = read_be(checksum_io, UInt32)
        if extra_length > 0
            extra = read_bytes(checksum_io, extra_length)
        else
            extra = Vecotr{UInt8}(undef, 0)
        end

        raw_extra_data = takeanchored!(checksum_io)
        extra_checksum = (:H_CRC32 in flags) ? crc32(raw_extra_data) : adler32(raw_extra_data)
        extra_field_checksum = read_be(checksum_io, UInt32)
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

    return LZOPFileHeader(
        version,
        lib_version,
        version_needed_to_extract,
        lzo_method,
        flags,
        lzo_filter,
        mode,
        mtime,
        name,
        extra,
    )
end

function Base.write(io::IO, header::LZOPFileHeader)
    # write everything to a buffer first to allow for checksum calculation
    checksum_io = IOBuffer()

    nb = 0

    nb += write_be(checksum_io, header.version)
    nb += write_be(checksum_io, header.lib_version)
    if header.version >= 0x0940
        nb += write_be(checksum_io, header.version_needed_to_extract)
    end
    method, level = translate_method(header.method)
    nb += write_be(checksum_io, method)
    if header.version >= 0x0940
        nb += write_be(checksum_io, level)
    end
    nb += write_be(checksum_io, UInt32(header.flags))
    if :H_FILTER in header.flags
        nb += write_be(checksum_io, translate_filter(header.filter))
    end
    nb += write_be(checksum_io, header.mode)
    mtime_low, mtime_high = translate_mtime(header.mtime)
    nb += write_be(checksum_io, mtime_low)
    if header.version >= 0x0120
        nb += write_be(checksum_io, mtime_high)
    end
    truncated_name = clean_name(header.name)
    name_length = min(length(truncated_name) % UInt8, typemax(UInt8))
    nb += write_be(checksum_io, name_length)
    if name_length > 0
        nb += write(checksum_io, codeunits(header.name))
    end

    raw_data = take!(checksum_io)
    checksum = (:H_CRC32 in header.flags) ? crc32(raw_data) : adler32(raw_data)

    nb_check = write(io, raw_data)
    if nb != nb_check
        throw(ErrorException("byte check failure: expected to write $nb bytes, wrote $nb_check"))
    end

    nb += write_be(io, checksum)

    if :H_EXTRA_FIELD in header.flags
        checksum_io = IOBuffer()

        nb += write_be(checksum_io, UInt32(length(header.extra_field)))
        nb += write(checksum_io, extra.header_field)

        raw_extra_data = take!(checksum_io)
        extra_checksum = (:H_CRC32 in header.flags) ? crc32(raw_extra_data) : adler32(raw_extra_data)

        write(io, raw_extra_data)

        nb += write_be(io, extra_checksum)
    end

    return nb
end
