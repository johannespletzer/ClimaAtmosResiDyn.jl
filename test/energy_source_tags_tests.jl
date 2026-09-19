using Test
import ClimaAtmos as CA
import ClimaComms
import ClimaCore
import ClimaCore:
    Domains, Fields, Geometry, Grids, Hypsography, Meshes, Operators,
    Quadratures, Spaces, Topologies
import ClimaDiagnostics
import Dates

# `AtmosModel` takes a grid. These tests read only the model's tagging fields,
# so the smallest column serves.
column_atmos_model(; kwargs...) =
    CA.AtmosModel(CA.ColumnGrid(Float64; z_elem = 10); kwargs...)

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
            # The controlled counterpart to `energy_source_tags_integration.jl`,
            # which cannot make this claim: `ρe_tot` is non-positive across its
            # column, so `energy_source_fraction` returns zero and the loss half
            # of the rule never runs. No column geometry fixes that under the
            # default energy reference, so the parent is positive here by
            # construction and that is asserted first.
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

        @testset "An offset total the model never uses ($FT)" begin
            strat = CA.EnergySourceTag{:strat}(
                CA.TanhAltitudeRegion(FT(750), FT(100)),
            )
            tropo = CA.EnergySourceTag{:tropo}(
                CA.TanhAltitudeRegion(FT(750), FT(100), false),
            )
            sfc = CA.EnergySourceTag{:sfc}(nothing, :surface_flux)
            tags = (strat, tropo, sfc)
            c = FT(110495)
            model = CA.EnergySourceTaggingModel(tags, c)
            plain = CA.EnergySourceTaggingModel(tags)

            # Without an offset the total is ρe_tot itself, bit for bit, so a
            # run that does not set the key is unchanged.
            @test isnothing(plain.offset)
            @test CA.energy_source_parent(FT(-5e4), FT(1.2), plain) === FT(-5e4)
            @test CA.energy_source_parent(FT(-5e4), FT(1.2), nothing) ===
                  FT(-5e4)
            @test CA.energy_source_closure_total(plain) === :ρe_tot
            @test CA.energy_source_closure_total(nothing) === :ρe_tot

            # With one it is ρe_tot + c·ρ, positive where ρe_tot is not.
            E_point = CA.energy_source_parent(FT(-5e4), FT(1.2), model)
            @test E_point == FT(-5e4) + c * FT(1.2)
            @test E_point > 0

            # The region tags partition the offset total at t = 0.
            vars = CA.energy_source_tagging_variables(
                E_point,
                (; coordinates = (; z = FT(500))),
                model,
            )
            @test vars.ρe_src_strat + vars.ρe_src_tropo ≈ E_point rtol =
                sqrt(eps(FT))
            @test vars.ρe_src_sfc == FT(0)

            # A bracket that moves mass as well as energy, in three cells whose
            # ρe_tot is negative in two and whose offset total is positive in
            # all three.
            ρ = FT[1.2, 1.0, 0.8]
            ρe_tot = FT[-60000, -20000, 30000]
            E = ρe_tot .+ c .* ρ
            @test all(<(0), ρe_tot[1:2])
            @test all(>(0), E)
            masks = (;
                ρe_src_strat = FT[0, 0.5, 1],
                ρe_src_tropo = FT[1, 0.5, 0],
            )
            Y = (;
                c = (;
                    ρ,
                    ρe_tot,
                    ρe_src_strat = masks.ρe_src_strat .* E,
                    ρe_src_tropo = masks.ρe_src_tropo .* E,
                    ρe_src_sfc = FT[10, 0, 5],
                ),
            )
            # Tendencies accumulated before the bracket opens, which the
            # bracket has to difference away.
            Yₜ = (;
                c = (;
                    ρ = FT[1e-6, -2e-6, 3e-6],
                    ρe_tot = FT[4, 5, -6],
                    ρe_src_strat = zeros(FT, 3),
                    ρe_src_tropo = zeros(FT, 3),
                    ρe_src_sfc = zeros(FT, 3),
                ),
            )
            p = (;
                atmos = (; energy_source_tagging_model = model),
                tagging = (; ᶜenergy_source_masks = masks),
                # The bracket needs only the cell-center scratch. The face
                # fluxes need a face space, which this state has not.
                scratch = CA.energy_source_cell_scratch(Y.c.ρ, model.offset),
            )
            CA.snapshot_energy_source_tags!(p, Yₜ)
            # The bracketed process gains energy in the first cell and loses it
            # in the other two, and moves mass in all three, as a surface flux
            # with evaporation does.
            Δρe_tot = FT[30, -40, -50]
            Δρ = FT[2e-4, -1e-4, 3e-4]
            Yₜ.c.ρe_tot .+= Δρe_tot
            Yₜ.c.ρ .+= Δρ
            CA.attribute_energy_source_tags!(Yₜ, Y, p, :surface_flux)

            # The increment of the total carries the energy of the mass moved.
            ΔE = Δρe_tot .+ c .* Δρ
            @test ΔE[1] > 0
            @test all(<(0), ΔE[2:3])
            # The region tags account for the whole increment in every cell,
            # the two with a negative ρe_tot included.
            @test Yₜ.c.ρe_src_strat .+ Yₜ.c.ρe_src_tropo ≈ ΔE rtol =
                sqrt(eps(FT))
            # The source tag takes the production and its donor share of the
            # loss, measured against the offset total.
            @test Yₜ.c.ρe_src_sfc[1] ≈ ΔE[1] rtol = sqrt(eps(FT))
            @test Yₜ.c.ρe_src_sfc[3] ≈ ΔE[3] * FT(5) / E[3] rtol = sqrt(eps(FT))

            # Against ρe_tot alone, as without an offset, the same loss goes
            # unattributed where ρe_tot is negative. That is the barrier the
            # offset removes.
            unshifted_Yₜ = (;
                ρe_src_strat = zeros(FT, 3),
                ρe_src_tropo = zeros(FT, 3),
                ρe_src_sfc = zeros(FT, 3),
            )
            CA._accumulate_energy_source_tags!(
                unshifted_Yₜ, Y.c, masks, ΔE, :held_suarez, tags,
            )
            @test unshifted_Yₜ.ρe_src_strat[2] + unshifted_Yₜ.ρe_src_tropo[2] ==
                  FT(0)

            # The closure check reads the offset total from a scratch field.
            @test CA.closure_parent(Y, p, CA.energy_source_closure_total(model)) ≈
                  E
            @test CA.closure_parent(Y, p, :ρe_tot) === Y.c.ρe_tot
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

    @testset "Offset config parsing" begin
        # Unset and zero both leave the tags on ρe_tot exactly as before.
        @test isnothing(CA.energy_source_offset_from_config(nothing, Float64))
        @test isnothing(CA.energy_source_offset_from_config(0, Float64))
        @test CA.energy_source_offset_from_config(110495, Float32) ===
              Float32(110495)
        # A negative offset could only make the total less positive, and a
        # value that is not a finite number is a typo.
        @test_throws ErrorException CA.energy_source_offset_from_config(
            -1.0,
            Float64,
        )
        @test_throws ErrorException CA.energy_source_offset_from_config(
            Inf,
            Float64,
        )
        @test_throws ErrorException CA.energy_source_offset_from_config(
            "big",
            Float64,
        )
    end

    @testset "Repair kernels ($FT)" for FT in (Float32, Float64)
        # One negative tag in a partition whose sum is 10. The positive tags give
        # up the deficit in proportion to what each holds, so the sum is kept.
        pos, neg, parent = FT(12), FT(-2), FT(10)
        repaired =
            CA.energy_source_partition_repair.(FT[8, 4, -2], pos, neg, parent)
        @test all(≥(0), repaired)
        @test sum(repaired) ≈ pos + neg
        @test repaired[1] / repaired[2] ≈ 2
        # A cell with no negative tag is left exactly as it is.
        @test CA.energy_source_partition_repair(FT(3), FT(5), FT(0), FT(5)) ==
              FT(3)
        # Where the negatives outweigh the positives, every tag is zeroed.
        @test CA.energy_source_partition_repair(FT(1), FT(1), FT(-3), FT(1)) ==
              0
        # Where the total is not positive, a region tag carries its sign by
        # design, and the repair leaves it alone.
        @test CA.energy_source_partition_repair(FT(-4), FT(1), FT(-5), FT(-4)) ==
              FT(-4)
        # A tag that carries a source is clipped at zero where the total is
        # positive, and left alone where it is not.
        @test CA.energy_source_overlay_repair(FT(-1), FT(10)) == 0
        @test CA.energy_source_overlay_repair(FT(2), FT(10)) == FT(2)
        @test CA.energy_source_overlay_repair(FT(-1), FT(-10)) == FT(-1)
    end

    @testset "Repair switch" begin
        tags = (CA.EnergySourceTag{:everywhere}(CA.EntireDomain()),)
        @test CA.EnergySourceTaggingModel(tags).repair
        @test !CA.EnergySourceTaggingModel(tags, nothing; repair = false).repair
        @test CA.energy_source_repair_from_config(true)
        @test !CA.energy_source_repair_from_config(false)
        @test CA.energy_source_repair_from_config(nothing)
        # A quoted "false" is a string, and must not read as on.
        @test_throws ErrorException CA.energy_source_repair_from_config("false")
    end

    @testset "Sedimentation shares ($FT)" for FT in (Float32, Float64)
        # A partition that holds all of a total of 10. The shares are the
        # fractions themselves, and they add up to one.
        total = FT(10)
        tags = FT[6, 3, 1]
        norm = sum(CA.energy_source_fraction.(tags, total))
        shares = CA.energy_source_sediment_share.(tags, total, norm)
        @test shares ≈ FT[0.6, 0.3, 0.1]
        @test sum(shares) ≈ 1
        # One tag is negative. The clamp drops it, and dividing by the sum of
        # the shares hands its part of the flux to the others. So the shares
        # still add up to one, and the partition's fluxes to the parent's.
        tags = FT[6, 3, -1]
        norm = sum(CA.energy_source_fraction.(tags, total))
        shares = CA.energy_source_sediment_share.(tags, total, norm)
        @test shares ≈ FT[2 / 3, 1 / 3, 0]
        @test sum(shares) ≈ 1
        # Where no tag holds a positive share, nothing moves, and there is no
        # NaN.
        @test CA.energy_source_sediment_share(FT(1), FT(-5), FT(0)) == 0
        # A tag that carries a source keeps its plain, clamped share.
        @test CA.energy_source_source_sediment_share(FT(2), total) ≈ FT(0.2)
        @test CA.energy_source_source_sediment_share(FT(-2), total) == 0
        @test CA.energy_source_source_sediment_share(FT(20), total) == 1
    end

    @testset "Transport switch" begin
        tags = (CA.EnergySourceTag{:everywhere}(CA.EntireDomain()),)
        # Passive tracers by default, as before the switch existed.
        @test CA.EnergySourceTaggingModel(tags).transport isa
              CA.TracerEnergySourceTransport
        @test !CA.moves_as_enthalpy(CA.EnergySourceTaggingModel(tags))
        @test !CA.moves_as_enthalpy(nothing)
        audit = CA.EnergySourceTaggingModel(
            tags,
            50000.0;
            transport = CA.EnthalpyEnergySourceTransport(),
        )
        @test CA.moves_as_enthalpy(audit)
        # Without an offset a share is zero wherever the total is not positive,
        # and the tags would not move there, so the audit is refused.
        @test_throws ErrorException CA.EnergySourceTaggingModel(
            tags;
            transport = CA.EnthalpyEnergySourceTransport(),
        )
        @test CA.energy_source_transport_from_config(nothing) isa
              CA.TracerEnergySourceTransport
        @test CA.energy_source_transport_from_config("tracer") isa
              CA.TracerEnergySourceTransport
        @test CA.energy_source_transport_from_config("enthalpy") isa
              CA.EnthalpyEnergySourceTransport
        @test_throws ErrorException CA.energy_source_transport_from_config(
            "Enthalpy",
        )
        @test_throws ErrorException CA.energy_source_transport_from_config(true)
        @test CA.energy_source_transport_from_config("enthalpy_increment") isa
              CA.EnthalpyIncrementEnergySourceTransport
    end

    @testset "Updraft copy switch" begin
        region = CA.EnergySourceTag{:everywhere}(CA.EntireDomain())
        source = CA.EnergySourceTag{:sfc}(nothing, :surface_flux)
        tags = (region, source)
        # No copies by default.
        @test !CA.has_energy_source_updraft_copies(
            CA.EnergySourceTaggingModel(tags),
        )
        @test !CA.has_energy_source_updraft_copies(nothing)
        @test CA.energy_source_updraft_copy_names(nothing) == ()
        increment = CA.EnergySourceTaggingModel(
            tags,
            50000.0;
            transport = CA.EnthalpyIncrementEnergySourceTransport(),
            updraft_copies = true,
        )
        @test CA.has_energy_source_updraft_copies(increment)
        @test CA.energy_source_updraft_copy_names(increment) ==
              (:e_src_everywhere, :e_src_sfc)
        @test CA.has_energy_source_updraft_copies(
            CA.EnergySourceTaggingModel(tags; updraft_copies = true),
        )
        # Under `enthalpy` nothing corrects the copies' flux to the parent's.
        @test_throws r"does not work with" CA.EnergySourceTaggingModel(
            tags,
            50000.0;
            transport = CA.EnthalpyEnergySourceTransport(),
            updraft_copies = true,
        )
        @test CA.energy_source_updraft_copy_from_config(nothing) == false
        @test CA.energy_source_updraft_copy_from_config(false) == false
        @test CA.energy_source_updraft_copy_from_config(true) == true
        @test_throws ErrorException CA.energy_source_updraft_copy_from_config(
            "true",
        )
        @test isnothing(
            CA.check_energy_source_updraft_copy_supported("prognostic_edmfx"),
        )
        @test_throws r"needs `turbconv: prognostic_edmfx`" CA.check_energy_source_updraft_copy_supported(
            "edonly_edmfx",
        )
        @test_throws r"needs `turbconv: prognostic_edmfx`" CA.check_energy_source_updraft_copy_supported(
            nothing,
        )
        # Each copy starts as its tag's specific value.
        gs = (; ρ = 1.25, ρe_src_everywhere = 250.0, ρe_src_sfc = 0.0)
        @test CA.energy_source_updraft_copy_variables(gs, increment) ==
              (; e_src_everywhere = 200.0, e_src_sfc = 0.0)
        @test CA.energy_source_updraft_copy_variables(
            gs,
            CA.EnergySourceTaggingModel(tags),
        ) == (;)
        @test CA.Setups.with_updraft_tracers((; ρtke = 1.0), (; e_src_sfc = 0.0)) ==
              (; ρtke = 1.0)
        sgs = (; ρtke = 1.0, sgsʲs = ((; ρa = 0.1, mse = 3.0e5),))
        @test CA.Setups.with_updraft_tracers(sgs, (; e_src_sfc = 2.0)).sgsʲs ==
              ((; ρa = 0.1, mse = 3.0e5, e_src_sfc = 2.0),)
        @test CA.Setups.with_updraft_tracers(sgs, (;)) === sgs
    end

    @testset "The exchange's plume ($FT)" for FT in (Float32, Float64)
        # The partition's flags are a constant of the tags' types.
        tags = (
            CA.EnergySourceTag{:a}(CA.EntireDomain()),
            CA.EnergySourceTag{:b}(nothing, :surface_flux),
            CA.EnergySourceTag{:c}(CA.EntireDomain(), :radiation),
        )
        @test (@inferred CA._energy_partition_flags(tags)) ===
              Val((true, false, false))
        # The partition's shares add up to one, and are zero where it holds
        # nothing. A source tag's share is its fraction of the partition's sum.
        partition = Val((true, true, false))
        ε = FT.((3, 1, 2))
        @test CA._share_of(ε, 1, partition) + CA._share_of(ε, 2, partition) ≈ 1
        @test CA._share_of(ε, 3, partition) ≈ FT(0.5)
        @test CA._share_of(FT.((1, 1, 5)), 3, partition) == 1
        @test CA._share_of(FT.((0, 0, 1)), 3, partition) == 0
        @test CA._nonnegative_specific(FT(2), FT(4), FT(-1), FT(6)) ==
              FT.((2, 0, 3))
        # Without a rising updraft the plume starts again from the grid mean.
        ε̄ = FT.((10, 30))
        level = CA._plume_level(ε̄, FT(1), FT(0.1), FT(0.9), FT(1e-3), FT(-1), FT(50))
        @test level[3]
        @test CA._plume_step(FT.((1, 2)), level) == ε̄
        # The lowest level takes the grid mean's composition.
        rising = CA._plume_level(ε̄, FT(1), FT(0.1), FT(0.9), FT(1e-3), FT(1), FT(50))
        @test !rising[3]
        @test CA._plume_step((FT(NaN), FT(NaN)), rising) == ε̄
        # Above, the updraft relaxes toward the environment at the weight `a`,
        # the steady updraft equation taken implicitly in `z`.
        a = FT(1e-3) * FT(50) / FT(1) * FT(1) / FT(0.9)
        @test rising[2] ≈ a
        εʲ = CA._plume_step(FT.((40, 0)), rising)
        @test collect(εʲ) ≈ [(40 + a * 10) / (1 + a), (0 + a * 30) / (1 + a)]
        # Its environment keeps the grid mean's total: ρ ε̄ = ρaʲ εʲ + ρa⁰ ε⁰.
        ε⁰ = CA._environment_specific(ε̄, εʲ, FT(1), FT(0.1), FT(0.9))
        @test collect(FT(0.1) .* εʲ .+ FT(0.9) .* ε⁰) ≈ collect(ε̄)
        # The van Leer limiter is not linear, so the exchange does not use it.
        @test CA._exchange_upwinding(Val(:vanleer_limiter)) == Val(:first_order)
        @test CA._exchange_upwinding(Val(:none)) == Val(:none)
    end

    # The increment mode takes the parent's increment after each Newton solve,
    # so it refuses a stepper that applies an implicit tendency without one.
    @testset "The increment mode refuses steppers it cannot follow" begin
        CTS = CA.CTS
        tags = (
            CA.EnergySourceTag{:strat}(CA.TanhAltitudeRegion(750.0, 100.0)),
            CA.EnergySourceTag{:tropo}(
                CA.TanhAltitudeRegion(750.0, 100.0, false),
            ),
        )
        atmos(transport) = (;
            energy_source_tagging_model = CA.EnergySourceTaggingModel(
                tags,
                50000.0;
                transport,
            )
        )
        increment = atmos(CA.EnthalpyIncrementEnergySourceTransport())
        newton = CTS.NewtonsMethod()
        T_imp! = (Yₜ, Y, p, t) -> nothing
        # The parent's own post-solve correction, which it has unless
        # `energy_q_tot_upwinding` is `none`.
        post = (dY, U, p, t) -> nothing
        check = CA.check_energy_source_increment_supported
        imex(tableau) = CTS.IMEXAlgorithm(tableau, newton)
        # Every stage the algorithm uses is solved: the ARS algorithms, and
        # SSP222, whose implicit diagonal has no zero.
        for tableau in (CTS.ARS343(), CTS.ARS222(), CTS.SSP222())
            @test isnothing(check(increment, imex(tableau), T_imp!, post))
        end
        @test_throws r"implicit tendency without a solve" check(
            increment,
            imex(CTS.SSP333()),
            T_imp!,
            post,
        )
        @test_throws r"flow is prescribed" check(
            increment,
            imex(CTS.ARS343()),
            nothing,
            nothing,
        )
        @test_throws r"not an IMEX algorithm with a Newton method" check(
            increment,
            CTS.ExplicitAlgorithm(CTS.SSP33ShuOsher()),
            T_imp!,
            post,
        )
        # Without the parent's own post-solve correction, a hook would make
        # the stepper refresh the cache the model's constraints read.
        @test_throws r"energy_q_tot_upwinding: none" check(
            increment,
            imex(CTS.ARS343()),
            T_imp!,
            nothing,
        )
        # Every other transport is left alone.
        @test isnothing(
            check(
                atmos(CA.EnthalpyEnergySourceTransport()),
                imex(CTS.SSP333()),
                T_imp!,
                nothing,
            ),
        )

        # The ledger exists in this mode only, and its names are not a
        # tracer's, so no transport reaches it.
        ledger = CA.energy_source_increment_ledger_variables(
            1.0,
            increment.energy_source_tagging_model,
        )
        @test keys(ledger) == (:e_src_inc_left, :e_src_inc_moved)
        @test all(iszero, values(ledger))
        @test CA.energy_source_increment_ledger_names(
            increment.energy_source_tagging_model,
        ) == keys(ledger)
        enthalpy = atmos(CA.EnthalpyEnergySourceTransport())
        @test CA.energy_source_increment_ledger_variables(
            1.0,
            enthalpy.energy_source_tagging_model,
        ) == (;)
        @test CA.energy_source_increment_ledger_names(
            enthalpy.energy_source_tagging_model,
        ) == ()
        for name in keys(ledger)
            @test CA.is_energy_source_ledger_name(name)
            @test !CA.is_energy_source_tag_name(name)
            @test !startswith(string(name), "ρ")
            @test !CA.is_tracer_var(name)
        end

        # A restart checks the ledger's fields, through the checkpoint's own
        # check, in both directions. Both stop before the file is opened.
        restart_model(source) = (;
            energy_source_tagging_model = source,
            energy_process_record = nothing,
            water_process_record = nothing,
        )
        state(names...) = (;
            c = NamedTuple{(:ρ, :ρe_src_strat, :ρe_src_tropo, names...)}(
                zeros(3 + length(names)),
            )
        )
        @test_throws r"Missing from the file: e_src_inc_left, e_src_inc_moved" CA.check_energy_source_checkpoint(
            "restart.hdf5",
            restart_model(increment.energy_source_tagging_model),
            state(),
            nothing,
        )
        @test_throws r"Not configured: e_src_inc_left, e_src_inc_moved" CA.check_energy_source_checkpoint(
            "restart.hdf5",
            restart_model(enthalpy.energy_source_tagging_model),
            state(keys(ledger)...),
            nothing,
        )

        # The mode needs region tags that partition the domain: at least one,
        # checked when the model is built, and masks that sum to 1, checked
        # when the cache is built.
        @test_throws r"needs region tags without sources" CA.EnergySourceTaggingModel(
            (CA.EnergySourceTag{:sfc}(nothing, :surface_flux),),
            50000.0;
            transport = CA.EnthalpyIncrementEnergySourceTransport(),
        )
        masks(a, b) = (; ρe_src_strat = fill(a, 3), ρe_src_tropo = fill(b, 3))
        partition = (:ρe_src_strat, :ρe_src_tropo)
        @test isnothing(
            CA._check_increment_partition(
                masks(0.25, 0.75),
                partition,
                increment.energy_source_tagging_model,
            ),
        )
        @test_throws r"partition the domain" CA._check_increment_partition(
            masks(0.25, 0.5),
            partition,
            increment.energy_source_tagging_model,
        )
        @test isnothing(
            CA._check_increment_partition(
                masks(0.25, 0.5),
                partition,
                enthalpy.energy_source_tagging_model,
            ),
        )
        # And the model refuses the mode without an offset.
        @test_throws r"enthalpy_increment` needs `energy_source_tag_offset`" CA.EnergySourceTaggingModel(
            tags;
            transport = CA.EnthalpyIncrementEnergySourceTransport(),
        )
    end

    @testset "The increment's flux under a deep atmosphere" begin
        # On a deep sphere the faces grow with height. The correction's column
        # integrals are per unit area of the bottom face, and the divergence
        # weights each face by its own area. So the flux is scaled by the
        # bottom face's area over each face's own, and then each cell takes
        # exactly its part of the mismatch. On ClimaCore's grids alone, deep
        # and shallow, with and without a mountain.
        FT = Float64
        radius = FT(6.371e6)
        function sphere_spaces(deep, mountain)
            context = ClimaComms.SingletonCommsContext()
            horizontal = Spaces.SpectralElementSpace2D(
                Topologies.Topology2D(
                    context,
                    Meshes.EquiangularCubedSphere(Domains.SphereDomain(radius), 2),
                ),
                Quadratures.GLL{3}(),
            )
            vertical = Grids.FiniteDifferenceGrid(
                Topologies.IntervalTopology(
                    context,
                    Meshes.IntervalMesh(
                        Domains.IntervalDomain(
                            Geometry.ZPoint(FT(0)),
                            Geometry.ZPoint(FT(30000));
                            boundary_names = (:bottom, :top),
                        );
                        nelems = 10,
                    ),
                ),
            )
            hypsography = if mountain
                coordinates = Fields.coordinate_field(horizontal)
                Hypsography.LinearAdaption(
                    @. Geometry.ZPoint(
                        FT(3000) * exp(
                            -((coordinates.lat - 30)^2 + (coordinates.long - 40)^2) /
                            400,
                        ),
                    )
                )
            else
                Grids.Flat()
            end
            grid = Grids.ExtrudedFiniteDifferenceGrid(
                Spaces.grid(horizontal),
                vertical,
                hypsography;
                deep,
            )
            return (
                Spaces.CenterExtrudedFiniteDifferenceSpace(grid),
                Spaces.FaceExtrudedFiniteDifferenceSpace(grid),
            )
        end
        half = ClimaCore.Utilities.half
        for deep in (true, false), mountain in (false, true)
            ᶜspace, ᶠspace = sphere_spaces(deep, mountain)
            ᶜz = Fields.coordinate_field(ᶜspace).z
            ᶠz = Fields.coordinate_field(ᶠspace).z
            ᶜm = @. FT(100) * (sin(2 * FT(π) * ᶜz / 30000) + FT(0.3))
            ᶜabs = abs.(ᶜm)
            ᶠI = Fields.Field(FT, ᶠspace)
            ᶠA = Fields.Field(FT, ᶠspace)
            Operators.column_integral_indefinite!(ᶠI, ᶜm)
            Operators.column_integral_indefinite!(ᶠA, ᶜabs)
            M = zeros(axes(Fields.level(ᶠI, half)))
            A = zeros(axes(Fields.level(ᶠI, half)))
            Operators.column_integral_definite!(M, ᶜm)
            Operators.column_integral_definite!(A, ᶜabs)
            ᶠratio = CA._energy_source_face_area_ratio(ᶠI)
            # The ratio is the square of the radii, and 1 when shallow.
            ᶠz_bottom = Fields.level(ᶠz, half)
            ᶠexpected = @. ifelse(deep, ((radius + ᶠz_bottom) / (radius + ᶠz))^2, FT(1))
            @test maximum(abs, parent(ᶠratio) .- parent(ᶠexpected)) < 100 * eps(FT)
            @test deep == (minimum(parent(ᶠratio)) < 1 - 1e-4)
            # Each cell takes the mismatch less the part left in place.
            dtγ = FT(60)
            r = @. M / A
            ᶜexpected = @. ᶜm - r * ᶜabs
            function change(ratio)
                ᶠflux = @. CA.CT3(Geometry.WVector(-(ᶠI - r * ᶠA) / dtγ * ratio))
                return @. -dtγ * CA.ᶜadvdivᵥ(ᶠflux)
            end
            scale = maximum(abs, parent(ᶜm))
            @test maximum(abs, parent(change(ᶠratio)) .- parent(ᶜexpected)) <
                  1000 * eps(FT) * scale
            # Without the ratio a deep atmosphere misses, so the test can fail.
            deep && @test maximum(
                abs,
                parent(change(one(FT))) .- parent(ᶜexpected),
            ) > 1e-4 * scale
        end
    end

    @testset "Repair on fields ($FT)" for FT in (Float32, Float64)
        # The kernels above, applied through `repair_energy_source_tags!` as
        # `constrain_state!` calls it, on plain arrays. Two cells: the first has
        # a positive total and a negative tag of each kind, the second a total
        # that is not positive.
        strat = CA.EnergySourceTag{:strat}(
            CA.TanhAltitudeRegion(FT(750), FT(100)),
        )
        tropo = CA.EnergySourceTag{:tropo}(
            CA.TanhAltitudeRegion(FT(750), FT(100), false),
        )
        sfc = CA.EnergySourceTag{:sfc}(nothing, :surface_flux)
        tags = (strat, tropo, sfc)
        tag_state_names = (:ρe_src_strat, :ρe_src_tropo, :ρe_src_sfc)
        c = FT(50000)
        ρ = FT[1, 1]
        ρe_tot = FT[-40000, -60000]
        E = ρe_tot .+ c .* ρ
        @test E[1] > 0
        @test E[2] < 0
        state() = (;
            c = (;
                ρ = copy(ρ),
                ρe_tot = copy(ρe_tot),
                ρe_src_strat = FT[12000, -3000],
                ρe_src_tropo = FT[-2000, -7000],
                ρe_src_sfc = FT[-5, -5],
            ),
        )
        cache(model) = (;
            atmos = (; energy_source_tagging_model = model),
            tagging = (;
                ᶜenergy_source_fix = (;
                    ρe_src_strat = zeros(FT, 2),
                    ρe_src_tropo = zeros(FT, 2),
                    ρe_src_sfc = zeros(FT, 2),
                ),
                ᶜenergy_source_pos = zeros(FT, 2),
                ᶜenergy_source_neg = zeros(FT, 2),
            ),
        )
        before = state().c

        Y = state()
        p = cache(CA.EnergySourceTaggingModel(tags, c))
        CA.repair_energy_source_tags!(Y, p)
        fix = p.tagging.ᶜenergy_source_fix
        # Where the total is positive, the partition keeps its sum and every tag
        # ends non-negative. The tag that carries a source is clipped at zero.
        @test Y.c.ρe_src_strat[1] + Y.c.ρe_src_tropo[1] ≈
              before.ρe_src_strat[1] + before.ρe_src_tropo[1]
        @test Y.c.ρe_src_strat[1] > 0
        @test Y.c.ρe_src_tropo[1] == 0
        @test Y.c.ρe_src_sfc[1] == 0
        # The ledger is the change, and the partition's entries cancel.
        for name in tag_state_names
            @test getproperty(fix, name) ≈
                  getproperty(Y.c, name) .- getproperty(before, name)
        end
        @test fix.ρe_src_strat[1] + fix.ρe_src_tropo[1] ≈ 0 atol =
            sqrt(eps(FT)) * abs(before.ρe_src_strat[1])
        @test fix.ρe_src_sfc[1] == 5
        # Where the total is not positive, nothing is touched.
        for name in tag_state_names
            @test getproperty(Y.c, name)[2] == getproperty(before, name)[2]
            @test getproperty(fix, name)[2] == 0
        end

        # Switched off, the repair leaves the tags and the ledger alone.
        Y = state()
        p = cache(CA.EnergySourceTaggingModel(tags, c; repair = false))
        CA.repair_energy_source_tags!(Y, p)
        for name in tag_state_names
            @test getproperty(Y.c, name) == getproperty(before, name)
            @test all(iszero, getproperty(p.tagging.ᶜenergy_source_fix, name))
        end
    end

    @testset "AtmosModel integration" begin
        model = column_atmos_model()
        @test isnothing(model.energy_source_tagging_model)
        @test isnothing(model.tagging.energy_source_tagging_model)

        tags = (CA.EnergySourceTag{:everywhere}(CA.EntireDomain()),)
        model = column_atmos_model(;
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
                column_atmos_model(),
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
            column_atmos_model(;
                energy_source_tagging_model = CA.EnergySourceTaggingModel(tags),
            ),
        )
        @test haskey(CA.Diagnostics.ALL_DIAGNOSTICS, "e_src_tropics")
        @test haskey(CA.Diagnostics.ALL_DIAGNOSTICS, "e_src_extratropics")
        @test haskey(CA.Diagnostics.ALL_DIAGNOSTICS, "e_src_res")
        @test haskey(CA.Diagnostics.ALL_DIAGNOSTICS, "e_src_fix_tropics")

        # With the repair on, the default output carries its ledgers, sampled
        # rather than averaged, because each is a running total. With the
        # repair off they would read zero, so they are left out.
        scheduled_names(repair) = begin
            tagging = CA.AtmosTagging(;
                energy_source_tagging_model = CA.EnergySourceTaggingModel(
                    tags;
                    repair,
                ),
            )
            scheduled = CA.Diagnostics.default_diagnostics(
                tagging,
                86400.0,
                Dates.DateTime(2010, 1, 1),
                0;
                output_writer = ClimaDiagnostics.Writers.DictWriter(),
            )
            Dict(
                ClimaDiagnostics.DiagnosticVariables.short_name(d.variable) =>
                    d for d in scheduled
            )
        end
        with_repair = scheduled_names(true)
        @test haskey(with_repair, "e_src_fix_tropics")
        @test haskey(with_repair, "e_src_fix_extratropics")
        @test isnothing(with_repair["e_src_fix_tropics"].reduction_time_func)
        @test !isnothing(with_repair["e_src_tropics"].reduction_time_func)
        @test !haskey(scheduled_names(false), "e_src_fix_tropics")
    end

    @testset "Processes that no tag follows" begin
        tropics = CA.EnergySourceTag{:tropics}(CA.TanhLatitudeRegion(20.0, 2.0, true))
        extratropics =
            CA.EnergySourceTag{:extratropics}(CA.TanhLatitudeRegion(20.0, 2.0, false))
        rad = CA.EnergySourceTag{:rad}(nothing, :radiation)
        sfc = CA.EnergySourceTag{:sfc}(nothing, :surface_flux)
        mp = CA.EnergySourceTag{:mp}(nothing, :microphysics)
        new_tropics = CA.EnergySourceTag{:new_tropics}(
            CA.TanhLatitudeRegion(20.0, 2.0, true),
            CA.KNOWN_TAG_SOURCES,
        )
        # A stand-in for the model, with only the properties the check reads: a
        # sphere with gray radiation, surface fluxes and 0-moment microphysics,
        # which is C6's sphere of the tag-closure experiments.
        sphere(tags; subsidence = nothing) = (;
            energy_source_tagging_model = CA.EnergySourceTaggingModel(tags),
            radiation_mode = :gray,
            disable_surface_flux_tendency = false,
            subsidence,
            ls_adv = nothing,
            external_forcing = nothing,
            microphysics_model = CA.EquilibriumMicrophysics0M(),
        )
        @test CA.active_energy_source_processes(sphere(())) ==
              (:radiation, :surface_flux, :microphysics)

        # Without a tag for the rain-out, it is warned about, and nothing else.
        c6 = sphere((tropics, extratropics, sfc, rad, new_tropics))
        @test_logs (:warn, r"`microphysics` changes `ρe_tot`") CA.warn_untagged_energy_source_processes(
            c6,
        )
        # With one, as in C7, nothing is.
        @test_logs CA.warn_untagged_energy_source_processes(
            sphere((tropics, extratropics, sfc, rad, mp, new_tropics)),
        )
        # A tag listing every process follows none in particular.
        @test_logs (:warn, r"`subsidence`") match_mode = :any CA.warn_untagged_energy_source_processes(
            sphere((tropics, extratropics, sfc, rad, mp, new_tropics); subsidence = :on),
        )
        # Region tags alone do not split energy by process, so they get no warning.
        @test_logs CA.warn_untagged_energy_source_processes(
            sphere((tropics, extratropics, new_tropics)),
        )

        # Clipping `ρq_tot` changes `ρe_tot` outside the brackets, which is warned
        # about with the tags and not without them.
        clipping = CA.TracerNonnegativityElementConstraint{true}()
        @test_logs (:warn, r"clips") CA._warn_unbracketed_energy_source_constraints(
            CA.EnergySourceTaggingModel((tropics, extratropics)),
            clipping,
        )
        @test_logs CA._warn_unbracketed_energy_source_constraints(nothing, clipping)
        @test_logs CA._warn_unbracketed_energy_source_constraints(
            CA.EnergySourceTaggingModel((tropics, extratropics)),
            CA.TracerNonnegativityElementConstraint{false}(),
        )

        # The two limiters that clip `ρq_tot` are warned about too. A stand-in
        # for the model, with only the properties the check reads.
        limited(; limiter = nothing, method = nothing,
            microphysics_model =
            CA.EquilibriumMicrophysics0M(), tags = (tropics, extratropics)) = (;
            energy_source_tagging_model = isnothing(tags) ? nothing :
                                          CA.EnergySourceTaggingModel(tags),
            water = (; tracer_nonnegativity_method = method, microphysics_model),
            numerics = (; limiter),
        )
        quasimonotone = CA.QuasiMonotoneLimiter()
        borrowing = CA.TracerNonnegativityVerticalWaterBorrowing()
        @test_logs CA.warn_unbracketed_energy_source_constraints(limited())
        @test_logs (:warn, r"apply_sem_quasimonotone_limiter") CA.warn_unbracketed_energy_source_constraints(
            limited(; limiter = quasimonotone),
        )
        # Borrowing clips `ρq_tot` when every tracer is selected, or `ρq_tot`
        # is, and not otherwise.
        @test_logs (:warn, r"vertical_water_borrowing") CA.warn_unbracketed_energy_source_constraints(
            limited(; method = borrowing),
        )
        @test_logs (:warn, r"vertical_water_borrowing") CA.warn_unbracketed_energy_source_constraints(
            limited(; method = borrowing),
            (:ρq_tot, :ρq_lcl),
        )
        @test_logs CA.warn_unbracketed_energy_source_constraints(
            limited(; method = borrowing),
            (:ρq_lcl,),
        )
        # Neither without the tags, nor in a dry model.
        @test_logs CA.warn_unbracketed_energy_source_constraints(
            limited(; limiter = quasimonotone, method = borrowing, tags = nothing),
        )
        @test_logs CA.warn_unbracketed_energy_source_constraints(
            limited(;
                limiter = quasimonotone,
                method = borrowing,
                microphysics_model = CA.DryModel(),
            ),
        )
    end

    # The audit table's energy source columns, on a column of four unit-height
    # cells, where a volume integral is the plain sum of the cells' values.
    @testset "The audit's energy source columns" begin
        CC = CA.ClimaCore
        FT = Float64
        space = CC.CommonSpaces.ColumnSpace(
            FT;
            z_min = 0,
            z_max = 4,
            z_elem = 4,
            staggering = CC.CommonSpaces.CellCenter(),
        )
        function cells(values)
            field = zeros(space)
            parent(field) .= reshape(FT.(values), size(parent(field)))
            return field
        end
        tropics = CA.EnergySourceTag{:tropics}(CA.TanhLatitudeRegion(20.0, 2.0, true))
        rad = CA.EnergySourceTag{:rad}(nothing, :radiation)
        sfc = CA.EnergySourceTag{:sfc}(nothing, :surface_flux)
        model = CA.EnergySourceTaggingModel((tropics, rad, sfc))

        ᶜnames = (:ρ, :ρe_src_tropics, :ρe_src_rad, :ρe_src_sfc)
        ᶜY = similar(
            CC.Fields.coordinate_field(space),
            NamedTuple{ᶜnames, NTuple{4, FT}},
        )
        ᶜY.ρ .= cells([2, 2, 2, 2])
        # The region tag is negative too, and no source column counts it.
        ᶜY.ρe_src_tropics .= cells([-100, -100, 5, 5])
        ᶜY.ρe_src_rad .= cells([-2, 4, -6, 8])
        ᶜY.ρe_src_sfc .= cells([1, -1, 3, 5])
        Y = CC.Fields.FieldVector(; c = ᶜY)
        fix = (;
            ρe_src_tropics = cells([-1, 0, 0, 0]),
            ρe_src_rad = cells([1, 0, -2, 0]),
            ρe_src_sfc = cells([0, 0, 0, 3]),
        )
        p = (;
            scratch = (; ᶜtemp_scalar = zeros(space)),
            tagging = (; ᶜenergy_source_fix = fix),
        )

        audit = CA.energy_source_audit(Y, p, model, FT(10))
        # The negative parts of the source tags: -2, -6 and -1.
        @test audit.source_negative == 9
        @test audit.source_negative_relative == 0.9
        # The smallest source tag per unit mass: -6 / 2.
        @test audit.source_minimum == -3
        # Every tag's ledger counts, the region tag's too: 1 + 2 + 3 + 1.
        @test audit.repair_moved == 7
        @test audit.repair_moved_relative == 0.7

        # A zero scale gives zero ratios, as the rest of the audit does.
        zero_scale = CA.energy_source_audit(Y, p, model, FT(0))
        @test zero_scale.source_negative_relative == 0
        @test zero_scale.repair_moved_relative == 0

        # Without a source tag there is nothing to take a minimum of.
        region_only = CA.EnergySourceTaggingModel((tropics,))
        no_sources = CA.energy_source_audit(Y, p, region_only, FT(10))
        @test no_sources.source_negative == 0
        @test isnan(no_sources.source_minimum)
        @test no_sources.repair_moved == 1
    end

    @testset "Fields the Jacobian solves apart" begin
        name(chain...) = CA.MatrixFields.FieldName(chain...)
        block_pairs = (
            (name(:c, :ρ), name(:c, :ρ)) => :block,
            (name(:c, :ρe_tot), name(:c, :ρ)) => :block,
            (name(:c, :ρe_tot), name(:c, :ρe_tot)) => :block,
            # A tag with only its own diagonal is solved apart.
            (name(:c, :ρe_src_tropics), name(:c, :ρe_src_tropics)) => :block,
            # So is a record.
            (name(:c, :prc_e_radiation), name(:c, :prc_e_radiation)) => :block,
            # A tag another block names is not.
            (name(:c, :ρq_tag_rain), name(:c, :ρq_tag_rain)) => :block,
            (name(:c, :ρq_tag_rain), name(:f, :u₃)) => :block,
            # Nor is a field that is neither a tag nor a record, even when it
            # couples to nothing.
            (name(:c, :ρq_lcl), name(:c, :ρq_lcl)) => :block,
            (name(:f, :u₃), name(:f, :u₃)) => :block,
        )
        @test CA.uncoupled_jacobian_names(block_pairs) ==
              (name(:c, :ρe_src_tropics), name(:c, :prc_e_radiation))
        # A block that names a part of a tag also couples it.
        @test isempty(
            CA.uncoupled_jacobian_names((
                (name(:c, :ρe_src_x), name(:c, :ρe_src_x)) => :block,
                (name(:c, :ρ), name(:c, :ρe_src_x, :components)) => :block,
            )),
        )
    end

    # The split must give the nested solver's increments bit for bit when a tag
    # block is not a scaled identity and the solve iterates more than once. With
    # the `-I` blocks of the integration test's column every solver gives `-R`
    # exactly, so that test cannot tell a wrong iteration count from a right
    # one. The state here is a column with two coupled scalars, a face velocity,
    # a tag and a record, whose own blocks are tridiagonal. The two algorithms
    # have the shapes `jacobian_solver_algorithm` builds.
    @testset "The split solver matches the nested one on tridiagonal blocks" begin
        CC = CA.ClimaCore
        MF = CA.MatrixFields
        FT = Float64
        column(staggering) = CC.CommonSpaces.ColumnSpace(
            FT;
            z_min = 0,
            z_max = 1000,
            z_elem = 12,
            staggering,
        )
        ᶜspace = column(CC.CommonSpaces.CellCenter())
        ᶠspace = column(CC.CommonSpaces.CellFace())
        ᶜnames = (:ρ, :ρe_tot, :ρe_src_upper, :prc_e_radiation)
        Y = CC.Fields.FieldVector(;
            c = similar(
                CC.Fields.coordinate_field(ᶜspace),
                NamedTuple{ᶜnames, NTuple{4, FT}},
            ),
            f = similar(
                CC.Fields.coordinate_field(ᶠspace),
                NamedTuple{(:u₃,), Tuple{FT}},
            ),
        )
        # Values that differ from point to point and from field to field,
        # without random numbers.
        fill_pattern!(values, shift) =
            values .= sin.(shift .+ 0.7 .* reshape(1:length(values), size(values)))
        R = similar(Y)
        fill_pattern!(parent(R.c), 0)
        fill_pattern!(parent(R.f), 1)

        # A block of the given row type: a pattern of size 0.1 in every entry,
        # plus `diagonal` on the main diagonal. Entries that would reach past
        # an end of the column are zero.
        function band_block(space, row_type, diagonal, shift)
            block = fill(zero(row_type), space)
            # One row per level and one column per entry of the band. A column
            # Field's parent array has singleton dimensions around those two.
            n_levels = size(parent(block), 1)
            values = reshape(parent(block), n_levels, :)
            fill_pattern!(values, shift)
            values .*= 0.1
            n_entries = size(values, 2)
            if isodd(n_entries)
                values[:, (n_entries + 1) ÷ 2] .+= diagonal
            end
            if n_entries > 1
                values[1, 1] = 0
                values[end, end] = 0
            end
            return block
        end
        ᶜdiagonal(shift) =
            band_block(ᶜspace, MF.DiagonalMatrixRow{FT}, -1, shift)
        ᶜtridiagonal(shift) =
            band_block(ᶜspace, MF.TridiagonalMatrixRow{FT}, -1, shift)
        ᶠtridiagonal(shift) =
            band_block(ᶠspace, MF.TridiagonalMatrixRow{FT}, -1, shift)
        # Faces to centres and back, as for a divergence and a gradient.
        ᶜᶠbidiagonal(shift) =
            band_block(ᶜspace, MF.BidiagonalMatrixRow{FT}, 0, shift)
        ᶠᶜbidiagonal(shift) =
            band_block(ᶠspace, MF.BidiagonalMatrixRow{FT}, 0, shift)
        block_pairs = (
            (CA.MatrixFields.@name(c.ρ), CA.MatrixFields.@name(c.ρ)) => ᶜdiagonal(2),
            (CA.MatrixFields.@name(c.ρe_tot), CA.MatrixFields.@name(c.ρe_tot)) =>
                ᶜdiagonal(3),
            (CA.MatrixFields.@name(c.ρ), CA.MatrixFields.@name(f.u₃)) =>
                ᶜᶠbidiagonal(4),
            (CA.MatrixFields.@name(c.ρe_tot), CA.MatrixFields.@name(f.u₃)) =>
                ᶜᶠbidiagonal(5),
            (CA.MatrixFields.@name(f.u₃), CA.MatrixFields.@name(c.ρ)) =>
                ᶠᶜbidiagonal(6),
            (CA.MatrixFields.@name(f.u₃), CA.MatrixFields.@name(c.ρe_tot)) =>
                ᶠᶜbidiagonal(7),
            (CA.MatrixFields.@name(f.u₃), CA.MatrixFields.@name(f.u₃)) =>
                ᶠtridiagonal(8),
            (
                CA.MatrixFields.@name(c.ρe_src_upper),
                CA.MatrixFields.@name(c.ρe_src_upper)
            ) =>
                ᶜtridiagonal(9),
            (
                CA.MatrixFields.@name(c.prc_e_radiation),
                CA.MatrixFields.@name(c.prc_e_radiation)
            ) =>
                ᶜtridiagonal(10),
        )
        uncoupled_names = CA.uncoupled_jacobian_names(block_pairs)
        @test uncoupled_names ==
              (
            CA.MatrixFields.@name(c.ρe_src_upper),
            CA.MatrixFields.@name(c.prc_e_radiation)
        )

        velocity_alg = MF.BlockLowerTriangularSolve(CA.MatrixFields.@name(f.u₃))
        iterative_alg(n_iters) = MF.ApproximateBlockArrowheadIterativeSolve(
            CA.MatrixFields.@name(c.ρ),
            CA.MatrixFields.@name(c.ρe_tot);
            alg₂ = velocity_alg,
            P_alg₁ = MF.MainDiagonalPreconditioner(),
            n_iters,
        )
        direct_alg = MF.BlockArrowheadSolve(
            CA.MatrixFields.@name(c.ρ),
            CA.MatrixFields.@name(c.ρe_tot);
            alg₂ = velocity_alg,
        )

        function increments(alg, split)
            matrix = MF.FieldMatrix(block_pairs...)
            solver =
                split ? CA.split_jacobian_solver(matrix, Y, alg, uncoupled_names) :
                MF.FieldMatrixWithSolver(matrix, Y, alg)
            ΔY = zero(Y)
            CA.LinearAlgebra.ldiv!(ΔY, solver, R)
            return ΔY
        end
        same_bits(a, b) =
            isequal(parent(a.c), parent(b.c)) && isequal(parent(a.f), parent(b.f))
        for alg in (iterative_alg(1), iterative_alg(2), direct_alg)
            @test same_bits(increments(alg, true), increments(alg, false))
        end
        # The count matters on these blocks: a second iteration changes the
        # tags' bits, so a split that ignored it would fail the check above.
        one_iteration = increments(iterative_alg(1), false)
        two_iterations = increments(iterative_alg(2), false)
        @test !isequal(
            parent(one_iteration.c.ρe_src_upper),
            parent(two_iterations.c.ρe_src_upper),
        )
        @test all(isfinite, parent(two_iterations.c))
        # Only the arrowhead solves are supported.
        @test_throws ErrorException CA.uncoupled_field_algorithm(
            MF.BlockDiagonalSolve(),
        )
    end
