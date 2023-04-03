using ProtoBuf: decode, ProtoDecoder, PipeBuffer
using CodecZlib: ZlibDecompressorStream
using Dates: unix2datetime, DateTime

"""
	readpbf(filename)

`readpbf` has one mendatory argument `filename`, taking a string of the pbf-file path and name.
In addion three optional arguments exist.
This aguments are for node, way, and relation callback functions.
This functions are expected to have one input agumemnt of type `Node`, `Way`, or `Relation` and return a value of the same type or of type  Nothing.
If the return value is `nothing` the element is not added to the `OpenStreetMap` object.
If the return value is of type `Node`, `Way`, or `Relation` the element is added to the `OpenStreetMap` object.
If no callback function is given, all elements are added to the `OpenStreetMap` object.
"""
function readpbf(
    filename::String;
    node_callback::Union{Function, Nothing} = nothing,
    way_callback::Union{Function, Nothing} = nothing,
    relation_callback::Union{Function, Nothing} = nothing,
)::OpenStreetMap
    osmdata = OpenStreetMap()
    open(filename, "r") do f
        blobheader, blob = readnext!(f)
        @assert blobheader.var"#type" == "OSMHeader"
        processheader!(osmdata, readblock!(blob, OSMPBF.HeaderBlock))
        while !eof(f)
            blobheader, blob = readnext!(f)
            @assert blobheader.var"#type" == "OSMData"
            processblock!(
                osmdata,
                readblock!(blob, OSMPBF.PrimitiveBlock),
                node_callback,
                way_callback,
                relation_callback,
            )
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
            block,
        )
    else
        DomainError("Unsupported blob data format")
    end
end

function processheader!(osmdata::OpenStreetMap, header::OSMPBF.HeaderBlock)
    if hasproperty(header, :bbox)
        osmdata.meta["bbox"] = BBox(
            round(1e-9 * header.bbox.bottom, digits = 7),
            round(1e-9 * header.bbox.left, digits = 7),
            round(1e-9 * header.bbox.top, digits = 7),
            round(1e-9 * header.bbox.right, digits = 7),
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

function processblock!(
    osmdata::OpenStreetMap,
    primblock::OSMPBF.PrimitiveBlock,
    node_callback::Union{Function, Nothing},
    way_callback::Union{Function, Nothing},
    relation_callback::Union{Function, Nothing},
)
    lookuptable = Base.transcode.(String, primblock.stringtable.s)
    latlonparameter = Dict(
        :lat_offset => primblock.lat_offset,
        :lon_offset => primblock.lon_offset,
        :granularity => primblock.granularity,
    )
    for primgrp in primblock.primitivegroup
        # Possible extension: callback functions for the selecton of specific elements (e.g. for routing).
        merge!(osmdata.nodes, extractnodes(primgrp, lookuptable, node_callback))
        if hasproperty(primgrp, :dense)
            merge!(osmdata.nodes, extractdensenodes(primgrp, lookuptable, latlonparameter, node_callback))
        end
        merge!(osmdata.ways, extractways(primgrp, lookuptable, way_callback))
        merge!(osmdata.relations, extractrelations(primgrp, lookuptable, relation_callback))
    end
end

function extractnodes(
    primgrp::OSMPBF.PrimitiveGroup,
    lookuptable::Vector{String},
    node_callback::Union{Function, Nothing},
)::Dict{Int64, Node}
    nodes = Dict{Int64, Node}()
    for n in primgrp.nodes
        @assert length(n.keys) == length(n.vals)
        if length(n.keys) > 0
            tags = Dict{String, String}()
            for (k, v) in zip(n.keys, n.vals)
                tags[lookuptable[k+1]] = lookuptable[v+1]
            end
            node = Node(LatLon(n.lat, n.lon), tags)
        else
            node = Node(LatLon(n.lat, n.lon), nothing)
        end
        if node_callback !== nothing
            cb_node = node_callback(node)
            if cb_node !== nothing
                nodes[n.id] = cb_node
            end
        else
            nodes[n.id] = node
        end
    end
    return nodes
end

function extractdensenodes(
    primgrp::OSMPBF.PrimitiveGroup,
    lookuptable::Vector{String},
    latlonparameter::Dict,
    node_callback::Union{Function, Nothing},
)::Dict{Int64, Node}
    if primgrp.dense === nothing
        return Dict{Int64, Node}()
    end
    ids = cumsum(primgrp.dense.id)
    lats =
        round.(
            1e-9 * (latlonparameter[:lat_offset] .+ latlonparameter[:granularity] .* cumsum(primgrp.dense.lat)),
            digits = 7,
        )
    lons =
        round.(
            1e-9 * (latlonparameter[:lon_offset] .+ latlonparameter[:granularity] .* cumsum(primgrp.dense.lon)),
            digits = 7,
        )
    @assert length(ids) == length(lats) == length(lons)
    # extract tags
    @assert primgrp.dense.keys_vals[end] == 0
    # decode tags i: node id index, kv: key-value index, k: key index, v: value index
    i = 1
    kv = 1
    tags = Dict{Int64, Dict{String, String}}()
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
                tags[id] = Dict{String, String}()
            end
            tags[id][lookuptable[k+1]] = lookuptable[v+1]
            kv += 2
        end
    end
    # assemble Node objects
    nodes = Dict{Int64, Node}()
    for (id, lat, lon) in zip(ids, lats, lons)
        node = Node(LatLon(lat, lon), get(tags, id, nothing))
        if node_callback !== nothing
            cb_node = node_callback(node)
            if cb_node !== nothing
                nodes[id] = cb_node
            end
        else
            nodes[id] = node
        end
    end
    return nodes
end

function extractways(
    primgrp::OSMPBF.PrimitiveGroup,
    lookuptable::Vector{String},
    way_callback::Union{Function, Nothing},
)::Dict{Int64, Way}
    ways = Dict{Int64, Way}()
    for w in primgrp.ways
        if length(w.keys) > 0
            tags = Dict{String, String}()
            for (k, v) in zip(w.keys, w.vals)
                tags[lookuptable[k+1]] = lookuptable[v+1]
            end
            way = Way(cumsum(w.refs), tags)
        else
            way = Way(cumsum(w.refs), nothing)
        end
        if way_callback !== nothing
            cb_way = way_callback(way)
            if cb_way !== nothing
                ways[w.id] = cb_way
            end
        else
            ways[w.id] = way
        end
    end
    return ways
end

function extractrelations(
    primgrp::OSMPBF.PrimitiveGroup,
    lookuptable::Vector{String},
    relation_callback::Union{Function, Nothing},
)::Dict{Int64, Relation}
    relations = Dict{Int64, Relation}()
    for r in primgrp.relations
        if length(r.keys) > 0
            tags = Dict{String, String}()
            for (k, v) in zip(r.keys, r.vals)
                tags[lookuptable[k+1]] = lookuptable[v+1]
            end
            relation = Relation(cumsum(r.memids), membertype.(r.types), lookuptable[r.roles_sid.+1], tags)
        else
            relation = Relation(cumsum(r.memids), membertype.(r.types), lookuptable[r.roles_sid.+1], nothing)
        end
        if relation_callback !== nothing
            cb_relation = relation_callback(r.id, relation)
            if callback !== nothing
                relations[r.id] = cb_relation
            end
        else
            relations[r.id] = relation
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
