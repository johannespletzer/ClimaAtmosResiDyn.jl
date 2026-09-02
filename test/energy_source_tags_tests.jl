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

    for FT in (Float32, Float64)
        @testset "Donor fraction is guarded ($FT)" begin
            # Ordinary case: the clamped share
            @test CA.energy_source_fraction(FT(1), FT(4)) == FT(0.25)
            # Clamped from both ends, so transport drift cannot make the rule
            # remove more than is there or add energy back
            @test CA.energy_source_fraction(FT(-1), FT(4)) == FT(0)
            @test CA.energy_source_fraction(FT(9), FT(4)) == FT(1)
            # ρe_tot has no physical zero, so a non-positive parent is possible
            # and must not produce Inf or NaN
            @test CA.energy_source_fraction(FT(1), FT(0)) == FT(0)
            @test CA.energy_source_fraction(FT(1), FT(-4)) == FT(0)
            @test isfinite(CA.energy_source_fraction(FT(1), FT(0)))
        end

        @testset "Attribution is rate-bounded, not sign-bounded ($FT)" begin
            region = CA.TanhLatitudeRegion(FT(20), FT(2), true)
            tropics = CA.EnergySourceTag{:tropics}(region)
            rad = CA.EnergySourceTag{:rad}(nothing, :radiation)
            tags = (tropics, rad)

            ᶜYₜ = (; ρe_src_tropics = zeros(FT, 4), ρe_src_rad = zeros(FT, 4))
            ᶜY = (;
                ρe_src_tropics = FT[100, 100, 100, 100],
                ρe_src_rad = FT[0, 50, 100, 200],
                ρe_tot = FT[400, 400, 400, 400],
            )
            ᶜmasks = (; ρe_src_tropics = FT[0, 0.25, 0.5, 1])

            # Pure production: mask-weighted, and a tag that does not list the
            # process gets none of it
            ᶜΔ = FT[8, 8, 8, 8]
            CA._accumulate_energy_source_tags!(
                ᶜYₜ, ᶜY, ᶜmasks, ᶜΔ, :radiation, tags,
            )
            @test ᶜYₜ.ρe_src_tropics == ᶜmasks.ρe_src_tropics .* ᶜΔ
            @test ᶜYₜ.ρe_src_rad == ᶜΔ  # region-less, lists radiation

            # Pure loss: donor-proportional, and it reaches *every* tag
            # regardless of what it lists. This is the half that differs from
            # the ρe_tag_* rule.
            fill!(ᶜYₜ.ρe_src_tropics, FT(0))
            fill!(ᶜYₜ.ρe_src_rad, FT(0))
            ᶜΔloss = FT[-8, -8, -8, -8]
            CA._accumulate_energy_source_tags!(
                ᶜYₜ, ᶜY, ᶜmasks, ᶜΔloss, :held_suarez, tags,
            )
            φ_tropics =
                CA.energy_source_fraction.(ᶜY.ρe_src_tropics, ᶜY.ρe_tot)
            φ_rad = CA.energy_source_fraction.(ᶜY.ρe_src_rad, ᶜY.ρe_tot)
            @test ᶜYₜ.ρe_src_tropics ≈ ᶜΔloss .* φ_tropics
            @test ᶜYₜ.ρe_src_rad ≈ ᶜΔloss .* φ_rad

            # What the rule bounds is the depletion *rate*, not the amount
            # removed. `ᶜYₜ` is a tendency, so a step of length `dt` takes
            # `dt * φ * Δ⁻` out of the tag and the result depends on `dt`.
            # Adding `ᶜYₜ` to `ᶜY` directly would be Euler with `dt = 1`, which
            # is what made this look like a non-negativity guarantee. Written
            # as a sum rather than a comparison against a negated field,
            # because `.-ᶜ` parses as a suffixed operator Julia leaves
            # undefined.
            after_step(dt) = ᶜY.ρe_src_rad .+ dt .* ᶜYₜ.ρe_src_rad

            # A step short against the local depletion timescale keeps every
            # tag positive.
            @test all(after_step(FT(1)) .>= 0)

            # A long enough one does not, and no clamp on φ prevents it: the
            # clamp acts on the share while `dt` sets the amount. The cell
            # holding 200 against a parent of 400 has φ = 0.5 and Δ⁻ = -8, so
            # it crosses zero once `dt` passes 50. This is the documented
            # limit, asserted rather than assumed away.
            @test φ_rad[4] == FT(0.5)
            @test ᶜYₜ.ρe_src_rad[4] == FT(-4)
            @test after_step(FT(100))[4] < 0

            # A non-positive parent falls back to zero rather than Inf/NaN
            fill!(ᶜYₜ.ρe_src_rad, FT(0))
            ᶜYzero = (;
                ρe_src_tropics = ᶜY.ρe_src_tropics,
                ρe_src_rad = ᶜY.ρe_src_rad,
                ρe_tot = zeros(FT, 4),
            )
            CA._accumulate_energy_source_tags!(
                ᶜYₜ, ᶜYzero, ᶜmasks, ᶜΔloss, :held_suarez, (rad,),
            )
            @test all(iszero, ᶜYₜ.ρe_src_rad)
        end

        @testset "Donor loss depletes a positive parent ($FT)" begin
            # The controlled counterpart to `energy_source_tags_integration.jl`.
            # That file cannot make this claim: `ρe_tot` is non-positive over
            # the whole of its column, so `energy_source_fraction` returns zero
            # and the loss half of the rule never runs. Under the default
            # energy reference no column geometry fixes that — the 30 km
            # version is still 43% non-positive — so the parent is made
            # positive here by construction instead, and the assertion that it
            # is positive comes first.
            strat = CA.EnergySourceTag{:strat}(
                CA.TanhAltitudeRegion(FT(750), FT(100)),
            )
            tropo = CA.EnergySourceTag{:tropo}(
                CA.TanhAltitudeRegion(FT(750), FT(100), false),
            )
            tags = (strat, tropo)

            # Two tags partitioning the parent exactly, holding unequal
            # shares so proportionality is visible rather than degenerate.
            ᶜY = (;
                ρe_src_strat = FT[100, 200, 300],
                ρe_src_tropo = FT[300, 200, 100],
                ρe_tot = FT[400, 400, 400],
            )
            @test all(>(0), ᶜY.ρe_tot)
            @test ᶜY.ρe_src_strat .+ ᶜY.ρe_src_tropo == ᶜY.ρe_tot

            # Both tags carry a region, and `_accumulate_energy_source_tag!`
            # looks the mask up unconditionally, so both need one even though
            # a pure loss increment never uses it.
            ᶜmasks = (;
                ρe_src_strat = FT[0, 0.5, 1],
                ρe_src_tropo = FT[1, 0.5, 0],
            )
            ᶜYₜ = (;
                ρe_src_strat = zeros(FT, 3),
                ρe_src_tropo = zeros(FT, 3),
            )
            ᶜΔloss = FT[-40, -40, -40]
            CA._accumulate_energy_source_tags!(
                ᶜYₜ, ᶜY, ᶜmasks, ᶜΔloss, :held_suarez, tags,
            )

            # Every tag is depleted, and by its own share of the parent.
            @test all(<(0), ᶜYₜ.ρe_src_strat)
            @test all(<(0), ᶜYₜ.ρe_src_tropo)
            @test ᶜYₜ.ρe_src_strat ≈ ᶜΔloss .* (ᶜY.ρe_src_strat ./ ᶜY.ρe_tot)
            @test ᶜYₜ.ρe_src_tropo ≈ ᶜΔloss .* (ᶜY.ρe_src_tropo ./ ᶜY.ρe_tot)

            # The tag holding more loses more, which is the whole content of
            # "donor-proportional" and the half a non-positive parent hides.
            @test ᶜYₜ.ρe_src_tropo[1] < ᶜYₜ.ρe_src_strat[1]
            @test ᶜYₜ.ρe_src_strat[3] < ᶜYₜ.ρe_src_tropo[3]

            # Closure per process: the tags partition the parent, so the loss
            # shared out among them sums to the increment exactly.
            @test ᶜYₜ.ρe_src_strat .+ ᶜYₜ.ρe_src_tropo ≈ ᶜΔloss

            # And with a positive parent the step is well posed, so a step
            # short against the depletion timescale leaves every tag positive.
            @test all(ᶜY.ρe_src_strat .+ ᶜYₜ.ρe_src_strat .> 0)
            @test all(ᶜY.ρe_src_tropo .+ ᶜYₜ.ρe_src_tropo .> 0)
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
