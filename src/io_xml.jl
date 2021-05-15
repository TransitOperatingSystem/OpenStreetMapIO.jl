"""
Returns OSM data read from a OSM file.
"""
function readosm(filename::String)
    readxmlstream(open(filename, "r"))
end

"""
Returns OSM data queried from a overpass using a BoundingBox.
"""
function queryoverpass(bbox::BoundingBox; kwargs...)
    queryoverpass("$(bbox.bottom_lat),$(bbox.left_lon),$(bbox.top_lat),$(bbox.right_lon)", kwargs...)
end


"""
Returns OSM data queried from a overpass using `radius`.
"""
function queryoverpass(lonlat::LatLon, radius::Real; kwargs...)
    queryoverpass("around:$radius,$(lonlat.lat),$(lonlatl.lon)", kwargs...)
end


"""
Returns OSM data queried from a overpass using a `bounds`.
"""
function queryoverpass(bounds::String; timeout::Int=25)
    result = request(
        "GET",
        "https://overpass-api.de/api/interpreter",
        query=Dict("data" => """
                [out:xml][timeout:$timeout];
                (
                    node($bounds);
                    way($bounds);
                    relation($bounds);
                );
                out body;
                >;
                out skel qt;
            """
        )
    )
    readxmlstream(IOBuffer(result.body))
end

"""
creation ´timestamp´ and ´version´ of element are for the time being discarded
https://wiki.openstreetmap.org/wiki/OSM_XML
"""
function readxmlstream(xmlstream::IO)
    osmdata = OpenStreetMapData()
    currentelement = ""
    currentid = 0
    reader = StreamReader(xmlstream)
    for typ in reader
        if typ == READER_ELEMENT
            elname = nodename(reader)
            if elname == "osm"
                version = reader["version"]
                if version != "0.6"
                    @warn("This is version $version, currently only vesrion `0.6` is supported")
                end
                osmdata.fileinfo.writingprogram = reader["generator"]
            elseif elname == "bounds"
                osmdata.fileinfo.bbox = BoundingBox(
                    parse(Float64, reader["minlat"]),
                    parse(Float64, reader["minlon"]),
                    parse(Float64, reader["maxlat"]),
                    parse(Float64, reader["maxlon"])
                )
            elseif elname == "node"
                currentelement = "node"
                currentid = parse(Int, reader["id"])
                push!(osmdata.nodes.id, parse(Int, reader["id"]))
                push!(osmdata.nodes.lat, parse(Float64, reader["lat"]))
                push!(osmdata.nodes.lon, parse(Float64, reader["lon"]))
            elseif elname == "way"
                currentelement = "way"
                currentid = parse(Int, reader["id"])
                osmdata.ways[currentid] = Int[]
            elseif elname == "relation"
                currentelement = "relation"
                currentid = parse(Int, reader["id"])
                osmdata.relations[currentid] = Dict{Symbol,Any}(
                    :role => Any[],
                    :id => Int[],
                    :type => Symbol[]
                )
            elseif elname == "tag"
                # can belong to `node`, `way`, or `relation`
                osmdata.tags[currentid] = get(osmdata.tags, currentid, Dict())
                osmdata.tags[currentid][Symbol(reader["k"])] = reader["v"]
            elseif elname == "nd"
                # can only belong to `way`
                @assert currentelement == "way"
                push!(osmdata.ways[currentid], parse(Int, reader["ref"]))
            elseif elname == "member"
                # can only belong to `relation`
                @assert currentelement == "relation"
                push!(osmdata.relations[currentid][:role], reader["role"])
                push!(osmdata.relations[currentid][:id], parse(Int, reader["ref"]))
                push!(osmdata.relations[currentid][:type], Symbol(reader["type"]))
            else
                @warn("unrecognized element: $elname")
            end
        end
    end
    close(reader)
    osmdata
end
