using LZOPStreams
using TestItemRunner

@testitem "write_be" begin
    io = IOBuffer()
    value = 0x0102
    @test LZOPStreams.write_be(io, value) == 2
    @test take!(io) == UInt8[0x01, 0x02]
end

@testitem "read_be" begin
    src = IOBuffer()
    value = 0x0102
    write(src, hton(value))
    seekstart(src)
    @test LZOPStreams.read_be(src, UInt16) == 0x0102
end

@testitem "clean_name" begin
    all_tests = (
        "" => "",
        "hello" => "hello",
        "/hello" => "hello",
        "hello/world/unix" => "hello/world/unix",
        "hello/./world" => "hello/world",
        "hello/../world" => "world",
        "hello//world" => "hello/world",
    )

    for test in all_tests
        input = first(test)
        expected = last(test)
        @test LZOPStreams.clean_name(input) == expected
    end

    # things that look like directory names should throw
    @test_throws ErrorException LZOPStreams.clean_name("dir/")
    @test_throws ErrorException LZOPStreams.clean_name("/")

    if Sys.iswindows()
        tests = (
            "c:\\hello" => "hello",
            "hello\\world\\windows" => "hello/world/windows",
            "hello\\\\world" => "hello/world",
        )
        @test_throws ErrorException LZOPStreams.clean_name("windows\\dir\\")
        @test_throws ErrorException LZOPStreams.clean_name("c:\\")
    else
        tests = (
            "c:\\hello" => "c:\\hello",
            "hello\\world\\windows" => "hello\\world\\windows",
            "hello\\\\world" => "hello\\\\world",
            "windows\\dir\\" => "windows\\dir\\",
            "c:\\" => "c:\\",
        )
    end

    for test in tests
        input = first(test)
        expected = last(test)
        @test LZOPStreams.clean_name(input) == expected
    end
end

@testitem "translate_method" begin
    using LibLZO

    let
        @test_throws ErrorException LZOPStreams.translate_method(0x00, 0x00)
        @test_throws ErrorException LZOPStreams.translate_method(rand(0x04:0xff), 0x00)
        @test_throws ErrorException LZOPStreams.translate_method(rand(0x01:0x03), rand(0x0a:0xff))

        @test typeof(LZOPStreams.translate_method(UInt8(LZOPStreams.M_LZO1X_1), rand(0x00:0x09))) == LZO1X_1
        @test typeof(LZOPStreams.translate_method(UInt8(LZOPStreams.M_LZO1X_1_15), rand(0x00:0x09))) == LZO1X_1_15
        level = rand(0x01:0x09)
        m = LZOPStreams.translate_method(UInt8(LZOPStreams.M_LZO1X_999), level)
        @test typeof(m) == LZO1X_999
        @test m.compression_level == level

        m_default = LZOPStreams.translate_method(UInt8(LZOPStreams.M_LZO1X_999), 0x00)
        @test typeof(m_default) == LZO1X_999
        @test m_default.compression_level == 9

        for T in (LZO1X_1, LZO1X_1_15, LZO1X_999)
            level = rand(0x0a:0xff)
            @test_throws ErrorException LZOPStreams.translate_method(T(), level)
        end

        for (T, M) in zip((LZO1X_1, LZO1X_1_15, LZO1X_999), (LZOPStreams.M_LZO1X_1, LZOPStreams.M_LZO1X_1_15, LZOPStreams.M_LZO1X_999))
            level = rand(0x00:0x09)
            @test LZOPStreams.translate_method(T(), level) == (UInt8(M), UInt8(level))
        end

        # default values
        @test LZOPStreams.translate_method(LZO1X_1()) == (UInt8(LZOPStreams.M_LZO1X_1), UInt8(3))
        @test LZOPStreams.translate_method(LZO1X_1_15()) == (UInt8(LZOPStreams.M_LZO1X_1_15), UInt8(1))
        level = rand(0x01:0x09)
        @test LZOPStreams.translate_method(LZO1X_999(compression_level=level)) == (UInt8(LZOPStreams.M_LZO1X_999), UInt8(level))
    end
end

@testitem "translate_filter" begin
    @test LZOPStreams.translate_filter(UInt32(0)) == LZOPStreams.NoopFilter()
    @test LZOPStreams.translate_filter(rand(UInt32(17):typemax(UInt32))) == LZOPStreams.NoopFilter()
    n = rand(UInt32(1):UInt32(16))
    N = Int(n)
    @test typeof(LZOPStreams.translate_filter(n)) == LZOPStreams.ModuloSumFilter{N}

    @test LZOPStreams.translate_filter(LZOPStreams.NoopFilter()) == zero(UInt32)
    @test LZOPStreams.translate_filter(LZOPStreams.ModuloSumFilter{N}()) == n
end

@testitem "translate_mtime" begin
    using Dates

    dt0 = Dates.unix2datetime(0)
    dtnow = Dates.now()

    s0 = zero(UInt64)
    snow = round(UInt64, Dates.datetime2unix(dtnow))

    s0_low = UInt32(s0 & typemax(UInt32))
    s0_high = UInt32(s0 >> 32)
    snow_low = UInt32(snow & typemax(UInt32))
    snow_high = UInt32(snow >> 32)

    @test LZOPStreams.translate_mtime(s0_low, s0_high) == dt0
    @test LZOPStreams.translate_mtime(snow_low, snow_high) == round(dtnow, Second)
    @test LZOPStreams.translate_mtime(dt0) == (s0_low, s0_high)
    @test LZOPStreams.translate_mtime(dtnow) == (snow_low, snow_high)
end

@run_package_tests verbose = true