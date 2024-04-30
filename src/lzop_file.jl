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



# archive header:
# 1:9 = magic number
# 10:11 = lzop version
# -- if lzop version < 0x0900, end header, assume LZO1X_1 --
# 12:13 = liblzo version
# (if lzop version >= 0x0940) 14:15 = minimum version needed to extract compressed data, all other bytes following += 2
# -- if minimum version needed to extract < 0x0900, end header, assume LZO1X_1 --
# -- if minimum version needed to extract > lzop version, error --
# 14 = compression method
# (if lzop version >= 0x0940) 15 = compression level, all other bytes following += 1
# 15:18 = flags
# (if flags & F_H_FILTER) 19:22 = filter type, all other bytes following += 4
# 19:22 = achive file mode
# 23:26 = archive file modified time (low word) (if lzop version < 0x0120 and this value is typemax(UInt32), set all time values to 0)
# (if lzop version >= 0x0940) 27:30 = archive file modified time (high word), all other bytes following += 4
# 27 = archive name length in bytes = L
# 28:28+L = archive name bytes
# 29+L:32+L = archive header checksum
# (if flags & F_H_EXTRA_FIELD) 33+L:36+L = extra field length = X
# (if flags & F_H_EXTRA_FIELD) 37+L:37+L+X = extra field bytes
# (if flags & F_H_EXTRA_FIELD) 38+L+X:41+L+X = extra field checksum value (including length!)