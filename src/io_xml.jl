"""
Returns OSM data read from a OSM file.
"""
function readosm(filename::String)
    readxmlstream(open(filename, "r"))
end

"""
Returns OSM data queried from a overpass using a `BBox`.
"""
function queryoverpass(bbox::BBox; kwargs...)
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
function queryoverpass(bounds::String; timeout::Int64=25)
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
    osmdata = Map()
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
                osmdata.meta[:writingprogram] = reader["generator"]
            elseif elname == "bounds"
                osmdata.meta[:bbox] = BBox(
                    parse(Float64, reader["minlat"]),
                    parse(Float64, reader["minlon"]),
                    parse(Float64, reader["maxlat"]),
                    parse(Float64, reader["maxlon"])
                )
            elseif elname == "node"
                currentelement = "node"
                currentid = parse(Int64, reader["id"])
                osmdata.nodes[currentid] = Node(
                    LatLon(parse(Float64, reader["lat"]), parse(Float64, reader["lon"])),
                    Dict{String, String}()
                )
            elseif elname == "way"
                currentelement = "way"
                currentid = parse(Int64, reader["id"])
                osmdata.ways[currentid] = Way(Int64[], Dict{String, String}())
            elseif elname == "nd"
                # can only belong to `way`
                @assert currentelement == "way"
                push!(osmdata.ways[currentid].refs, parse(Int64, reader["ref"]))
            elseif elname == "relation"
                currentelement = "relation"
                currentid = parse(Int64, reader["id"])
                osmdata.relations[currentid] = Relation(
                    Int64[], Symbol[], String[], Dict{String, String}()
                )
            elseif elname == "member"
                # can only belong to `relation`
                @assert currentelement == "relation"
                push!(osmdata.relations[currentid].refs, parse(Int64, reader["ref"]))
                push!(osmdata.relations[currentid].types, Symbol(reader["type"]))
                push!(osmdata.relations[currentid].roles, reader["role"])
            elseif elname == "tag"
                # can belong to `node`, `way`, or `relation`
                if currentelement == "node"
                osmdata.nodes[currentid].tags[reader["k"]] = reader["v"]
                elseif currentelement == "way"
                    osmdata.ways[currentid].tags[reader["k"]] = reader["v"]
                elseif currentelement == "relation"
                    osmdata.relations[currentid].tags[reader["k"]] = reader["v"]
                else
                    @error("unrecognized element: $currentelement")
                end
            else
                @warn("unrecognized element: $elname")
            end
        end
    end
    close(reader)
    osmdata
end
