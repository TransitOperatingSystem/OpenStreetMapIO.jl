module OpenStreetMapIO

using ProtoBuf: readproto, PipeBuffer
using CodecZlib: transcode, GzipDecompressor

MAX_BLOB_HEADER_SIZE = 65536          # 64 * 1024
MAX_UNCOMPRESSED_BLOB_SIZE = 33554432 # 32 * 1024 * 1024

# This files have been translated with `protoc` and the Julia plugin `protoc-gen-julia` (2020-03-15)
include("proto/fileformat_pb.jl") # https://github.com/openstreetmap/OSM-binary/blob/master/src/fileformat.proto
include("proto/osmformat_pb.jl")  # https://github.com/openstreetmap/OSM-binary/blob/master/src/osmformat.proto

function readpbf(file::String)
    io = open(file)
    
    data = []
    while !eof(io)
        # the first 4 bytes are the header size (in big-endianness)
        headersize = Int64(reinterpret(UInt32, read!(io, Array{UInt8}(undef, 4))[4:-1:1])[1])
        if headersize >= MAX_BLOB_HEADER_SIZE
            DomainError("blob-header-size is bigger than allowed $(headersize) >  $(MAX_BLOB_HEADER_SIZE)")
        end

        # Read blob header
        blobheader = readproto(PipeBuffer(read!(io, Array{UInt8}(undef, headersize))), BlobHeader())
        blobsize = blobheader.datasize
        if blobsize > MAX_UNCOMPRESSED_BLOB_SIZE
            DomainError("blob-size is bigger than allowed $(blobsize) >  $(MAX_UNCOMPRESSED_BLOB_SIZE)")
        end
        
        # Read blob
        blob = readproto(PipeBuffer(read!(io, Array{UInt8}(undef, blobsize))), Blob())
        if length(blob.raw) > 0
            blobdata = blob.raw
        elseif length(blob.zlib_data)  > 0
            # decompress if data are zlib compresst
            blobdata = transcode(GzipDecompressor, blob.zlib_data)
        elseif length(blob.lzma_data) > 0
            DomainError("lzma-decompression is not supported")
        else
            DomainError("Unsupported blob data format")
        end
        if blob.raw_size > length(blobdata)
            DomainError("blob reports wrong raw_size: $(blob.raw_size) bytes")
        end
        
        append!(data, [(blobheader, blobdata)])
    end
    
    return data
end

end # module
