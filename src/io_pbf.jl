using ProtoBuf: decode, ProtoDecoder, PipeBuffer
using CodecZlib: ZlibDecompressorStream
using Dates: unix2datetime, DateTime

"""
    readpbf(filename)

`readpbf` has only one argument `filename`, taking a string of the pbf-file path and name.
It returns an object containing the OSM data.
"""
function readpbf(filename::String)::OpenStreetMap
    osmdata = OpenStreetMap()
    open(filename, "r") do f
        blobheader, blob = readnext!(f)
        @assert blobheader.var"#type" == "OSMHeader"
        processheader!(osmdata, readblock!(blob, OSMPBF.HeaderBlock))
        while !eof(f)
            blobheader, blob = readnext!(f)
            @assert blobheader.var"#type" == "OSMData"
            processblock!(osmdata, readblock!(blob, OSMPBF.PrimitiveBlock))
        end
    end
    return osmdata
end

function readnext!(f)
    n = ntoh(read(f, UInt32))
    blobheader = decode(ProtoDecoder(PipeBuffer(read(f, n))), OSMPBF.BlobHeader)
    blob = decode(ProtoDecoder(PipeBuffer(read(f, blobheader.datasize))), OSMPBF.Blob)
    return blobheader, blob
end

function readblock!(blob::OSMPBF.Blob, block::Union{Type{OSMPBF.HeaderBlock}, Type{OSMPBF.PrimitiveBlock}})
    @assert xor(isempty(blob.raw), isempty(blob.zlib_data))
    if !isempty(blob.raw)
        decode(ProtoDecoder(PipeBuffer(blob.raw)), block)
    elseif !isempty(blob.zlib_data)
        decode(
            ProtoDecoder(ZlibDecompressorStream(IOBuffer(blob.zlib_data))),
            block
        )
    else
        DomainError("Unsupported blob data format")
    end
end

function processheader!(osmdata::OpenStreetMap, header::OSMPBF.HeaderBlock)
    if hasproperty(header, :bbox)
        osmdata.meta["bbox"] = BBox(
            round(1e-9 * header.bbox.bottom, digits=7),
            round(1e-9 * header.bbox.left, digits=7),
            round(1e-9 * header.bbox.top, digits=7),
            round(1e-9 * header.bbox.right, digits=7)
        )
    end
    if hasproperty(header, :osmosis_replication_timestamp)
        osmdata.meta["writenat"] = unix2datetime(header.osmosis_replication_timestamp)
    end
    if hasproperty(header, :osmosis_replication_sequence_number)
        osmdata.meta["sequencenumber"] = header.osmosis_replication_sequence_number
    end
    if hasproperty(header, :osmosis_replication_base_url)
        osmdata.meta["baseurl"] = header.osmosis_replication_base_url
    end
    if hasproperty(header, :writingprogram)
        osmdata.meta["writingprogram"] = header.writingprogram
    end
end

function processblock!(osmdata::OpenStreetMap, primblock::OSMPBF.PrimitiveBlock)
    lookuptable = Base.transcode.(String, primblock.stringtable.s)
    latlonparameter = Dict(
        :lat_offset => primblock.lat_offset,
        :lon_offset => primblock.lon_offset,
        :granularity => primblock.granularity
    )
    for primgrp in primblock.primitivegroup
        # Possible extension: callback functions for the selecton of specific elements (e.g. for routing).
        merge!(osmdata.nodes, extractnodes(primgrp, lookuptable))
        if hasproperty(primgrp, :dense)
            merge!(osmdata.nodes, extractdensenodes(primgrp, lookuptable, latlonparameter))
        end
        merge!(osmdata.ways, extractways(primgrp, lookuptable))
        merge!(osmdata.relations, extractrelations(primgrp, lookuptable))
    end
end

function extractnodes(primgrp::OSMPBF.PrimitiveGroup, lookuptable::Vector{String})::Dict{Int64,Node}
    nodes = Dict{Int64,Node}()
    for n in primgrp.nodes
        @assert length(n.keys) == length(n.vals)
        if length(n.keys) > 0
            tags = Dict{String,String}()
            for (k, v) in zip(n.keys, n.vals)
                tags[lookuptable[k+1]] = lookuptable[v+1]
            end
            nodes[n.id] = Node(LatLon(n.lat, n.lon), tags)
        else
            nodes[n.id] = Node(LatLon(n.lat, n.lon), nothing)
        end
    end
    return nodes
end

function extractdensenodes(primgrp::OSMPBF.PrimitiveGroup, lookuptable::Vector{String}, latlonparameter::Dict)::Dict{Int64,Node}
    if primgrp.dense === nothing
        return Dict{Int64,Node}()
    end
    ids = cumsum(primgrp.dense.id)
    lats = round.(1e-9 * (latlonparameter[:lat_offset] .+ latlonparameter[:granularity] .* cumsum(primgrp.dense.lat)), digits=7)
    lons = round.(1e-9 * (latlonparameter[:lon_offset] .+ latlonparameter[:granularity] .* cumsum(primgrp.dense.lon)), digits=7)
    @assert length(ids) == length(lats) == length(lons)
    # extract tags
    @assert primgrp.dense.keys_vals[end] == 0
    # decode tags i: node id index, kv: key-value index, k: key index, v: value index
    i = 1
    kv = 1
    tags = Dict{Int64,Dict{String,String}}()
    while kv <= length(primgrp.dense.keys_vals)
        k = primgrp.dense.keys_vals[kv]
        if k == 0
            # move to next node
            i += 1
            kv += 1
        else
            # continue with current note
            @assert kv < length(primgrp.dense.keys_vals)
            v = primgrp.dense.keys_vals[kv+1]
            id = ids[i]
            if !haskey(tags, id)
                tags[id] = Dict{String,String}()
            end
            tags[id][lookuptable[k+1]] = lookuptable[v+1]
            kv += 2
        end
    end
    # assemble Node objects
    nodes = Dict{Int64,Node}()
    for (id, lat, lon) in zip(ids, lats, lons)
        nodes[id] = Node(LatLon(lat, lon), get(tags, id, nothing))
    end
    return nodes
end

function extractways(primgrp::OSMPBF.PrimitiveGroup, lookuptable::Vector{String})::Dict{Int64,Way}
    ways = Dict{Int64,Way}()
    for w in primgrp.ways
        if length(w.keys) > 0
            tags = Dict{String,String}()
            for (k, v) in zip(w.keys, w.vals)
                tags[lookuptable[k+1]] = lookuptable[v+1]
            end
            ways[w.id] = Way(cumsum(w.refs), tags)
        else
            ways[w.id] = Way(cumsum(w.refs), nothing)
        end
    end
    return ways
end

function extractrelations(primgrp::OSMPBF.PrimitiveGroup, lookuptable::Vector{String})::Dict{Int64,Relation}
    relations = Dict{Int64,Relation}()
    for r in primgrp.relations
        if length(r.keys) > 0
            tags = Dict{String,String}()
            for (k, v) in zip(r.keys, r.vals)
                tags[lookuptable[k+1]] = lookuptable[v+1]
            end
            relations[r.id] = Relation(cumsum(r.memids), membertype.(r.types), lookuptable[r.roles_sid.+1], tags)
        else
            relations[r.id] = Relation(cumsum(r.memids), membertype.(r.types), lookuptable[r.roles_sid.+1], nothing)
        end
    end
    return relations
end

function membertype(i)
    if i == 0
        "node"
    elseif i == 1
        "way"
    else
        "relation"
    end
end
