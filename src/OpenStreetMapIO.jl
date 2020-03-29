module OpenStreetMapIO

using ProtoBuf: readproto, PipeBuffer
using CodecZlib: transcode, GzipDecompressor

MAX_BLOB_HEADER_SIZE = 65536          # 64 * 1024
MAX_UNCOMPRESSED_BLOB_SIZE = 33554432 # 32 * 1024 * 1024

# This files have been translated with `protoc` and the Julia plugin `protoc-gen-julia` (2020-03-15)
include("proto/fileformat_pb.jl") # https://github.com/openstreetmap/OSM-binary/blob/master/src/fileformat.proto
include("proto/osmformat_pb.jl")  # https://github.com/openstreetmap/OSM-binary/blob/master/src/osmformat.proto


function readpbf(file::String, nodecallback=nodecallback, waycallback=waycallback,relationcallback=relationcallback)
    io = open(file)
    c = 0
    
    nodeoutput = []
    wayoutput = []
    relationoutput = []
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
            DomainError("blob-size is bigger than allowed $(blobsize) > $(MAX_UNCOMPRESSED_BLOB_SIZE)")
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

        if blobheader._type == "OSMData"
            primitiveblock = readproto(PipeBuffer(blobdata), PrimitiveBlock())
            # Parse blob data
            # for each primitive group
            for primitivegroup in primitiveblock.primitivegroup
                if isdefined(primitivegroup, :nodes) && !isempty(primitivegroup.nodes)
                    parsenodes!(nodeoutput, primitiveblock, primitivegroup.nodes, nodecallback)
                end
                if isdefined(primitivegroup, :dense) && !isempty(primitivegroup.dense.id)
                    parsedensenodes!(nodeoutput, primitiveblock, primitivegroup.dense, nodecallback)
                end
                if isdefined(primitivegroup, :ways) && !isempty(primitivegroup.ways)
                    parseways!(wayoutput, primitiveblock, primitivegroup.ways, waycallback)
                end
                if isdefined(primitivegroup, :rlations) && !isempty(primitivegroup.relations)
                    parserelations!(relationoutput, primitiveblock, primitivegroup.relations, relationcallback)
                end
            end
        elseif blobheader._type == "OSMHeader"
            # TODO: add stuff
        else
            DomainError("Unknown blob type: " * blobheader._type)
        end
    end
    
    return Dict("nodes" => nodeoutput, "ways" =>wayoutput, "relations" => relationoutput)
end


function parsenodes!(output, primitiveblock, nodes, nodecallback=nodecallback)#, changesetcallback)
    for node in nodes
        lat = 1e-9 * (primitiveblock.lat_offset + primitiveblock.granularity * node.lat)
        lon = 1e-9 * (primitiveblock.lon_offset + primitiveblock.granularity * node.lon)

        # get tags 
        tags = Dict()
        for kv_inx in 1:length(nodes.keys_vals)
            key = String(copy(primitiveblock.stringtable.s[nodes.keys[kv_inx]]))
            value = String(copy(primitiveblock.stringtable.s[nodes.vals[kv_inx]]))
            tags[key] = value
        end
        
        append!(output, nodecallback(node.id, lat, lon, tags))

        # if hasvalues(nods.info) && hasvalues(node.info.changeset) #&& (interest & CHANGESETS) == CHANGESETS)
        #     #changesetcallback(node.info.changeset)
        # end
    end
end


function parsedensenodes!(output, primitiveblock, densenodes, nodecallback=nodecallback)#, changesetcallback)
    id::Int64 = 0
    latitude::Float64 = 0.0
    longitude::Float64 = 0.0
    
    kv_inx::Int64 = 1
    for n_inx in 1:length(densenodes.id)
        id += densenodes.id[n_inx]
        latitude += 1e-9 * (primitiveblock.lat_offset + primitiveblock.granularity * densenodes.lat[n_inx])
        longitude += 1e-9 * (primitiveblock.lon_offset + primitiveblock.granularity * densenodes.lon[n_inx])

        # get tags
        tags = Dict()
        while kv_inx <= length(densenodes.keys_vals) && densenodes.keys_vals[kv_inx] != 0
            key = String(copy(primitiveblock.stringtable.s[densenodes.keys_vals[kv_inx]]))
            value = String(copy(primitiveblock.stringtable.s[densenodes.keys_vals[kv_inx + 1]]))
            kv_inx += 2
            tags[key] = value
        end
        kv_inx += 1

        append!(output, nodecallback(id, latitude, longitude, tags))
    end

    # if hasvalues(densenodes.denseinfo) # && (interest & CHANGESETS) == CHANGESETS)
    #     changeset = 0
    #     for cs in densenodes.denseinfo.changeset
    #         #changesetcallback(changeset += cs)
    #     end
    # end
end


function parseways!(output, primitiveblock, ways, waycallback=waycallback)#, changesetcallback)
    for way in ways 
        node = 0
        nodes = []
        
        for node_id_offset in way.refs
            node += node_id_offset
            append!(nodes, node)
        end
        
        # get tags 
        tags = Dict()
        for kv_inx in 1:length(way.keys)
            key = String(copy(primitiveblock.stringtable.s[way.keys[kv_inx]]))
            value = String(copy(primitiveblock.stringtable.s[way.vals[kv_inx]]))
            tags[key] = value;
        end
        
        append!(output, waycallback(way.id, tags, nodes))
        
        # if hasvalues(way.info) && hasvalues(way.info.changeset) #&& (interest & CHANGESETS) == CHANGESETS)
        #     #changesetcallback(way.info.changeset)
        # end
    end
end


function parserelations!(output, primitiveblock, relations, relationcallback=relationcallback)#, changesetcallback)
    for relation in relations
        member = 0
        members = []
        for m_inx in relation.memids_size
            member += relation.memids[m_inx];
            append!(members, [relation.types[m_inx], member, primitiveblock.stringtable.s[relation.roles_sid[m_inx]]])
        end
        
        # get tags 
        tags = Dict()
        for kv_inx in 1:length(relation.keys_vals)
            key = String(copy(primitiveblock.stringtable.s[relation.keys[kv_inx]]))
            value = String(copy(primitiveblock.stringtable.s[relation.vals[kv_inx]]))
            tags[key] = value;
        end
        
        append!(output, relationcallback(relation.id, tags, members))
        
        # if hasvalues(relation.info) && hasvalues(relation.info.changeset) #&& (interest & CHANGESETS) == CHANGESETS)z
        #     #changesetcallback(relation.info.changeset)
        # end
    end
end


function nodecallback(id, latitude, longitude, tags)
    return [id, latitude, longitude, tags]
end


function waycallback(id, tags, nodes)
    return [id, tags, nodes]
end


function relationcallback(id, tags, members)
    return [id, tags, members]
end


end # module
