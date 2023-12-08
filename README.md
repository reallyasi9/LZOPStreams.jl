# CodecLZO

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://reallyasi9.github.io/CodecLZO.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://reallyasi9.github.io/CodecLZO.jl/dev/)
[![Build Status](https://github.com/reallyasi9/CodecLZO.jl/actions/workflows/CI.yml/badge.svg?branch=development)](https://github.com/reallyasi9/CodecLZO.jl/actions/workflows/CI.yml?query=branch%3Adevelopment)

A Codec module for TranscodingStreams that implements a version of LZO. If you have the choice, choose CodecLZ4 or CodecSnappy over this module.

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
compressed = transcode(LZOCompressionCodec, text)
@assert length(compressed) < length(text)
decompressed = transcode(LZODecompressionCodec, compressed)
@assert decompressed == text
```
Transcoding using a streaming interface:

```julia
stream = LZOCompressionStream(IOBuffer(text))
for line in eachline(LZODecompressionStream(stream))
    println(line)
end
close(stream)
```

## Description

If you need to compress and decompress data in a stream and are starting from scratch, _do not use LZO_. Use the more modern CodecLZ4 or CodecSnappy modules. LZO is not designed or optimized for streaming, and is dominated in both compression ratio and speed by LZ4 and Snappy.

LZO (Lempel-Ziv-Oberhumer) is an LZ-style compression algorithm in that it encodes a given set of bytes as a sequence of commands that represent either literal copies of data (e.g., "copy the next N bytes directly to the end of the output") or copies from the output history (e.g., "go back K bytes in the output and copy N bytes from that point to the end of the output"). This simple algorithm is remarkably good at compressing things like natural language and computer programs (both source code and compiled binary code), and can be decoded extremely efficiently.

LZO, as implemented in liblzo2, is actually XXX separate algorithms: some are mutually compatable (i.e., data compressed with one algorithm can be decompressed with another), some are not; some are very fast, some are not; some are memory-efficient, some are not. This module attempts to implement a version of the "1X1" algorithm. This is the algorithm that the LZO authors recommend. The major features of the algorithm are:
  - A maximum lookback of XXX bytes;
  - A 4-byte minimum for history matches;
  - A history search with a linearly increasing skip distance as more misses are found;
  - A special encoding of literal copy commands and history copy commands that favors short history copies separated by literal copies of 4 or fewer bytes.

LZO 1X1, as implemented by liblzo2, is not compatible with streaming for two reasons:
  1. The entire input must be available all at once to the compression algorithm. Nothing is gained by streaming the input because the entire input must be buffered before compression can begin.
  2. The output size cannot be determined from a given input _a priori_ by the decompression algorithm. Either an infinite output buffer is required, or the algorithm has to repeatedly start over with a larger output buffer once an overrun is detected.

That being said, this module does export functions that directly call the liblzo2 versions of the 1X1 compression and decompression algorithms:

```julia
compressed = lzo_compress(text)

destination = UInt8[]
lzo_compress!(destination, text) # compresses in place, growing the destination as necessary
@assert destination == compressed
n = unchecked_lzo_compress!(destination, text) # compresses in place without resizing the destination, throwing a BoundsError if the compressed data overruns the destination
resize!(destination, n)
@assert destination == compressed

decompressed = lzo_decompress(compressed)
@assert decompressed == Vector{UInt8}(text)

destination = UInt8[]
lzo_decompress!(destination, compressed)
@assert destination == decompressed
n = unchecked_lzo_decompress!(destination, text)
resize!(destination, n)
@assert destination == decompressed
```