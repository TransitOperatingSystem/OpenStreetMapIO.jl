"""
Read OSM data in PBF format. Data-set are available from various sources, e.g. https://download.geofabrik.de/

Explanation of the data model can be found here https://wiki.openstreetmap.org/wiki/PBF_Format

```
osmdata = OpenStreetMapIO.readpbf("/home/jrklasen/Desktop/hamburg-latest.osm.pbf");

```
"""
function readpbf(filename::String)
    osmdata = OpenStreetMapData()
    blobheader = OSMPBF.BlobHeader()
    blob = OSMPBF.Blob()

    open(filename, "r") do f
        readnext!(f, blobheader, blob)
        @assert blobheader._type == "OSMHeader"
        processheader!(osmdata, readblock!(blob, OSMPBF.HeaderBlock()))
        while !eof(f)
            readnext!(f, blobheader, blob)
            @assert blobheader._type == "OSMData"
            processblock!(osmdata, readblock!(blob, OSMPBF.PrimitiveBlock()))
        end
    end
    osmdata
end

function readnext!(f, blobheader::OSMPBF.BlobHeader, blob::OSMPBF.Blob)
    n = ntoh(read(f, UInt32))
    readproto(PipeBuffer(read(f, n)), blobheader)
    readproto(PipeBuffer(read(f, blobheader.datasize)), blob)
end

function readblock!(blob::OSMPBF.Blob, block:: Union{OSMPBF.HeaderBlock, OSMPBF.PrimitiveBlock})
    @assert xor(isempty(blob.raw), isempty(blob.zlib_data))
    if !isempty(blob.raw)
        readproto(PipeBuffer(blob.raw), block)
    elseif !isempty(blob.zlib_data)
        readproto(
            ZlibDecompressorStream(IOBuffer(blob.zlib_data)),
            block
        )
    else
        DomainError("Unsupported blob data format")
    end
end

function processheader!(osmdata::OpenStreetMapData, header::OSMPBF.HeaderBlock)
    if hasproperty(header, :bbox)
        osmdata.fileinfo.bbox = BoundingBox(1e-9 * header.bbox.bottom, 1e-9 * header.bbox.left, 1e-9 * header.bbox.top, 1e-9 * header.bbox.right)
    end
    if hasproperty(header, :osmosis_replication_timestamp)
        osmdata.fileinfo.writenat = unix2datetime(header.osmosis_replication_timestamp)
    end
    if hasproperty(header, :osmosis_replication_sequence_number)
        osmdata.fileinfo.sequencenumber = header.osmosis_replication_sequence_number
    end
    if hasproperty(header, :osmosis_replication_base_url)
        osmdata.fileinfo.baseurl = header.osmosis_replication_base_url
    end
    if hasproperty(header, :writingprogram)
        osmdata.fileinfo.writingprogram = header.writingprogram
    end
end

function processblock!(osmdata::OpenStreetMapData, primblock::OSMPBF.PrimitiveBlock)
    lookuptable =  Base.transcode.(String, primblock.stringtable.s)
    latlonparameter = Dict(:lat_offset =>  primblock.lat_offset, :lon_offset =>  primblock.lon_offset, :granularity => primblock.granularity)

    for primgrp in primblock.primitivegroup
        if hasproperty(primgrp, :dense)
            densenodes!(osmdata, primgrp, lookuptable, latlonparameter)
        end
        nodes!(osmdata, primgrp, lookuptable)
        ways!(osmdata, primgrp, lookuptable)
        relations!(osmdata, primgrp, lookuptable)
    end
end

function densenodes!(osmdata::OpenStreetMapData, primgrp::OSMPBF.PrimitiveGroup, lookuptable::Vector{String}, latlonparameter::Dict)
    osmids = cumsum(primgrp.dense.id)
    append!(osmdata.nodes.id, osmids)
    append!(
        osmdata.nodes.lat,
        1e-9 * (latlonparameter[:lat_offset] .+ latlonparameter[:granularity] .* cumsum(primgrp.dense.lat))
    )
    append!(
        osmdata.nodes.lon,
        1e-9 * (latlonparameter[:lon_offset] .+ latlonparameter[:granularity] .* cumsum(primgrp.dense.lon))
    )

    # decode tags i: node id index, kv: key-value index, k: key index, v: value index
    let i = 1, kv = 1
        @assert primgrp.dense.keys_vals[end] == 0
        while kv <= length(primgrp.dense.keys_vals)
            k = primgrp.dense.keys_vals[kv]
            if k == 0
                # move to next node
                i += 1; kv += 1
            else
                # continue with current note
                @assert kv < length(primgrp.dense.keys_vals)
                v = primgrp.dense.keys_vals[kv + 1]
                id = osmids[i]
                osmdata.tags[id] = get(osmdata.tags, id, Dict())
                osmdata.tags[id][Symbol(lookuptable[k + 1])] = lookuptable[v + 1]
                kv += 2
            end
        end
    end
end

function nodes!(osmdata::OpenStreetMapData, primgrp::OSMPBF.PrimitiveGroup, lookuptable::Vector{String})
    for n in primgrp.nodes
        push!(osmdata.nodes.id, n.id)
        push!(osmdata.nodes.lon, n.lon)
        push!(osmdata.nodes.lat, n.lat)
        @assert length(n.keys) == length(n.vals)
        osmdata.tags[n.id] = get(osmdata.tags, n.id, Dict())
        for (k, v) in zip(n.keys, n.vals)
            osmdata.tags[n.id][Symbol(lookuptable[k + 1])] = lookuptable[v + 1]
        end
    end
end

function ways!(osmdata::OpenStreetMapData, primgrp::OSMPBF.PrimitiveGroup, lookuptable::Vector{String})
    for w in primgrp.ways
        osmdata.ways[w.id] = cumsum(w.refs)
        osmdata.tags[w.id] = get(osmdata.tags, w.id, Dict())
        for (k, v) in zip(w.keys, w.vals)
            osmdata.tags[w.id][Symbol(lookuptable[k + 1])] = lookuptable[v + 1]
        end
    end
end

function relations!(osmdata::OpenStreetMapData, primgrp::OSMPBF.PrimitiveGroup, lookuptable::Vector{String})
    for r in primgrp.relations
        osmdata.relations[r.id] = Dict(:id => cumsum(r.memids), :type => membertype.(r.types), :role => lookuptable[r.roles_sid .+ 1])
        osmdata.tags[r.id] = get(osmdata.tags, r.id, Dict())
        for (k, v) in zip(r.keys, r.vals)
            osmdata.tags[r.id][Symbol(lookuptable[k + 1])] = lookuptable[v + 1]
        end
    end
end

function membertype(i)
    if i == 0; :node elseif i == 1; :way else; :relation end
end
