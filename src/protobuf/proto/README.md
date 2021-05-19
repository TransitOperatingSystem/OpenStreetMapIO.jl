# OpenStreetMap ProtoBuffer fils in JUlia

For updating the julia code generated from the proto files,

1. Download `fileformat.proto` and `osmformat.proto` from [osmosis](https://github.com/openstreetmap/osmosis/tree/93065380e462b141e5c5733a092531bf43860526/osmosis-osm-binary/src/main/protobuf)
2. Run the following within a Julia session:

```julia
using ProtoBuf
ProtoBuf.protoc(`--julia_out=. fileformat.proto osmformat.proto`)
```
