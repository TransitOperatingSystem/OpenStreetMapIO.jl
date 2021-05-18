# Reading OpenStreetMap Data

A OpenStreetMap (OSM) data file reader for Julia.

OSM pbf-files are available from various sources, like e.g. [Geofabrik](https://download.geofabrik.de/)

**Example:**

```julia
using OpenStreetMapIO
readpbf(filename)
```