const LZO_E_OK = 0
const LZO_E_ERROR = -1
const LZO_E_OUT_OF_MEMORY = -2    # [lzo_alloc_func_t failure]
const LZO_E_NOT_COMPRESSIBLE = -3    # [not used right now]
const LZO_E_INPUT_OVERRUN = -4
const LZO_E_OUTPUT_OVERRUN = -5
const LZO_E_LOOKBEHIND_OVERRUN = -6
const LZO_E_EOF_NOT_FOUND = -7
const LZO_E_INPUT_NOT_CONSUMED = -8
const LZO_E_NOT_YET_IMPLEMENTED = -9    # [not used right now]
const LZO_E_INVALID_ARGUMENT = -10
const LZO_E_INVALID_ALIGNMENT = -11   # pointer argument is not properly aligned
const LZO_E_OUTPUT_NOT_CONSUMED = -12
const LZO_E_INTERNAL_ERROR = -99

function lzo_version()
    return @ccall liblzo2.lzo_version()::UInt
end

function lzo_version_string()
    return unsafe_string(@ccall liblzo2.lzo_version_string()::Cstring)
end

function lzo_version_date()
    return unsafe_string(@ccall liblzo2.lzo_version_date()::Cstring)
end

const lzo_sizeof_dict_t = sizeof(Ptr{Cuchar})
# The larger type of lzo_uint and lzo_uint32_t. #
const lzo_xint = Cuint

struct lzo_callback_t
    nalloc::Ptr{Cvoid}
    nfree::Ptr{Cvoid}

    nprogress::Ptr{Cvoid}

    user1::Ptr{Cvoid}
    user2::lzo_xint
    user3::lzo_xint
end

function lzo_init()
    version = lzo_version()
    # sizes = -1 skips check of that particular size
    s1 = -1
    s2 = -1
    s3 = -1
    s4 = -1
    s5 = -1
    s6 = -1
    s7 = -1
    s8 = -1
    s9 = -1

    return @ccall liblzo2.__lzo_init_v2(version::Cuint, s1::Cint, s2::Cint, s3::Cint, s4::Cint, s5::Cint, s6::Cint, s7::Cint, s8::Cint, s9::Cint)::Cint
end