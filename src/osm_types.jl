
include("protobuf/OSMPBF.jl")

struct BoundingBox
    bottom_lat::Float64
    left_lon::Float64
    top_lat::Float64
    right_lon::Float64
end

mutable struct FileInfo
    bbox::Union{BoundingBox, Missing}
    writenat::Union{DateTime, Missing}
    sequencenumber::Union{Int64, Missing}
    baseurl::Union{String, Missing}
    writingprogram::Union{String, Missing}

    FileInfo() = new(missing, missing, missing, missing, missing)
end

struct OpenStreetMapNodes
    id::Vector{Int}
    lat::Vector{Float64}
    lon::Vector{Float64}

    OpenStreetMapNodes() = new([], [], [])
end

struct OpenStreetMapData
    nodes::OpenStreetMapNodes
    ways::Dict{Int,Vector{Int}}
    relations::Dict{Int,Dict{Symbol,Any}}
    tags::Dict{Int,Dict{Symbol,String}}
    fileinfo::FileInfo

    OpenStreetMapData() = new(OpenStreetMapNodes(), Dict(), Dict(), Dict(), FileInfo())
end

