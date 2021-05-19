# Reading OpenStreetMap Data

A OpenStreetMap (OSM) data file reader for Julia.

**Example:**

```julia
using OpenStreetMapIO
readpbf(filename)
```

OSM data are available from various sources, like e.g. [Geofabrik](https://download.geofabrik.de/)

Explanation of the data-model for pbf and osm files are avaiebal at the OSM Wiki [OSM PBF](https://wiki.openstreetmap.org/wiki/PBF_Format) and [OSM XML](https://wiki.openstreetmap.org/wiki/OSM_XML)
