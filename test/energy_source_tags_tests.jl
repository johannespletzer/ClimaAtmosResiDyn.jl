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
                scratch = CA.energy_source_scratch(Y, model),
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
        @test haskey(CA.Diagnostics.ALL_DIAGNOSTICS, "e_src_fix_tropics")
    end
end
