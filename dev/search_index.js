var documenterSearchIndex = {"docs":
[{"location":"","page":"Home","title":"Home","text":"CurrentModule = CodecLZO","category":"page"},{"location":"#CodecLZO","page":"Home","title":"CodecLZO","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"Documentation for CodecLZO.","category":"page"},{"location":"","page":"Home","title":"Home","text":"","category":"page"},{"location":"","page":"Home","title":"Home","text":"Modules = [CodecLZO]","category":"page"},{"location":"#CodecLZO.AbstractCommand","page":"Home","title":"CodecLZO.AbstractCommand","text":"AbstractCommand\n\nA type representing either a literal copy (LiteralCopyCommand) or a history lookback copy (HistoryCopyCommand).\n\nTypes that inherit from AbstractCommand must implement the following methods:\n\ncommand_length(::AbstractCommand)::Int, which returns the length of the encoded command in bytes;\ncopy_length(::AbstractCommand)::Int, which returns the number of bytes to be copied to the output;\none or both of:\ndecode(::Type{T}, ::AbstractVector{UInt8})::T where {T <: AbstractCommand}, which decodes a command of type T from the start of an AbstractVector{UInt8};\nunsafe_decode(::Type{T}, ::Ptr{UInt8}, ::Integer)::T where {T <: AbstractCommand}, which decodes a command of type T from the memory pointed to by the pointer at a given (one-indexed) offset;\none or both of:\nencode!(::T, ::AbstractCommand)::T where {T <: AbstractVector{UInt8}}, which encodes the command to the given vector and returns the modified vector;\nunsafe_encode!(::Ptr{UInt8}, ::AbstractCommand, ::Integer)::Int, which encodes the command to the memory pointed to at a given (one-indexed offset) and returns the number of bytes written.\n\n\n\n\n\n","category":"type"},{"location":"#CodecLZO.HashMap","page":"Home","title":"CodecLZO.HashMap","text":"HashMap{K,V}\n\nA super-fast dictionary-like hash table of fixed size for integer keys.\n\n\n\n\n\n","category":"type"},{"location":"#CodecLZO.HistoryCopyCommand","page":"Home","title":"CodecLZO.HistoryCopyCommand","text":"struct HistoryCopyCommand <: AbstractCommand\n\nAn encoded command representing a copy of a number of bytes from the already produced output back to the output.\n\nIn LZO1X, history lookback copies come in five varieties, the format of which is determined by the number of bytes copied, the lookback distance, and whether or not the previous command had a short literal copy tagged on the end:\n\nVery short copy, short distance\n\nCopies of three to four bytes with a lookback distance within 2048 bytes are encoded as two bytes, with bits encoding the length and distance. The command is to be interpreted in the following way (MSB first):\n\n`01LDDDSS HHHHHHHH`\n\nThis means copy 3 + 0bL from a distance of 0b00000HHH_HHHHHDDD + 1.\n\nThe last two bits of the MSB instruct the decoder to copy 0bSS literals from the input to the output immediately following the history lookback copy.\n\nShort copy, short distance\n\nCopies of five to eight bytes with a lookback distance within 2048 bytes are encoded as two bytes, with bits encoding the length and distance. The command is to be interpreted in the following way (MSB first):\n\n`1LLDDDSS HHHHHHHH`\n\nThis means copy 5 + 0bLL bytes from a distance of 0b00000HHH_HHHHHDDD + 1.\n\nThe last two bits of the MSB instruct the decoder to copy 0 through 3 literals from the input to the output immediately following the history lookback copy.\n\nAny length copy, short to medium distance\n\nCopies of any length greater than two with a lookback distance within 16384 bytes is incoded with at least three bytes and with as many as necessary to encode the run length. The command is to be interpreted in the following way (MSB first):\n\n`001LLLLL [Z zero bytes] [XXXXXXXX] EEEEEESS DDDDDDDD`\n\nThe lower five bits of the first byte represent the length of the copy minus two. This can obviously only represent copies of length 2 to 33, so to encode longer copies, LZO1X uses the following encoding method:\n\nIf 0bLLLLL is non-zero, then length = 2 + 0bLLLLL\nIf 0bLLLLL is zero, then length = 33 + (number of zero bytes after the first) × 255 + (first non-zero byte)\n\nThe lookback distance is encoded in LE order in the last two bytes: that is, the last byte of the command holds the MSB of the distance, and the second-to-last byte holds the LSB of the distance. The distance is interpreted as distance = 0b00DDDDDD_DDEEEEEE + 1.\n\nThe last two bits of the second-to-last byte instruct the decoder to copy 0bSS literals from the input to the output immediately following the history lookback copy.\n\nAny length copy, long distance\n\nCopies of any length greater than two with a lookback distance between 16385 and 49151 bytes is incoded with at least three bytes and with as many as necessary to encode the run length. The command is to be interpreted in the following way (MSB first):\n\n`0001HLLL [Z zero bytes] [XXXXXXXX] EEEEEESS DDDDDDDD`\n\nAs with other variable length runs,, LZO1X uses the following encoding method with this command:\n\nIf 0bLLL is non-zero, then length = 2 + 0bLLL\nIf 0bLLL is zero, then length = 9 + (number of zero bytes after the first) × 255 + (first non-zero byte)\n\nThe lookback distance is encoded with one bit in the first command byte (H), then in LE order in the last two bytes: that is, the last byte of the command holds the MSB of the distance, and the second-to-last byte holds the LSB of the distance. The distance is interpreted as distance = 16384 + 0b0HDDDDDD_DDEEEEEE.\n\nThe last two bits of the second-to-last byte instruct the decoder to copy 0bSS literals from the input to the output immediately following the history lookback copy.\n\ninfo: Special End-of-Stream Encoding\nEnd-of-stream is signaled by a history lookback copy of 3 bytes from a distance of 16384 bytes with no subsequent literal copies. This corresponds to a long historical lookback copy command of 0b00010001 0b00000000 0b00000000.\n\nnote: Note\nThe maximum lookback distance that LZO1X can encode is 16384 + 0b01111111_11111111 == 49151 bytes.\n\nShort copies from short distances following literal copies\n\nIf the previous history lookback command included a short literal copy (1 ≤ 0bSS ≤ 3, as encoded in the above commands), then a special two-byte command can be used to copy two bytes with a lookback distance within 1024 bytes. The command is to be interpreted in the following way (MSB first):\n\n`0000DDSS HHHHHHHH`\n\nThe number of bytes to copy is always length = 2, and the lookback distance is 0b000000HH_HHHHHHDD + 1.\n\nThe last two bits of the first byte instruct the decoder to copy 0bSS literals from the input to the output immediately following the history lookback copy.\n\nIf the previous command was a long literal copy (of four of more bytes), then the same two-byte command means something different: it encodes a three-byte copy with a lookback distance between 2049 and 3071 bytes. The command is interpreted the same as above, but length = 3 and distance = 0b000000HH_HHHHHHDD + 2049.\n\nnote: Note\nBecause encoding these special commands require a historical match of fewer than four bytes, they are never encoded by the LZO1X algorithm: however, they are valid LZO1X commands, and the LZO1X decoder will interpret them correctly.\n\nSee also CodecLZO.LiteralCopyCommand.\n\n\n\n\n\n","category":"type"},{"location":"#CodecLZO.LZO1X1CompressorCodec","page":"Home","title":"CodecLZO.LZO1X1CompressorCodec","text":"LZO1X1CompressorCodec <: TranscodingStreams.Codec\n\nA struct that compresses data according to the 1X1 version of the LZO algorithm.\n\nThe LZO 1X1 algorithm is a Lempel-Ziv lossless compression algorithm defined by:\n\nA lookback dictionary implemented as a hash map with a maximum of size of 1<<12 = 4096 elements;\nA 4-byte history lookup window that scans the input with a skip distance that increases linearly with the number of misses;\nA maximum lookback distance of 0b11000000_00000000 - 1 = 49151 bytes;\n\nThe C implementation of LZO defined by liblzo2 requires that all compressable information be loaded in working memory at once, and is therefore not adaptable to streaming as required by TranscodingStreams. The C library version claims to use only a 4096-byte hash map as additional working memory, but it also requires that a continuous space in memory be available to hold the entire output of the compressed data, the length of which is not knowable a priori but can be larger than the uncompressed data by a factor of roughly 256/255. This implementation needs to keep 49151 bytes of input history in memory in addition to the 4096-byte hash map, but only expands the output as necessary during compression.\n\n\n\n\n\n","category":"type"},{"location":"#CodecLZO.LZO1X1DecompressorCodec","page":"Home","title":"CodecLZO.LZO1X1DecompressorCodec","text":"LZO1X1DecompressorCodec <: TranscodingStreams.Codec\n\nA struct that decompresses data according to the 1X1 version of the LZO algorithm.\n\nThe LZO 1X1 algorithm is a Lempel-Ziv lossless compression algorithm. Compressed streams consist of alternating encoded instructions and sequences of literal values. The encoded instructions tell the decompressor to either:\n\ncopy a sequence of bytes of a particular length directly from the input to the output (literal copy), or\nlook back a certain distance in the already returned output and copy a sequence of bytes of a particular length from the output to the output again.\n\nFor implementation purposes, this decompressor uses a buffer of 49151 bytes to store output. This is equal to the maximum lookback distance of the LZO 1X1 algorithm.\n\nThe C implementation of LZO defined by liblzo2 requires that all decompressed information be available in working memory at once, and is therefore not adaptable to streaming as required by TranscodingStreams. The C library version claims to use no additional working memory, but it requires that a continuous space in memory be available to hold the entire output of the compressed data, the length of which is not knowable a priori but can be larger than the compressed data by a factor of roughly 255. This implementation needs to keep 49151 bytes of output history in memory while decompressing, equal to the maximum lookback distance of the LZO 1x1 algorithm, and a small number of bytes to keep track of the command being processed in case the command is broken between multiple reads from the input memory.\n\n\n\n\n\n","category":"type"},{"location":"#CodecLZO.LZO1X1FastCompressorCodec","page":"Home","title":"CodecLZO.LZO1X1FastCompressorCodec","text":"LZO1X1FastCompressorCodec <: TranscodingStreams.Codec\n\nA struct that compresses data using the liblzo2 version version of the LZO 1X1 algorithm.\n\nThe LZO 1X1 algorithm is a Lempel-Ziv lossless compression algorithm defined by:\n\nA lookback dictionary implemented as a hash map with a maximum of size of 1<<16 = 65536 elements;\nA 4-byte history lookup window that scans the input with a skip distance that increases linearly with the number of misses;\nA maximum lookback distance of 0b11000000_00000000 - 1 = 49151 bytes;\n\nThe C implementation of LZO defined by liblzo2 requires that all compressable information be loaded in working memory at once. The C library version claims to use only a 4096-byte hash map as additional working memory, but it also requires that a continuous space in memory be available to hold the entire output of the compressed data, the length of which is not knowable a priori but can be larger than the uncompressed data by a factor of roughly 256/255. This implementation uses an expanding input buffer that waits until all input is available before processing, eliminating the usefulness of the TranscodingStreams interface.\n\n\n\n\n\n","category":"type"},{"location":"#CodecLZO.LZO1X1FastDecompressorCodec","page":"Home","title":"CodecLZO.LZO1X1FastDecompressorCodec","text":"LZO1X1FastDecompressorCodec <: TranscodingStreams.Codec\n\nA struct that decompresses data using liblzo1 library version of the LZO 1X1 algorithm.\n\nThe LZO 1X1 algorithm is a Lempel-Ziv lossless compression algorithm. Compressed streams consist of alternating encoded instructions and sequences of literal values. The encoded instructions tell the decompressor to either:\n\ncopy a sequence of bytes of a particular length directly from the input to the output (literal copy), or\nlook back a certain distance in the already returned output and copy a sequence of bytes of a particular length from the output to the output again.\n\nThe C implementation of LZO defined by liblzo2 requires that all decompressed information be available in working memory at once, and therefore does not take advantage of the memory savings allowed by TranscodingStreams. The C library version claims to use no additional working memory, but it requires that a continuous space in memory be available to hold the entire output of the compressed data, the length of which is not knowable a priori but can be larger than the compressed data by a factor of roughly 255. This implementation reports a very large memory requirement with TranscodingStreams.minoutsize to account for this.\n\n\n\n\n\n","category":"type"},{"location":"#CodecLZO.LiteralCopyCommand","page":"Home","title":"CodecLZO.LiteralCopyCommand","text":"struct LiteralCopyCommand <: AbstractCommand\n\nAn encoded command representing a copy of a number of bytes from input straight to output.\n\nIn LZO1X, literal copies come in three varieties:\n\nLong copies\n\nLZO1X long copy commands begin with a byte with four high zero bits and four low potentially non-zero bits:\n\n0 0 0 0 L L L L\n\nThe low four bits represent the length of the copy minus three. This can obviously only represent copies of length 3 to 18, so to encode longer copies, LZO1X uses the following encoding method:\n\nIf the first byte is non-zero, then length = 3 + L\nIf the first byte is zero, then length = 18 + (number of zero bytes after the first) × 255 + (first non-zero byte)\n\nThis means a length of 18 is encoded as [0b00001111], a length of 19 is encoded as [0b00000000, 0b00000001], a length of 274 is encoded as [0b00000000, 0b00000000, 0b00000001], and so on.\n\nShort copies\n\nThe long copy command cannot encode copies shorter than four bytes by design. If a literal of three or fewer bytes needs to be copied, it is encoded in the two least significant bits of the previous history lookback copy command. This works because literal copies and history lookback copies always alternate in LZO1X streams.\n\nFirst literal copies\n\nLZO1X streams always begin with a literal copy command of at least four bytes. Because the first command is always a literal copy, a special format is used to copy runs of literals that are between 18 and 238 bytes that compacts the command into a single byte. If the first byte of the stream has the following values, they are interpreted as the corresponding literal copy commands:\n\n0:15: Treat as a \"long copy\" encoding (see above).\n17:255: Treat as a copy of (byte - 17) literals.\n\nNote that 17:20 are invalid values for a first copy command in LZO1X streams because history lookback copy lengths must always be four or more bytes. A value of 16 in the first position is always invalid.\n\nnote: Note\nThe official liblzo2 version of LZO1X properly decodes these first literal copy codes, but never encodes them when compressing data.\n\nSee also CodecLZO.HistoryCopyCommand.\n\n\n\n\n\n","category":"type"},{"location":"#CodecLZO.ModuloBuffer","page":"Home","title":"CodecLZO.ModuloBuffer","text":"ModuloBuffer{T}(n::Integer)\nModuloBuffer(v::AbstractVector{T}[, n::Integer])\nModuloBuffer(iter[, n::Integer])\n\nAn AbstractVector{T} of fixed capacity n with periodic boundary conditions.\n\nIf not given, n defaults to the length of the Vector or iterator passed to the constructor. If n < length(v), only the first n elements will be copied to the buffer.\n\nIf a new element added (either with push!, pushfirst!, or append!) would increase the size of the buffer past the capacity n, the oldest element added will be overwritten (or the newest element added in the case of pushfirst!) to maintain the fixed capacity.\n\n\n\n\n\n","category":"type"},{"location":"#CodecLZO.PassThroughFIFO","page":"Home","title":"CodecLZO.PassThroughFIFO","text":"PassThroughFIFO <: AbstractVector{UInt8}\n\nA FIFO (first in, first out data structure) that buffers data pushed into the front of it and, when full, pushes out older data from the back to a sink.\n\n\n\n\n\n","category":"type"},{"location":"#Base.resize!-Union{Tuple{T}, Tuple{CodecLZO.ModuloBuffer{T}, Integer}} where T","page":"Home","title":"Base.resize!","text":"resize!(buffer::ModuloBuffer, n::Integer)::ModuloBuffer\n\nResize buffer to a capacity of n elements efficiently.\n\nIf n < capacity(buffer), only the first n elements of buffer will be retained.\n\nAttempts to avoid allocating new memory by manipulating and resizing the internal vector in place.\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.capacity-Tuple{CodecLZO.ModuloBuffer}","page":"Home","title":"CodecLZO.capacity","text":"capacity(buffer::ModuloBuffer)::Int\n\nReturn the maximum number of elements buffer can contain.\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.command_length-Tuple{CodecLZO.AbstractCommand}","page":"Home","title":"CodecLZO.command_length","text":"command_length(command)::Int\n\nReturn the number of bytes in the encoded command.\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.compute_run_remainder-Tuple{Integer, Integer}","page":"Home","title":"CodecLZO.compute_run_remainder","text":"compute_run_remainder(n, bits)::Tuple{Int, Int}\n\nCompute the number of bytes necessary to encode a run of length n given a first-byte mask of length bits, also returning the remainder byte.\n\nnote: Note\nThis method does not adjust n before computing the run length. Perform adjustments before calling this method.\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.copy_length-Tuple{CodecLZO.AbstractCommand}","page":"Home","title":"CodecLZO.copy_length","text":"copy_length(command)::Int\n\nReturn the number of bytes that are to be copied to the output by command.\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.count_matching-Union{Tuple{T}, Tuple{AbstractVector{T}, AbstractVector{T}}} where T","page":"Home","title":"CodecLZO.count_matching","text":"count_matching(a::AbstractVector, b::AbstractVector)\n\nCount the number of elements at the start of a that match the elements at the start of b.\n\nEquivalent to findfirst(a .!= b), but faster and limiting itself to the first min(length(a), length(b)) elements.\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.decode_run-Tuple{AbstractVector{UInt8}, Integer}","page":"Home","title":"CodecLZO.decode_run","text":"decode_run(input::Vector{UInt8}, bits)::Tuple{Int, Int}\n\nDecode the length of the run in bytes and the number of bytes to copy from input given a mask of bits bits.\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.encode_run!-Tuple{AbstractVector{UInt8}, Integer, Integer}","page":"Home","title":"CodecLZO.encode_run!","text":"encode_run!(output, len, bits)::Int\n\nEmit the number of zero bytes necessary to encode a length len in a command expecting bits leading bits, returning the number of bytes written to the output.\n\nLiteral and copy lengths are always encoded as either a single byte or a sequence of three or more bytes. If len < (1 << bits), the length will be encoded in the lower bits bits of the starting byte of output so the return will be 0. Otherwise, the return will be the number of additional bytes needed to encode the length. The returned number of bytes does not include the zeros in the first byte (the command) used to signal that a run encoding follows, but it does include the remainder.\n\nNote: the argument len is expected to be the adjusted length for the command. Literals use an adjusted length of len = length(literal) - 3 and copy commands use an adjusted literal length of len = length(copy) - 2.\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.flush!-Tuple{CodecLZO.PassThroughFIFO, AbstractVector{UInt8}}","page":"Home","title":"CodecLZO.flush!","text":"flush!(p::PassThroughFIFO, sink::AbstractVector{UInt8})\n\nCopy all the data in p to the front of sink.\n\nReturns the number of bytes copied, equal to min(length(p), length(sink)). If length(sink) >= length(p), isempty(p) == true after the flush, else length(p) will be equal to the number of bytes that could not be pushed to sink.\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.lzo_compress","page":"Home","title":"CodecLZO.lzo_compress","text":"lzo_compress(src, [working_memory=zeros(UInt8, 1<<12)])::Vector{UInt8}\n\nCompress src using the LZO 1X1 algorithm.\n\nReturns a compressed version of src.\n\nPass working_memory, a Vector{UInt8} with length(working_memory) >= 1<<12, to reuse pre-allocated memory required by the algorithm.\n\n\n\n\n\n","category":"function"},{"location":"#CodecLZO.lzo_compress!","page":"Home","title":"CodecLZO.lzo_compress!","text":"lzo_compress!(dest::Vector{UInt8}, src, [working_memory=zeros(UInt8, 1<<12)])\n\nCompress src to dest using the LZO 1X1 algorithm.\n\nThe destination vector dest will be resized to fit the compressed data if necessary. Returns the modified dest.\n\nPass working_memory, a Vector{UInt8} with length(working_memory) >= 1<<12, to reuse pre-allocated memory required by the algorithm.\n\n\n\n\n\n","category":"function"},{"location":"#CodecLZO.lzo_decompress!-Tuple{Vector{UInt8}, AbstractVector{UInt8}}","page":"Home","title":"CodecLZO.lzo_decompress!","text":"lzo_decompress!(dest::Vector{UInt8}, src)\n\nDecompress src to dest using the LZO 1X1 algorithm.\n\nThe destination vector dest will be resized to fit the decompressed data if necessary. Returns the modified dest.\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.lzo_decompress-Tuple{AbstractVector{UInt8}}","page":"Home","title":"CodecLZO.lzo_decompress","text":"lzo_decompress(src)::Vector{UInt8}\n\nDecompress src using the LZO 1X1 algorithm.\n\nReturns a decompressed version of src.\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.multiplicative_hash-Union{Tuple{T}, Tuple{T, Integer, Int64}} where T<:Integer","page":"Home","title":"CodecLZO.multiplicative_hash","text":"multiplicative_hash(value, magic_number, bits, [mask::V = typemax(UInt64)])\n\nHash value into a type V using multiplicative hashing.\n\nThis method performs floor((value * magic_number % W) / (W / M)) where W = 2^64, M = 2^m, and magic_number is relatively prime to W, is large, and has a good mix of 1s and 0s in its binary representation. In modulo 2^64 arithmetic, this becomes (value * magic_number) >>> m.\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.pushout!-Tuple{CodecLZO.PassThroughFIFO, AbstractVector{UInt8}, AbstractVector{UInt8}}","page":"Home","title":"CodecLZO.pushout!","text":"pushout!(p::PassThroughFIFO, source, sink::AbstractVector{UInt8})\n\nPush as much of source into the FIFO as it can hold, pushing out stored data to sink.\n\nThe argument source can be an AbstractVector{UInt8} or a single UInt8 value.\n\nUntil p is full, elements from source will be added to the FIFO and no elements will be pushed out to sink. Once p is full, elements of source up to capacity(p) will be added to the FIFO and the older elements will be pushed to sink.\n\nReturns a tuple of the number of elements read from source and the number of elements written to sink.\n\nSee repeatout!.\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.reinterpret_get-Union{Tuple{T}, Tuple{Type{T}, AbstractVector{UInt8}}, Tuple{Type{T}, AbstractVector{UInt8}, Int64}} where T<:Integer","page":"Home","title":"CodecLZO.reinterpret_get","text":"reinterpret_get(T::Type, input::AbstractVector{UInt8}, [index::Int = 1])::T\n\nReinterpret bytes from input as an LE-ordered value of type T, optionally starting at index. This tries to be faster than reinterpret(T, input[index:index+sizeof(T)-1]).\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.reinterpret_next-Union{Tuple{T}, Tuple{T, AbstractVector{UInt8}}, Tuple{T, AbstractVector{UInt8}, Int64}} where T<:Integer","page":"Home","title":"CodecLZO.reinterpret_next","text":"reinterpret_next(previous::T, input::AbstractVector{UInt8}, [index::Int = 1])::T\n\nGet the byte from input at index and push it to the LSB of previous, rotating off the MSB. This tries to be faster than doing reinterpret(T, input[index:index+sizeof(T)-1]) twice by reusing the already read LSBs.\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.repeatout!-Tuple{CodecLZO.PassThroughFIFO, Integer, Integer, AbstractVector{UInt8}}","page":"Home","title":"CodecLZO.repeatout!","text":"repeatout!(p::PassThroughFIFO, lookback::Integer, n::Integer, sink::AbstractVector{UInt8})\n\nAppend n values starting from lookback bytes from the end of p to the front of p.\n\nOnce p is full, any bytes that are appended to the front of p will cause bytes from the back to be expelled into the front of sink.\n\nThis method works even if n > lookback, in which case the bytes that were appended to the     front of p first will be repeated.\n\nReturns the number of bytes expelled from p into sink.\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.replace_all_matching!-Union{Tuple{V}, Tuple{K}, Tuple{CodecLZO.HashMap{K, V}, Union{TranscodingStreams.Memory, AbstractVector{UInt8}}, Int64, Union{TranscodingStreams.Memory, AbstractVector{UInt8}}, Int64}} where {K<:Integer, V}","page":"Home","title":"CodecLZO.replace_all_matching!","text":"replace_all_matching!(h::HashMap, input, input_start, output, output_start)\n\nCount the number of elements at the start of input that match the elements at the start of output, putting the matching indices of input as values into h keyed by the K integer read from input at that index.\n\nReturns the number of matching bytes found (not necessarily equal to the number of Ks put into h).\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.resize_front!-Union{Tuple{T}, Tuple{CodecLZO.ModuloBuffer{T}, Integer}} where T","page":"Home","title":"CodecLZO.resize_front!","text":"resize_front!(buffer::ModuloBuffer, n::Integer)::ModuloBuffer\n\nResize buffer to a capacity of n elements efficiently.\n\nIf n < capacity(buffer), only the last n elements of buffer will be retained.\n\nAttempts to avoid allocating new memory by manipulating and resizing the internal vector in place.\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.state-Tuple{LZO1X1CompressorCodec}","page":"Home","title":"CodecLZO.state","text":"state(codec)::MatchingState\n\nDetermine the state of the codec from the command in the buffer.\n\nThe state of the codec can be one of:\n\nFIRST_LITERAL`: in the middle of recording the first literal copy command from the input (the initial state);\nLITERAL: in the middle of writing a literal copy command to the output; or\nHISTORY: in the middle of writing a history copy command to the output.\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.unsafe_decode_run-Tuple{Ptr{UInt8}, Integer, Integer}","page":"Home","title":"CodecLZO.unsafe_decode_run","text":"unsafe_decode_run(p::Ptr{UInt8}, i, bits)::Tuple{Int, Int}\n\nDecode the length of the run in bytes and the number of bytes to copy from the memory address pointed to by p offset by i given a mask of bits bits.\n\nThis method is \"unsafe\" in that it will not stop reading from memory addresses after p until it finds a non-zero byte, whatever the consequences.\n\n\n\n\n\n","category":"method"},{"location":"#CodecLZO.unsafe_encode_run!","page":"Home","title":"CodecLZO.unsafe_encode_run!","text":"unsafe_encode_run!(p::Ptr{UInt8}, len, bits, [i=1])::Int\n\nEmit the number of zero bytes necessary to encode a length len in a command expecting bits leading bits, returning the number of bytes written to the output.\n\nLiteral and copy lengths are always encoded as either a single byte or a sequence of three or more bytes. If len < (1 << bits), the length will be encoded in the lower bits bits of the starting byte of output so the return will be 0. Otherwise, the return will be the number of additional bytes needed to encode the length. The returned number of bytes does not include the zeros in the first byte (the command) used to signal that a run encoding follows, but it does include the remainder.\n\nThis method is \"unsafe\" in that it does not check if p points to an area of memory large enough to hold the resulting run before clobbering it.\n\nNote: the argument len is expected to be the adjusted length for the command. Literals use an adjusted length of len = length(literal) - 3 and copy commands use an adjusted literal length of len = length(copy) - 2.\n\n\n\n\n\n","category":"function"},{"location":"#CodecLZO.unsafe_lzo_compress!","page":"Home","title":"CodecLZO.unsafe_lzo_compress!","text":"unsafe_lzo_compress!(dest::Vector{UInt8}, src, [working_memory=zeros(UInt8, 1<<12)])::Int\n\nCompress src to dest using the LZO 1X1 algorithm.\n\nThe method is \"unsafe\" in that it does not check to see if the compressed output can fit into dest before proceeding, and may write out of bounds or crash your program if the number of bytes required to compress src is larger than the number of bytes available in dest. The method returns the number of bytes written to dest, which may be greater than length(dest).\n\nPass working_memory, a Vector{UInt8} with length(working_memory) >= 1<<12, to reuse pre-allocated memory required by the algorithm.\n\n\n\n\n\n","category":"function"},{"location":"#CodecLZO.unsafe_lzo_decompress!-Tuple{Vector{UInt8}, AbstractVector{UInt8}}","page":"Home","title":"CodecLZO.unsafe_lzo_decompress!","text":"unsafe_lzo_decompress!(dest::Vector{UInt8}, src)::Int\n\nDecompress src to dest using the LZO 1X1 algorithm.\n\nThe method is \"unsafe\" in that it does not check to see if the decompressed output can fit into dest before proceeding, and may write out of bounds or crash your program if the number of bytes required to decompress src is larger than the number of bytes available in dest. The method returns the number of bytes written to dest, which may be greater than length(dest).\n\n\n\n\n\n","category":"method"}]
}
