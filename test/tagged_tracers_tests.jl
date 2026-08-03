using Test
import ClimaAtmos as CA

@testset "Tagged tracers" begin
    for FT in (Float32, Float64)
        @testset "Smooth spatial masks ($FT)" begin
            strat = CA.TanhAltitudeRegion(FT(12000), FT(1000))
            tropics = CA.TanhLatitudeRegion(FT(20), FT(2), true)
            extratropics = CA.TanhLatitudeRegion(FT(20), FT(2), false)

            for lat in FT[-80, -20, 0, 20, 80], z in FT[0, 5000, 12000, 20000]
                coord = (; lat, z)
                m_strat = CA.region_mask(strat, coord)
                m_trop = CA.region_mask(tropics, coord)
                m_extra = CA.region_mask(extratropics, coord)

                # Masks are bounded, of the right type, and complements are exact
                for m in (m_strat, m_trop, m_extra)
                    @test m isa FT
                    @test FT(0) <= m <= FT(1)
                end
                @test m_trop + m_extra == FT(1)
                @test CA.region_mask(CA.EntireDomain(), coord) == FT(1)
            end

            # Transition midpoints and asymptotics
            @test CA.region_mask(strat, (; lat = FT(0), z = FT(12000))) ==
                  FT(0.5)
            @test CA.region_mask(strat, (; lat = FT(0), z = FT(0))) <
                  sqrt(eps(FT))
            @test CA.region_mask(strat, (; lat = FT(0), z = FT(40000))) >
                  1 - sqrt(eps(FT))
            @test CA.region_mask(tropics, (; lat = FT(0), z = FT(0))) >
                  1 - sqrt(eps(FT))
            @test CA.region_mask(tropics, (; lat = FT(80), z = FT(0))) <
                  sqrt(eps(FT))
        end

        @testset "State variable construction ($FT)" begin
            tags = (
                CA.TracerTag{:strat}(CA.TanhAltitudeRegion(FT(12000), FT(1000))),
                CA.TracerTag{:tropics}(CA.TanhLatitudeRegion(FT(20), FT(2), true)),
                CA.TracerTag{:extratropics}(
                    CA.TanhLatitudeRegion(FT(20), FT(2), false),
                ),
                CA.TracerTag{:rad}(nothing, :radiation),
            )
            model = CA.TaggingModel(tags)
            ρe_tot = FT(250000)
            local_geometry = (; coordinates = (; lat = FT(10), z = FT(3000)))

            # Disabled tagging adds no fields
            @test CA.tagging_variables(ρe_tot, local_geometry, nothing) == (;)

            nt = CA.tagging_variables(ρe_tot, local_geometry, model)
            @test propertynames(nt) == (
                :ρe_tag_strat,
                :ρe_tag_tropics,
                :ρe_tag_extratropics,
                :ρe_tag_rad,
            )
            @test all(v -> v isa FT, values(nt))
            # Source-only tags start at zero
            @test nt.ρe_tag_rad == FT(0)
            # Complementary region tags partition the initial energy to
            # machine precision (the two products round independently)
            @test nt.ρe_tag_tropics + nt.ρe_tag_extratropics ≈ ρe_tot rtol =
                4 * eps(FT)
            # Names are ρ-weighted, so the generic tracer machinery picks them up
            @test all(
                CA.is_tracer_var, (:ρe_tag_strat, :ρe_tag_tropics, :ρe_tag_rad),
            )
        end

        @testset "Config parsing ($FT)" begin
            entries = [
                Dict{String, Any}(
                    "name" => "strat",
                    "region" => Dict{String, Any}(
                        "type" => "tanh_altitude",
                        "z_center" => 12000.0,
                        "width" => 1000.0,
                    ),
                ),
                Dict{String, Any}(
                    "name" => "tropics",
                    "region" => Dict{String, Any}(
                        "type" => "tanh_latitude",
                        "lat_bound" => 20.0,
                        "width" => 2.0,
                    ),
                ),
                Dict{String, Any}(
                    "name" => "extratropics",
                    "region" => Dict{String, Any}(
                        "type" => "tanh_latitude",
                        "lat_bound" => 20.0,
                        "width" => 2.0,
                        "inside" => false,
                    ),
                ),
                Dict{String, Any}("name" => "rad", "source" => "radiation"),
            ]
            tags = CA.tagged_tracer_tuple(entries, FT)
            @test tags isa Tuple
            @test length(tags) == 4
            @test map(CA.tag_name, tags) ==
                  (:strat, :tropics, :extratropics, :rad)
            @test tags[1].region isa CA.TanhAltitudeRegion{FT}
            @test tags[2].region.inside && !tags[3].region.inside
            @test isnothing(tags[4].region) && tags[4].source == :radiation

            # Validation errors
            @test_throws ErrorException CA.tagged_tracer_tuple(
                [Dict{String, Any}("region" => Dict("type" => "everywhere"))],
                FT,
            ) # missing name
            @test_throws ErrorException CA.tagged_tracer_tuple(
                [Dict{String, Any}("name" => "a")],
                FT,
            ) # neither region nor source
            @test_throws ErrorException CA.tagged_tracer_tuple(
                [
                    Dict{String, Any}("name" => "a", "source" => "radiation"),
                    Dict{String, Any}("name" => "a", "source" => "latent"),
                ],
                FT,
            ) # duplicate names
            @test_throws ErrorException CA.tag_region_from_config(
                Dict{String, Any}("type" => "step_function"),
                FT,
            ) # unknown region type
        end
    end

    @testset "AtmosModel integration" begin
        # Disabled by default
        model = CA.AtmosModel()
        @test isnothing(model.tagging_model)
        @test isnothing(model.tagging.tagging_model)

        # Enabled via the grouped kwarg interface
        tags = (CA.TracerTag{:rad}(nothing, :radiation),)
        model = CA.AtmosModel(; tagging_model = CA.TaggingModel(tags))
        @test model.tagging_model isa CA.TaggingModel
        @test CA.tag_name(model.tagging_model.tags[1]) == :rad
    end
end
