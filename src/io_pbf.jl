"""
Returns OSM data read from a PBF file. Data-set are available from various sources, e.g. https://download.geofabrik.de/

Explanation of the data model can be found here https://wiki.openstreetmap.org/wiki/PBF_Format

```
osmdata = OpenStreetMapIO.readpbf("/home/jrklasen/Desktop/hamburg-latest.osm.pbf");

```
"""
function readpbf(filename::String)
    osmdata = Map()
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

function processheader!(osmdata::Map, header::OSMPBF.HeaderBlock)
    if hasproperty(header, :bbox)
        osmdata.meta[:bbox] = BBox(
            1e-9 * header.bbox.bottom,
            1e-9 * header.bbox.left,
            1e-9 * header.bbox.top,
            1e-9 * header.bbox.right
        )
    end
    if hasproperty(header, :osmosis_replication_timestamp)
        osmdata.meta[:writenat] = unix2datetime(header.osmosis_replication_timestamp)
    end
    if hasproperty(header, :osmosis_replication_sequence_number)
        osmdata.meta[:sequencenumber] = header.osmosis_replication_sequence_number
    end
    if hasproperty(header, :osmosis_replication_base_url)
        osmdata.meta[:baseurl] = header.osmosis_replication_base_url
    end
    if hasproperty(header, :writingprogram)
        osmdata.meta[:writingprogram] = header.writingprogram
    end
end

function processblock!(osmdata::Map, primblock::OSMPBF.PrimitiveBlock)
    lookuptable =  Base.transcode.(String, primblock.stringtable.s)
    latlonparameter = Dict(
        :lat_offset =>  primblock.lat_offset,
        :lon_offset =>  primblock.lon_offset,
        :granularity => primblock.granularity
    )

    for primgrp in primblock.primitivegroup
        if hasproperty(primgrp, :dense)
            densenodes!(osmdata, primgrp, lookuptable, latlonparameter)
        end
        nodes!(osmdata, primgrp, lookuptable)
        ways!(osmdata, primgrp, lookuptable)
        relations!(osmdata, primgrp, lookuptable)
    end
end

function densenodes!(osmdata::Map, primgrp::OSMPBF.PrimitiveGroup, lookuptable::Vector{String}, latlonparameter::Dict)
    ids = cumsum(primgrp.dense.id)
    lats = 1e-9 * (latlonparameter[:lat_offset] .+ latlonparameter[:granularity] .* cumsum(primgrp.dense.lat))
    lons = 1e-9 * (latlonparameter[:lon_offset] .+ latlonparameter[:granularity] .* cumsum(primgrp.dense.lon))
    @assert length(ids) == length(lats) == length(lons)
    for (id, lat, lon) in zip(ids, lats, lons)
        osmdata.nodes[id] = Node(LatLon(lat, lon), Dict{String, String}())
    end
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
                id = ids[i]
                osmdata.nodes[id].tags[lookuptable[k + 1]] = lookuptable[v + 1]
                kv += 2
            end
        end
    end
end

function nodes!(osmdata::Map, primgrp::OSMPBF.PrimitiveGroup, lookuptable::Vector{String})
    for n in primgrp.nodes
        osmdata.nodes[n.id] = Node(LatLon(lat, lon), Dict{String, String}())
        @assert length(n.keys) == length(n.vals)
        for (k, v) in zip(n.keys, n.vals)
            osmdata.nodes[n.id].tags[lookuptable[k + 1]] = lookuptable[v + 1]
        end
    end
end

function ways!(osmdata::Map, primgrp::OSMPBF.PrimitiveGroup, lookuptable::Vector{String})
    for w in primgrp.ways
        osmdata.ways[w.id] = Way(cumsum(w.refs), Dict{String, String}())
        for (k, v) in zip(w.keys, w.vals)
            osmdata.ways[w.id].tags[lookuptable[k + 1]] = lookuptable[v + 1]
        end
    end
end

function relations!(osmdata::Map, primgrp::OSMPBF.PrimitiveGroup, lookuptable::Vector{String})
    for r in primgrp.relations
        osmdata.relations[r.id] = Relation(
            cumsum(r.memids),
            membertype.(r.types),
            lookuptable[r.roles_sid .+ 1],
            Dict{String, String}()
        )
        for (k, v) in zip(r.keys, r.vals)
            osmdata.relations[r.id].tags[lookuptable[k + 1]] = lookuptable[v + 1]
        end
    end
end

function membertype(i)
    if i == 0; :node elseif i == 1; :way else; :relation end
end
