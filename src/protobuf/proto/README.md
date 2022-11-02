# OpenStreetMap ProtoBuffer fils in Julia

For generating julia code from the proto files,

1. Download `fileformat.proto` and `osmformat.proto` from [osmosis](https://github.com/openstreetmap/osmosis/tree/93065380e462b141e5c5733a092531bf43860526/osmosis-osm-binary/src/main/protobuf) and
2. Run the following within a Julia session:

```julia
using ProtoBuf
protojl(["fileformat.proto", "osmformat.proto"], ".", ".")
```
