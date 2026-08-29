using Test
import ClimaAtmos as CA

@testset "Energy source tags" begin
    for FT in (Float32, Float64)
        @testset "State construction ($FT)" begin
            region = CA.TanhLatitudeRegion(FT(20), FT(2), true)
            complement = CA.TanhLatitudeRegion(FT(20), FT(2), false)
            tropics = CA.EnergySourceTag{:tropics}(region)
            extratropics = CA.EnergySourceTag{:extratropics}(complement)
            rad = CA.EnergySourceTag{:rad}(nothing, :radiation)
            model = CA.EnergySourceTaggingModel((tropics, extratropics, rad))

            @test CA.energy_source_tag_state_names(model) ==
                  (:ρe_src_tropics, :ρe_src_extratropics, :ρe_src_rad)
            # Only the pure region tags partition the parent, so only they are
            # summed by the closure residual
            @test CA.energy_source_region_tag_state_names(model) ==
                  (:ρe_src_tropics, :ρe_src_extratropics)

            # A region tag starts as its masked share, a source tag at zero
            ρe_tot = FT(250000)
            coord = (; lat = FT(0), z = FT(5000))
            vars = CA.energy_source_tagging_variables(
                ρe_tot,
                (; coordinates = coord),
                model,
            )
            @test keys(vars) ==
                  (:ρe_src_tropics, :ρe_src_extratropics, :ρe_src_rad)
            @test vars.ρe_src_rad == FT(0)
            # A region and its exact complement partition the parent at t = 0
            @test vars.ρe_src_tropics + vars.ρe_src_extratropics ≈ ρe_tot rtol =
                sqrt(eps(FT))
            @test vars.ρe_src_tropics > vars.ρe_src_extratropics # in the tropics

            # Disabled costs no state fields at all
            @test CA.energy_source_tagging_variables(
                ρe_tot,
                (; coordinates = coord),
                nothing,
            ) == (;)
        end
    end

    @testset "Name predicate" begin
        @test CA.is_energy_source_tag_name(:ρe_src_tropics)
        @test !CA.is_energy_source_tag_name(:ρe_tag_tropics)
        @test !CA.is_energy_source_tag_name(:ρq_tag_tropics)
        @test !CA.is_energy_source_tag_name(:ρe_tot)

        # Source tags must be exempt from the tracer limiters alongside the
        # other two families
        @test CA.is_tagged_tracer_name(:ρe_src_tropics)
        @test CA.is_tagged_tracer_name(:ρe_tag_strat)
        @test CA.is_tagged_tracer_name(:ρq_tag_evap)
        @test !CA.is_tagged_tracer_name(:ρq_tot)
    end

    @testset "Config parsing" begin
        entries = [
            Dict{String, Any}("name" => "tropics", "region" => "tropics"),
            Dict{String, Any}(
                "name" => "extratropics",
                "region" => "extratropics",
            ),
        ]
        tags = CA.energy_source_tracer_tuple(entries, Float64)
        @test length(tags) == 2
        @test tags[1] isa CA.EnergySourceTag
        @test CA.tag_name(tags[1]) == :tropics
        @test isempty(tags[1].sources)

        # The process labels are the energy set, so radiation is accepted here
        # even though it moves no water
        sourced = CA.energy_source_tracer_tuple(
            [Dict{String, Any}("name" => "rad", "source" => "radiation")],
            Float64,
        )
        @test CA.tag_name(sourced[1]) == :rad
        @test sourced[1].sources == (:radiation,)
        @test isnothing(sourced[1].region)
    end

    @testset "AtmosModel integration" begin
        model = CA.AtmosModel()
        @test isnothing(model.energy_source_tagging_model)
        @test isnothing(model.tagging.energy_source_tagging_model)

        tags = (CA.EnergySourceTag{:everywhere}(CA.EntireDomain()),)
        model = CA.AtmosModel(;
            energy_source_tagging_model = CA.EnergySourceTaggingModel(tags),
        )
        @test model.energy_source_tagging_model isa
              CA.EnergySourceTaggingModel
        @test CA.tag_name(model.energy_source_tagging_model.tags[1]) ==
              :everywhere
    end

    @testset "Diagnostics registration" begin
        @test isnothing(
            CA.Diagnostics.register_energy_source_tagging_diagnostics!(
                CA.AtmosModel(),
            ),
        )

        tags = (
            CA.EnergySourceTag{:tropics}(
                CA.TanhLatitudeRegion(20.0, 2.0, true),
            ),
            CA.EnergySourceTag{:extratropics}(
                CA.TanhLatitudeRegion(20.0, 2.0, false),
            ),
        )
        CA.Diagnostics.register_energy_source_tagging_diagnostics!(
            CA.AtmosModel(;
                energy_source_tagging_model = CA.EnergySourceTaggingModel(tags),
            ),
        )
        @test haskey(CA.Diagnostics.ALL_DIAGNOSTICS, "e_src_tropics")
        @test haskey(CA.Diagnostics.ALL_DIAGNOSTICS, "e_src_extratropics")
        @test haskey(CA.Diagnostics.ALL_DIAGNOSTICS, "e_src_res")
    end
end
