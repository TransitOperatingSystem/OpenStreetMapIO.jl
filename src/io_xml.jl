readxml(filename::String, osmdata::OpenStreetMapData=OpenStreetMapData()) =
    readxmlstream(open(filename, "r"), osmdata)


"Returns the overpass query with `bbox = (minlon, minlat, maxlon, maxlat)`"
overpass(bbox::NTuple{4,Float64}; kwargs...) =
    overpass("$(bbox[1]),$(bbox[2]),$(bbox[3]),$(bbox[4])", kwargs...)

"Returns the overpass query within a `radius` (in meters) around `lonlat`"
overpass(lonlat::Tuple{Float64,Float64}, radius::Real; kwargs...) =
    overpass("around:$radius,$(lonlat[1]),$(lonlat[2])", kwargs...)

"Returns the overpass query within `bounds`"
function overpass(bounds::String; timeout::Int=25)
    result = HTTP.request("GET",
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
        """)
    )
    readxmlstream(IOBuffer(result.body))
end

function readxmlstream(
        xmlstream::IO,
        osmdata::OpenStreetMapData=OpenStreetMapData()
    )
    currentelement = ""
    currentid = 0
    reader = StreamReader(xmlstream)
    for typ in reader
        if typ == READER_ELEMENT
            elname = nodename(reader)
            if elname == "bounds"
                @warn("we currently do not handle element: $elname")
            elseif elname == "member"
                @assert currentelement == "relation"
                push!(osmdata.relations[currentid]["role"], reader["role"])
                push!(osmdata.relations[currentid]["id"], parse(Int, reader["ref"]))
                push!(osmdata.relations[currentid]["type"], Symbol(reader["type"]))
            elseif elname == "nd"
                @assert currentelement == "way"
                push!(osmdata.ways[currentid], parse(Int, reader["ref"]))
            elseif elname == "node"
                currentelement = "node"
                currentid = parse(Int, reader["id"])
                push!(osmdata.nodes.id, parse(Int, reader["id"]))
                push!(osmdata.nodes.lat, parse(Float64, reader["lat"]))
                push!(osmdata.nodes.lon, parse(Float64, reader["lon"]))
            elseif elname == "osm"
                @warn("we currently do not handle element: $elname")
            elseif elname == "relation"
                currentelement = "relation"
                currentid = parse(Int, reader["id"])
                osmdata.relations[currentid] = Dict{String,Any}(
                    "role" => Any[],
                    "id" => Int[],
                    "type" => Symbol[]
                )
            elseif elname == "tag"
                osmdata.tags[currentid] = get(osmdata.tags, currentid, Dict())
                osmdata.tags[currentid][reader["k"]] = reader["v"]
            elseif elname == "way"
                currentelement = "way"
                currentid = parse(Int, reader["id"])
                osmdata.ways[currentid] = Int[]
            else
                @warn("unrecognized element: $elname")
            end
        end
    end
    close(reader)
    osmdata
end
