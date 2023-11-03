var documenterSearchIndex = {"docs":
[{"location":"","page":"Home","title":"Home","text":"CurrentModule = CodecLZO","category":"page"},{"location":"#CodecLZO","page":"Home","title":"CodecLZO","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"Documentation for CodecLZO.","category":"page"},{"location":"","page":"Home","title":"Home","text":"","category":"page"},{"location":"","page":"Home","title":"Home","text":"Modules = [CodecLZO]","category":"page"},{"location":"#CodecLZO.LZO1X1CompressorCodec","page":"Home","title":"CodecLZO.LZO1X1CompressorCodec","text":"LZO1X1CompressorCodec <: AbstractLZOCompressorCodec\n\nA TranscodingStreams.Codec struct that compresses data according to the 1X1 version of the LZO algorithm.\n\nThe LZO 1X1 algorithm is defined by:\n\nA lookback dictionary implemented as a hash map with a maximum of size of at most 1<<12 = 4096 elements and as few as 16 elements using a specific fast hashing algorithm;\nAn 8-byte history lookup window that scans the input with a logarithmically increasing skip distance;\nA maximum lookback distance of 0b11000000_00000000 - 1 = 49151;\n\nThe C implementation of LZO defined by liblzo2 requires that all compressable information be loaded in working memory at once, and is therefore not adaptable to streaming as required by TranscodingStreams. The C library version therefore uses only a 4096-byte hash map as additional working memory, while this version needs to keep the full 49151 bytes of history in memory in addition to the 4096-byte hash map.\n\n\n\n\n\n","category":"type"}]
}