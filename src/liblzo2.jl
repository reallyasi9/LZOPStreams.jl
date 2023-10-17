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

const Lzo_uint32_t = Cuint  # Always 4 bytes in Julia
const Lzo_uint = Culonglong  # LZO expects this to be 8 bytes
const Lzo_xint = sizeof(Lzo_uint32_t) > sizeof(Lzo_uint) ? Lzo_uint32_t : Lzo_uint  # The larger type of lzo_uint and lzo_uint32_t
const Lzo_voidp = Ptr{Cvoid}

const lzo_sizeof_dict_t = sizeof(Ptr{Cuchar})

struct Lzo_callback_t
    nalloc::Ptr{Cvoid}
    nfree::Ptr{Cvoid}
    nprogress::Ptr{Cvoid}

    user1::Lzo_voidp
    user2::Lzo_xint
    user3::Lzo_xint
end

function lzo_init()
    version = lzo_version()
    # sizes = -1 skips check of that particular size
    s1 = sizeof(Cshort)
    s2 = sizeof(Cint)
    s3 = sizeof(Clong)
    s4 = sizeof(Lzo_uint32_t) # always 32 bits in Julia
    s5 = sizeof(Lzo_uint)
    s6 = lzo_sizeof_dict_t
    s7 = sizeof(Ptr{Cchar})
    s8 = sizeof(Lzo_voidp)
    s9 = sizeof(Lzo_callback_t)

    return @ccall liblzo2.__lzo_init_v2(version::Cuint, s1::Cint, s2::Cint, s3::Cint, s4::Cint, s5::Cint, s6::Cint, s7::Cint, s8::Cint, s9::Cint)::Cint
end