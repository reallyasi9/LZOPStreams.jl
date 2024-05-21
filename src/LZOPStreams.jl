module LZOPStreams

using BufferedStreams
using CRC32
using Dates
using FlagSets
using LibLZO
using SimpleChecksums
using StringEncodings

export LZOPArchiveSink, LZOPArchiveSource, LZOPFileHeader
export next_file, create_file

@static if VERSION < v"1.9"
    include("compat.jl")
end

const LZO_LIB_VERSION = UInt16(LibLZO.version())
const LZOP_VERSION = 0x1300
const LZOP_MIN_VERSION = 0x0900

include("lzop_filter.jl")
include("lzop_header.jl")
include("lzop_block.jl")
include("lzop_file.jl")
include("lzop_archive.jl")

end
