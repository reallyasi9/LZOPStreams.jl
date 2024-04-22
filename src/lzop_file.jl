const LZOP_MAGIC_NUMBER = (0x89, 0x4c, 0x5a, 0x4f, 0x00, 0x0d, 0x0a, 0x1a, 0x0a)
const LZOP_VERSION = 0x1030
const LZOP_MIN_FILTER_VERSION = 0x0950
const LZOP_MIN_VERSION = 0x0940
@static if Sys.iswindows()
    const LZOP_F_OS = 0x00000000
else
    const LZOP_F_OS = 0x03000000
end
const LZOP_F_CS = 0x00500000 # UTF-8