end

# The restart guard. A checkpoint records the settings that decide what the tags
# in it mean, and a restart that changes one is refused by name. This needs no
# simulation: a small checkpoint, and a model and a state that carry only what
# the check reads.
@testset "The restart guard" begin
    context = CA.ClimaComms.context()
    HDF5 = CA.InputOutput.HDF5
    tags(width = 100.0; sources = (:radiation,)) = (
        CA.EnergySourceTag{:strat}(CA.TanhAltitudeRegion(750.0, width, true)),
        CA.EnergySourceTag{:tropo}(CA.TanhAltitudeRegion(750.0, width, false)),
        CA.EnergySourceTag{:rad}(nothing, sources),
    )
    source_model(;
        offset = 50000.0,
        width = 100.0,
        sources = (:radiation,),
        repair = true,
        transport = CA.TracerEnergySourceTransport(),
    ) = CA.EnergySourceTaggingModel(tags(width; sources), offset; repair, transport)
    atmos(model; energy_process_record = nothing, water_process_record = nothing) =
        (; energy_source_tagging_model = model, energy_process_record, water_process_record)
    state(names...) =
        (; c = NamedTuple{(:ρ, :ρe_tot, names...)}(Tuple(zeros(2 + length(names)))))
    tagged = state(:ρe_src_strat, :ρe_src_tropo, :ρe_src_rad)
    directory = mktempdir()
    # A checkpoint with the attributes a run writes. `edit` changes the file
    # afterwards, to stand in for a file from another version.
    function checkpoint(model, name; record = true, edit = file -> nothing)
        path = joinpath(directory, "$name.hdf5")
        writer = CA.InputOutput.HDF5Writer(path, context)
        record && CA.write_energy_source_checkpoint_attributes!(writer.file, model)
        edit(writer.file)
        Base.close(writer)
        return path
    end
    check(path, model, Y = tagged; kwargs...) =
        CA.check_energy_source_checkpoint(path, atmos(model; kwargs...), Y, context)

    written = checkpoint(source_model(), "written")
    # The same settings restart.
    @test isnothing(check(written, source_model()))
    # Each changed setting is refused, and the error names it with both values.
    @test_throws r"`energy_source_tag_offset: 50000\.0`.*sets 60000\.0" check(
        written,
        source_model(; offset = 60000.0),
    )
    @test_throws r"tag `strat`.*width = 100\.0.*width = 200\.0" check(
        written,
        source_model(; width = 200.0),
    )
    @test_throws r"tag `rad`.*sources `radiation`.*sources `surface_flux`" check(
        written,
        source_model(; sources = (:surface_flux,)),
    )
    @test_throws r"`energy_source_tag_transport: tracer`.*sets enthalpy" check(
        written,
        source_model(; transport = CA.EnthalpyEnergySourceTransport()),
    )
    @test_throws r"`energy_source_tag_repair: true`.*sets false" check(
        written,
        source_model(; repair = false),
    )
    unrepaired = checkpoint(source_model(; repair = false), "unrepaired")
    @test_throws r"`energy_source_tag_repair: false`.*sets true" check(
        unrepaired,
        source_model(),
    )
    # A tag matches a source by membership, so the order of its sources does
    # not count.
    two_sources = checkpoint(
        source_model(; sources = (:radiation, :surface_flux)),
        "two_sources",
    )
    @test isnothing(
        check(two_sources, source_model(; sources = (:surface_flux, :radiation))),
    )
    # No offset is an offset of zero, as `energy_source_tag_offset: 0` is read.
    unshifted = checkpoint(source_model(; offset = nothing), "unshifted")
    @test isnothing(check(unshifted, source_model(; offset = nothing)))
    @test isnothing(check(unshifted, source_model(; offset = 0.0)))
    @test_throws r"`energy_source_tag_offset: 0\.0`.*sets 50000\.0" check(
        unshifted,
        source_model(),
    )
    # A `Float32` offset is written and compared in its own type.
    single = checkpoint(source_model(; offset = 110495.3f0), "single")
    @test isnothing(check(single, source_model(; offset = 110495.3f0)))

    # The fields, which need no attribute. A tag set that differs names what
    # is missing and what is not configured.
    other_tags = CA.EnergySourceTaggingModel(
        (tags()[1], tags()[2], CA.EnergySourceTag{:sfc}(nothing, :surface_flux)),
        50000.0,
    )
    @test_throws r"Missing from the file: sfc\. Not configured: rad\." check(
        written,
        other_tags,
    )
    reordered = CA.EnergySourceTaggingModel((tags()[2], tags()[1], tags()[3]), 50000.0)
    @test_throws r"same, in a different order" check(written, reordered)
    # Tags in the file, none in the run, and the reverse.
    @test_throws r"energy source tags strat, tropo, rad, and this run configures none" check(
        written,
        nothing,
    )
    @test_throws r"energy source tags none, and this run configures strat" check(
        written,
        source_model(),
        state(),
    )
    @test isnothing(check(written, nothing, state()))
    # The process records are checked the same way, energy and water.
    record = CA.ProcessRecordModel((CA.RecordedProcess{:radiation}(),))
    @test_throws r"energy process records none, and this run configures radiation" check(
        written,
        source_model(),
        tagged;
        energy_process_record = record,
    )
    @test isnothing(
        check(
            written,
            source_model(),
            state(:ρe_src_strat, :ρe_src_tropo, :ρe_src_rad, :prc_e_radiation);
            energy_process_record = record,
        ),
    )
    @test_throws r"water process records none, and this run configures radiation" check(
        written,
        source_model(),
        tagged;
        water_process_record = record,
    )

    # A checkpoint from before the guard is checked by its fields, with a
    # warning, and restarts.
    unrecorded = checkpoint(source_model(), "unrecorded"; record = false)
    @test_logs (:warn, r"written before") check(unrecorded, source_model())
    # A checkpoint in another version of the format is refused.
    newer = checkpoint(
        source_model(),
        "newer";
        edit = file -> begin
            HDF5.delete_attribute(file, "energy_source_tag_checkpoint")
            HDF5.write_attribute(file, "energy_source_tag_checkpoint", 2)
        end,
    )
    @test_throws r"version 2 of the checkpoint format.*reads version 1" check(
        newer,
        source_model(),
    )
    # A tag the file holds but records no definition for is refused.
    undefined = checkpoint(
        source_model(),
        "undefined";
        edit = file -> HDF5.delete_attribute(file, "energy_source_tag.rad"),
    )
    @test_throws r"no definition for the energy source tag `rad`" check(
        undefined,
        source_model(),
    )
    # A polygon too long for one HDF5 attribute is written in parts.
    long_polygon = CA.EnergySourceTaggingModel(
        (
            CA.EnergySourceTag{:strat}(
                CA.TanhPolygonRegion(
                    Tuple((k / 10, sin(k / 100)) for k in 1:1600),
                    1.0,
                    true,
                ),
            ),
        ),
        50000.0,
    )
    long = checkpoint(long_polygon, "long")
    @test HDF5.h5open(file -> HDF5.read_attribute(file, "energy_source_tag.strat"), long) >
          1
    @test isnothing(check(long, long_polygon, state(:ρe_src_strat)))

    # The region a checkpoint records reads back to the same region, for every
    # region type, in `Float64` and in `Float32`.
    for FT in (Float64, Float32)
        regions = (
            CA.EntireDomain(),
            CA.TanhAltitudeRegion(FT(750.3), FT(100), false),
            CA.TanhLatitudeRegion(FT(20), FT(2), true),
            CA.TanhBoxRegion(FT(170), FT(-170), FT(-10), FT(10), FT(2), false),
            CA.TanhPolygonRegion(
                ((FT(0), FT(0)), (FT(10), FT(0)), (FT(5), FT(8))),
                FT(1.5),
                true,
            ),
        )
        for region in regions
            @test CA.tag_region_from_config(Dict(CA.tag_region_spec(region)), FT) ==
                  region
        end
    end
    @test CA.tag_region_text(nothing) == "none"
    @test CA.tag_region_text(CA.EntireDomain()) == "everywhere"
    @test CA.tag_region_text(CA.TanhAltitudeRegion(750.0, 100.0, true)) ==
          "tanh_altitude(z_center = 750.0, width = 100.0, above = true)"
    # A `Float32` region prints as it was configured, not widened.
    @test CA.tag_region_text(CA.TanhAltitudeRegion(750.3f0, 100.0f0, true)) ==
          "tanh_altitude(z_center = 750.3, width = 100.0, above = true)"
    @test CA.tag_region_text(
        CA.TanhPolygonRegion(((0.0, 1.5), (2.0, 3.0), (4.0, 5.0)), 1.0, false),
    ) ==
          "tanh_polygon(vertices = [[0.0, 1.5], [2.0, 3.0], [4.0, 5.0]], width = 1.0, inside = false)"
end
