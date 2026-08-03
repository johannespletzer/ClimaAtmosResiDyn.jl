using Test
import ClimaAtmos as CA

@testset "Tagged tracers" begin
    for FT in (Float32, Float64)
        @testset "Smooth spatial masks ($FT)" begin
            strat = CA.TanhAltitudeRegion(FT(12000), FT(1000))
            tropics = CA.TanhLatitudeRegion(FT(20), FT(2), true)
            extratropics = CA.TanhLatitudeRegion(FT(20), FT(2), false)

            troposphere = CA.TanhAltitudeRegion(FT(12000), FT(1000), false)

            for lat in FT[-80, -20, 0, 20, 80], z in FT[0, 5000, 12000, 20000]
                coord = (; lat, z)
                m_strat = CA.region_mask(strat, coord)
                m_tropo = CA.region_mask(troposphere, coord)
                m_trop = CA.region_mask(tropics, coord)
                m_extra = CA.region_mask(extratropics, coord)

                # Masks are bounded, of the right type, and complements are exact
                for m in (m_strat, m_tropo, m_trop, m_extra)
                    @test m isa FT
                    @test FT(0) <= m <= FT(1)
                end
                @test m_trop + m_extra == FT(1)
                @test m_strat + m_tropo == FT(1)
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
            # Region-restricted source tags ALSO start at zero: the region
            # only restricts where the source is counted (a nonzero start
            # would break `Σ restricted source tags == global source tag`)
            combined = CA.TracerTag{:rad_trop}(
                CA.TanhLatitudeRegion(FT(20), FT(2), true),
                :radiation,
            )
            @test CA.tag_initial_value(combined, ρe_tot, (; lat = FT(0), z = FT(0))) ==
                  FT(0)
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
            @test tags[1].region.above # default
            @test tags[2].region.inside && !tags[3].region.inside
            @test isnothing(tags[4].region) && tags[4].source == :radiation

            # Altitude complement via `above: false`
            tropo_tag = CA.tagged_tracer_tuple(
                [
                    Dict{String, Any}(
                        "name" => "tropo",
                        "region" => Dict{String, Any}(
                            "type" => "tanh_altitude",
                            "z_center" => 12000.0,
                            "width" => 1000.0,
                            "above" => false,
                        ),
                    ),
                ],
                FT,
            )[1]
            @test !tropo_tag.region.above

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
                    Dict{String, Any}("name" => "a", "source" => "surface_flux"),
                ],
                FT,
            ) # duplicate names
            @test_throws ErrorException CA.tagged_tracer_tuple(
                [Dict{String, Any}("name" => "a", "source" => "latent_heat")],
                FT,
            ) # unknown source label
            @test_throws ErrorException CA.tag_region_from_config(
                Dict{String, Any}("type" => "step_function"),
                FT,
            ) # unknown region type
        end

        @testset "Source attribution ($FT)" begin
            region = CA.TanhAltitudeRegion(FT(12000), FT(1000))
            region_tag = CA.TracerTag{:strat}(region)
            source_tag = CA.TracerTag{:rad}(nothing, :radiation)
            both_tag = CA.TracerTag{:strat_rad}(region, :radiation)

            # Region tags receive every attributed source; source tags only
            # their own
            @test CA.tag_receives_source(region_tag, :radiation)
            @test CA.tag_receives_source(region_tag, :surface_flux)
            @test CA.tag_receives_source(source_tag, :radiation)
            @test !CA.tag_receives_source(source_tag, :surface_flux)
            @test CA.tag_receives_source(both_tag, :radiation)
            @test !CA.tag_receives_source(both_tag, :microphysics)

            # Accumulation: region tags are mask-weighted, source tags are
            # not; non-matching sources leave a tag untouched
            tags = (region_tag, source_tag, both_tag)
            ᶜYₜ = (;
                ρe_tag_strat = zeros(FT, 4),
                ρe_tag_rad = zeros(FT, 4),
                ρe_tag_strat_rad = zeros(FT, 4),
            )
            ᶜmasks = (;
                ρe_tag_strat = FT[0, 0.25, 0.5, 1],
                ρe_tag_strat_rad = FT[0, 0.25, 0.5, 1],
            )
            ᶜΔ = FT[1, 2, 3, 4]
            CA._accumulate_tags!(ᶜYₜ, ᶜmasks, ᶜΔ, :radiation, tags)
            @test ᶜYₜ.ρe_tag_strat == ᶜmasks.ρe_tag_strat .* ᶜΔ
            @test ᶜYₜ.ρe_tag_rad == ᶜΔ
            @test ᶜYₜ.ρe_tag_strat_rad == ᶜmasks.ρe_tag_strat_rad .* ᶜΔ
            CA._accumulate_tags!(ᶜYₜ, ᶜmasks, ᶜΔ, :surface_flux, tags)
            @test ᶜYₜ.ρe_tag_strat == 2 .* ᶜmasks.ρe_tag_strat .* ᶜΔ
            @test ᶜYₜ.ρe_tag_rad == ᶜΔ # not its source; unchanged
            @test ᶜYₜ.ρe_tag_strat_rad == ᶜmasks.ρe_tag_strat_rad .* ᶜΔ
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

    @testset "Diagnostics registration" begin
        tags = (
            CA.TracerTag{:strat}(CA.TanhAltitudeRegion(12000.0, 1000.0)),
            CA.TracerTag{:src}(nothing, :radiation),
        )
        # No-op when disabled
        @test isnothing(CA.Diagnostics.register_tagging_diagnostics!(nothing))

        CA.Diagnostics.register_tagging_diagnostics!(CA.TaggingModel(tags))
        e_strat = CA.Diagnostics.get_diagnostic_variable("e_tag_strat")
        e_src = CA.Diagnostics.get_diagnostic_variable("e_tag_src")
        e_res = CA.Diagnostics.get_diagnostic_variable("e_tag_res")
        @test e_strat.units == "J kg^-1"

        # Compute functions divide by density; the residual sums only the
        # region tags (the source tag would double-count region content)
        state = (;
            c = (;
                ρ = [2.0, 2.0],
                ρe_tot = [10.0, 6.0],
                ρe_tag_strat = [4.0, 2.0],
                ρe_tag_src = [1.0, 1.0],
            )
        )
        @test e_strat.compute!(nothing, state, nothing, 0.0) == [2.0, 1.0]
        @test e_src.compute!(nothing, state, nothing, 0.0) == [0.5, 0.5]
        @test e_res.compute!(nothing, state, nothing, 0.0) == [3.0, 2.0]

        # Mutating form writes into `out`
        out = zeros(2)
        e_res.compute!(out, state, nothing, 0.0)
        @test out == [3.0, 2.0]

        # Registration is idempotent for per-tag entries (no overwrite)
        CA.Diagnostics.register_tagging_diagnostics!(CA.TaggingModel(tags))
        @test CA.Diagnostics.get_diagnostic_variable("e_tag_strat") === e_strat
    end

    @testset "Tagged name predicate" begin
        @test CA.is_tagged_tracer_name(:ρe_tag_strat)
        @test !CA.is_tagged_tracer_name(:ρq_tot)
        @test !CA.is_tagged_tracer_name(:ρe_tot)
        # Tags are exempt from nonnegativity limiting even when the species
        # filter would apply the limiter to all tracers
        @test !CA._should_apply_limiter_to_tracer(:ρe_tag_strat, nothing)
        @test CA._should_apply_limiter_to_tracer(:ρq_tot, nothing)
    end
end
