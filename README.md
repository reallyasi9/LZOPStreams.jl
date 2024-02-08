# CodecLZO

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://reallyasi9.github.io/CodecLZO.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://reallyasi9.github.io/CodecLZO.jl/dev/)
[![Build Status](https://github.com/reallyasi9/CodecLZO.jl/actions/workflows/CI.yml/badge.svg?branch=development)](https://github.com/reallyasi9/CodecLZO.jl/actions/workflows/CI.yml?query=branch%3Adevelopment)

A Codec module for TranscodingStreams that implements a version of LZO. If you have the choice, choose CodecLZ4 or CodecZstd over this module.

## Synopsis

```julia
using CodecLZO
using TranscodingStreams

const text = """Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aenean sollicitudin
mauris non nisi consectetur, a dapibus urna pretium. Vestibulum non posuere
erat. Donec luctus a turpis eget aliquet. Cras tristique iaculis ex, eu
malesuada sem interdum sed. Vestibulum ante ipsum primis in faucibus orci luctus
et ultrices posuere cubilia Curae; Etiam volutpat, risus nec gravida ultricies,
erat ex bibendum ipsum, sed varius ipsum ipsum vitae dui."""
```

One-shot transcoding to and from `String` or `Array{UInt8}` values:

```julia
compressed = transcode(LZOCompressor, text)
@assert length(compressed) < length(text)
decompressed = transcode(LZODecompressor, compressed)
@assert String(decompressed) == text
```
Transcoding using a streaming interface:

```julia
stream = LZOCompressorStream(IOBuffer(text))
for line in eachline(LZODecompressorStream(stream))
    println(line)
end
close(stream)
```

This package exports following codecs and streams:

| Codec              | Stream                   |
| ------------------ | ------------------------ |
| `LZOCompressor`   | `LZOCompressorStream`   |
| `LZODecompressor` | `LZODecompressorStream` |

See docstrings and [TranscodingStreams.jl](https://github.com/bicycle1885/TranscodingStreams.jl) for details.

## Description

If you need to compress and decompress data in a stream and are starting from scratch, _do not use LZO_. Use the more modern [CodecLZ4](https://github.com/JuliaIO/CodecLz4.jl) or [CodecZstd](https://github.com/JuliaIO/CodecZstd.jl) modules. LZO is _not_ designed or optimized for streaming.

LZO (an abbrevation of [Lempel-Ziv-Oberhumer](https://www.oberhumer.com/opensource/lzo/)) is a variant of the [LZ77 compression algorithm](https://doi.org/10.1109/TIT.1977.1055714) that encodes a given set of bytes as a sequence of commands that represent either literal copies of data (e.g., "copy the next N bytes directly to the end of the output") or copies from the output history (e.g., "go back K bytes in the output and copy N bytes from there to the end of the output"). This simple algorithm is remarkably good at compressing things like natural language and computer programs (both source code and compiled binary code), and can be decompressed extremely quickly and with little memory overhead.

LZO as implemented in liblzo2 is actually 37 separate algorithms: some are mutually compatible (i.e., data compressed with one algorithm can be decompressed with another), some are not; some are very fast, some are not; some are memory-efficient, some are not. This module attempts to implement a version of the "1X1" algorithm, which is the default algorithm used by the [`lzop` program](https://www.lzop.org/). The major features of this algorithm are:
  - A maximum look-back distance of 49151 bytes;
  - A 4-byte minimum history match;
  - A history search with a linearly increasing skip distance as more misses are found;
  - A special encoding of literal copy commands and history copy commands that favors short history copies separated by literal copies of 4 or fewer bytes.

LZO1X1, as implemented by liblzo2, is not compatible with streaming for two reasons:
  1. The entire input must be available all at once to the compression algorithm. Nothing is gained by streaming the input because the entire input must be buffered before compression can begin.
  2. The output size cannot be determined from a given input _a priori_ by the decompression algorithm. Either an infinite output buffer is required, or the algorithm has to repeatedly start over with a larger output buffer once an overrun is detected.

That being said, the liblzo2 version of the algorithm still outperforms this pure Julia implementation by a factor of 20 in terms of speed and a factor of 10-100 in terms of memory usage. The only advantage of streaming LZO1X1 using this module is that it _sometimes_ allows partial processing of streamed data on memory-limited systems.

This module does export functions that directly call the liblzo2 versions of the 1X1 compression and decompression algorithms:

```julia
using CodecLZO.LZO: lzo_compress, lzo_compress!, unsafe_lzo_compress!, lzo_decompress, lzo_decompress!, unsafe_lzo_decompress!

# compress to a new Vector{UInt8}
compressed = lzo_compress(text)

# compress in place, growing the destination as necessary
destination = UInt8[]
lzo_compress!(destination, text)
@assert destination == compressed

# compress in place, throwing BoundsError if the compressed data does not fit
n = unsafe_lzo_compress!(destination, text)
resize!(destination, n)
@assert destination == compressed

# decompress to a new Vector{UInt8}
decompressed = lzo_decompress(compressed)
@assert decompressed == Vector{UInt8}(text)

# decompress in place, growing the destination as necessary
destination = UInt8[]
lzo_decompress!(destination, compressed)
@assert destination == decompressed

# decompress in place, throwing BoundsError if the decompressed data does not fit
n = unsafe_lzo_decompress!(destination, compressed)
resize!(destination, n)
@assert destination == decompressed
```
Because of necessary differences between the streaming version of the LZO1X1 algorithm and the in-place version used by liblzo2, the two methods may not produce the same compressed output. However, the compression ratios achieved by the two versions are similar (with the streaming version typically achieving 1-2% better compression), and the encoded data are compatible between the two as demonstrated:

```julia
lzo_compressed = lzo_compress(text)
stream_decompressed = transcode(LZODecompressor, lzo_compressed)
@assert String(stream_decompressed) == text

stream_compressed = transcode(LZOCompressor, text)
lzo_decompressed = lzo_decompress(stream_compressed)
@assert String(lzo_decompressed) == text
```
