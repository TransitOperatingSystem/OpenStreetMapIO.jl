using EzXML
using HTTP: request

"""
    readosm(filename)

`readosm` has only one argument `filename`, taking a string of the pbf-file path and name.
It returns an object containing the OSM data.
"""
function readosm(filename::String)::Map
    return readxmldoc(EzXML.readxml(open(filename, "r")))
end

"""
    queryoverpass(bbox)

`queryoverpass` has only one argument `bbox`.
It returns an object containing the OSM data.
"""
function queryoverpass(bbox::BBox; kwargs...)::Map
    osmdata = queryoverpass("$(bbox.bottom_lat),$(bbox.left_lon),$(bbox.top_lat),$(bbox.right_lon)", kwargs...)
    return osmdata
end

"""
    queryoverpass(lonlat, radius)

`queryoverpass` has two arguments, `lonlat` and `radius`.
It returns an object containing the OSM data.
"""
function queryoverpass(lonlat::LatLon, radius::Real; kwargs...)
    osmdata = queryoverpass("around:$radius,$(lonlat.lat),$(lonlatl.lon)", kwargs...)
    return osmdata
end

"""
    queryoverpass(bounds)

`queryoverpass` has only one argument `bounds`.
It returns an object containing the OSM data.
"""
function queryoverpass(bounds::String; timeout::Int64=25)::Map
    query = """
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
    result = request(
        "GET",
        "https://overpass-api.de/api/interpreter",
        query=Dict("data" => query)
    )
    return readxmldoc(EzXML.readxml(IOBuffer(result.body)))
end

"""
The argument is a xml document, it returns an osm object.
"""
function readxmldoc(xmldoc::EzXML.Document)::Map
    osmdata = Map()
    # Iterate over child elements.
    for xmlnode in EzXML.eachelement(root(xmldoc))
        elname = EzXML.nodename(xmlnode)
        if elname == "bounds"
            osmdata.meta["bbox"] = osmbound(xmlnode)
        elseif elname == "node"
            k, v = osmnode(xmlnode)
            osmdata.nodes[k] = v
        elseif elname == "way"
            k, v = osmway(xmlnode)
            osmdata.ways[k] = v
        elseif elname == "relation"
            k, v = osmrelation(xmlnode)
            osmdata.relations[k] = v
        else
            merge!(osmdata.meta, osmunknown(xmlnode))
        end
    end
    return osmdata
end

function osmbound(xmlnode::EzXML.Node)::BBox
    bbox = BBox(
        parse(Float64, xmlnode["minlat"]),
        parse(Float64, xmlnode["minlon"]),
        parse(Float64, xmlnode["maxlat"]),
        parse(Float64, xmlnode["maxlon"])
    )
    return bbox
end

function osmnode(xmlnode::EzXML.Node)::Tuple{Int64,Node}
    id = parse(Int64, xmlnode["id"])
    latlon = LatLon(
        parse(Float64, xmlnode["lat"]),
        parse(Float64, xmlnode["lon"])
    )
    tags = nothing
    if EzXML.haselement(xmlnode)
        # Iterate over child elements.
        for subxmlnode in EzXML.eachelement(xmlnode)
            elname = EzXML.nodename(subxmlnode)
            if elname == "tag"
                if tags === nothing
                    tags = Dict{String,String}()
                end
                tags[subxmlnode["k"]] = subxmlnode["v"]
            end
        end
    end
    return id, Node(latlon, tags)
end

function osmway(xmlnode::EzXML.Node)::Tuple{Int64,Way}
    id = parse(Int64, xmlnode["id"])
    refs = []
    tags = nothing
    if EzXML.haselement(xmlnode)
        # Iterate over child elements.
        for subxmlnode in EzXML.eachelement(xmlnode)
            elname = EzXML.nodename(subxmlnode)
            if elname == "nd"
                push!(refs, parse(Int64, subxmlnode["ref"]))
            elseif elname == "tag"
                if tags === nothing
                    tags = Dict{String,String}()
                end
                tags[subxmlnode["k"]] = subxmlnode["v"]
            end
        end
    end
    return id, Way(refs, tags)
end

function osmrelation(xmlnode::EzXML.Node)::Tuple{Int64,Relation}
    id = parse(Int64, xmlnode["id"])
    refs = Int64[]
    types = String[]
    roles = String[]
    tags = nothing
    if EzXML.haselement(xmlnode)
        # Iterate over child elements.
        for subxmlnode in EzXML.eachelement(xmlnode)
            elname = EzXML.nodename(subxmlnode)
            if elname == "member"
                push!(refs, parse(Int64, subxmlnode["ref"]))
                push!(types, subxmlnode["type"])
                push!(roles, subxmlnode["role"])
            elseif elname == "tag"
                if tags === nothing
                    tags = Dict{String,String}()
                end
                tags[subxmlnode["k"]] = subxmlnode["v"]
            end
        end
    end
    return id, Relation(refs, types, roles, tags)
end

function osmunknown(xmlnode::EzXML.Node)::Dict{String,Any}
    out = Dict{String,Any}()
    for kv in EzXML.attributes(xmlnode)
        out[EzXML.nodename(kv)] = EzXML.nodecontent(kv)
    end
    if EzXML.haselement(xmlnode)
        for subxmlnode in EzXML.eachelement(xmlnode)
            elname = EzXML.nodename(subxmlnode)
            out[elname] = osmunknown(subxmlnode)
        end
    end
    return out
end
