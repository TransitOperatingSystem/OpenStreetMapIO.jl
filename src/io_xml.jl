using EzXML
using HTTP: request

"""
    readosm(filename)

Returns OSM data read from a OSM file.
"""
function readosm(filename::String)::Map
    return readxmldoc(EzXML.readxml(open(filename, "r")))
end

"""
    queryoverpass(bbox)

Returns OSM data queried from a overpass using a `BBox`.
"""
function queryoverpass(bbox::BBox; kwargs...)::Map
    osmdata = queryoverpass("$(bbox.bottom_lat),$(bbox.left_lon),$(bbox.top_lat),$(bbox.right_lon)", kwargs...)
    return osmdata
end


"""
    queryoverpass(lonlat, radius)

Returns OSM data queried from a overpass using `radius`.
"""
function queryoverpass(lonlat::LatLon, radius::Real; kwargs...)
    osmdata = queryoverpass("around:$radius,$(lonlat.lat),$(lonlatl.lon)", kwargs...)
    return osmdata
end


"""
    queryoverpass(bounds)

Returns OSM data queried from a overpass using a `bounds`.
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

Explanation of the pbf-data-model can be found here https://wiki.openstreetmap.org/wiki/OSM_XML
"""
function readxmldoc(xmldoc::EzXML.Document)::Map
    osmdata = Map()
    # Iterate over child elements.
    for xmlnode in EzXML.eachelement(root(xmldoc))
        elname = EzXML.nodename(xmlnode)
        if elname == "bounds"
            osmdata.meta[:bbox] = osmbound(xmlnode)
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
                    tags = Dict{Symbol,String}()
                end
                tags[Symbol(subxmlnode["k"])] = subxmlnode["v"]
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
                    tags = Dict{Symbol,String}()
                end
                tags[Symbol(subxmlnode["k"])] = subxmlnode["v"]
            end
        end
    end
    return id, Way(refs, tags)
end

function osmrelation(xmlnode::EzXML.Node)::Tuple{Int64,Relation}
    id = parse(Int64, xmlnode["id"])
    refs = Int64[]
    types = Symbol[]
    roles = String[]
    tags = nothing
    if EzXML.haselement(xmlnode)
        # Iterate over child elements.
        for subxmlnode in EzXML.eachelement(xmlnode)
            elname = EzXML.nodename(subxmlnode)
            if elname == "member"
                push!(refs, parse(Int64, subxmlnode["ref"]))
                push!(types, Symbol(subxmlnode["type"]))
                push!(roles, subxmlnode["role"])
            elseif elname == "tag"
                if tags === nothing
                    tags = Dict{Symbol,String}()
                end
                tags[Symbol(subxmlnode["k"])] = subxmlnode["v"]
            end
        end
    end
    return id, Relation(refs, types, roles, tags)
end

function osmunknown(xmlnode::EzXML.Node)::Dict{Symbol,Any}
    out = Dict{Symbol,Any}()
    for kv in EzXML.attributes(xmlnode)
        out[Symbol(EzXML.nodename(kv))] = EzXML.nodecontent(kv)
    end
    if EzXML.haselement(xmlnode)
        for subxmlnode in EzXML.eachelement(xmlnode)
            elname = EzXML.nodename(subxmlnode)
            out[Symbol(elname)] = osmunknown(subxmlnode)
        end
    end
    return out
end