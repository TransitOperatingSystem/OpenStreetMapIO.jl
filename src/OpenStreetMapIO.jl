module OpenStreetMapIO

using ProtoBuf: readproto, PipeBuffer
using CodecZlib: ZlibDecompressorStream
using EzXML: nodename, StreamReader, READER_ELEMENT
using HTTP: request
using Dates: unix2datetime, DateTime

include("osm_types.jl")
include("io_pbf.jl")
include("io_xml.jl")

export readpbf, readosm, queryoverpass
export OpenStreetMapData, OpenStreetMapNodes, BoundingBox, LatLon

end
