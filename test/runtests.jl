using OpenStreetMapIO, Test

@testset "Testing `pbf` file" begin
    @time osmdata = OpenStreetMapIO.readpbf("data/map.pbf")

    @testset "Testing Node" begin
        node = osmdata.nodes[1675598406]

        @test typeof(node) === Node
        @test node.latlon === LatLon(54.2619665, 9.9854149)
        @test length(node.tags) === 5
        @test node.tags[Symbol("addr:country")] === "DE"
    end

     @testset "Testing Way" begin
        way = osmdata.ways[889648159]

        @test typeof(way) === Way
        @test length(way.refs) === 56
        @test way.refs[23] === 1276389426
        @test length(way.tags) === 2
        @test way.tags[Symbol("wetland")] === "wet_meadow"
    end

    @testset "Testing Relation" begin
        relation = osmdata.relations[12475101]

        @test typeof(relation) === Relation
        @test length(relation.refs) === 136
        @test relation.refs[23] === 324374700
        @test length(relation.types) === 136
        @test relation.types[23] === :node
        @test length(relation.roles) === 136
        @test relation.roles[23] === "platform"
        @test length(relation.tags) === 8
        @test relation.tags[Symbol("from")] === "Bordesholm Bahnhof"
    end

end

@testset "Testing `osm` file" begin
    @time osmdata = OpenStreetMapIO.readosm("data/map.osm")

    @testset "Testing Node" begin
        node = osmdata.nodes[1675598406]

        @test typeof(node) === Node
        @test node.latlon === LatLon(54.2619665, 9.9854149)
        @test length(node.tags) === 5
        @test node.tags[Symbol("addr:country")] === "DE"
    end

    @testset "Testing Way" begin
        way = osmdata.ways[889648159]

        @test typeof(way) === Way
        @test length(way.refs) === 56
        @test way.refs[23] === 1276389426
        @test length(way.tags) === 2
        @test way.tags[Symbol(:wetland)] === "wet_meadow"
    end

    @testset "Testing Relation" begin
        relation = osmdata.relations[12475101]

        @test typeof(relation) === Relation
        @test length(relation.refs) === 136
        @test relation.refs[23] === 324374700
        @test length(relation.types) === 136
        @test relation.types[23] === :node
        @test length(relation.roles) === 136
        @test relation.roles[23] === "platform"
        @test length(relation.tags) === 8
        @test relation.tags[Symbol("from")] === "Bordesholm Bahnhof"
    end
end


