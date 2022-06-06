include("protobuf/OSMPBF.jl")

struct BBox
    bottom_lat::Float64
    left_lon::Float64
    top_lat::Float64
    right_lon::Float64
end

struct LatLon
    lat::Float64
    lon::Float64
end

struct Node
    latlon::LatLon
    tags::Union{Dict{String,String},Nothing}
end

struct Way
    refs::Vector{Int64}
    tags::Union{Dict{String,String},Nothing}
end

struct Relation
    refs::Vector{Int64}
    types::Vector{String}
    roles::Vector{String}
    tags::Union{Dict{String,String},Nothing}
end

struct Map
    nodes::Dict{Int64,Node}
    ways::Dict{Int64,Way}
    relations::Dict{Int64,Relation}
    meta::Dict{String,Any}

    Map() = new(Dict(), Dict(), Dict(), Dict())
end
