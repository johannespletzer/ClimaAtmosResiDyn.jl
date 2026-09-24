using Test
import ClimaAtmos as CA
entries = [Dict{String, Any}("name" => "tropo", "region" => "tropics"),
           Dict{String, Any}("name" => "extra", "region" => "extratropics")]
@testset "water 2M and P3" for mp in ("2M", "2MP3"), transport in ("tracer", "increment")
    cfg = CA.AtmosConfig(Dict{String, Any}("microphysics_model" => mp, "implicit_microphysics" => false,
        "water_tracers" => entries, "water_tag_transport" => transport); job_id = "w2m_$(mp)_$transport")
    @test_throws r"supports `microphysics_model: 0M` and `1M` only" CA.AtmosTagging(cfg)
end
