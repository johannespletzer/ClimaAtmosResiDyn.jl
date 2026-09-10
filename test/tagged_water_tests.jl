using Test
import ClimaAtmos as CA
import ClimaCore.MatrixFields: @name

# Unit tests for the tagged water tracers. The region/mask machinery is shared
# with the energy tags and is covered by `tagged_tracers_tests.jl`; what is
# tested here is what differs: the water source table, the initial partition,
# the production/loss attribution rule, and the limiter rescale.
#
# The attribution and rescale kernels are written as broadcasts over
# property-accessed fields, so they run unchanged on NamedTuples of plain
# `Vector`s. That makes every closure assertion below exact and free of any
# simulation setup.

@testset "Tagged water" begin
    for FT in (Float32, Float64)
        @testset "State variables ($FT)" begin
            tags = (
                CA.WaterTag{:tropics}(
                    CA.TanhLatitudeRegion(FT(20), FT(2), true),
                ),
                CA.WaterTag{:extratropics}(
                    CA.TanhLatitudeRegion(FT(20), FT(2), false),
                ),
                CA.WaterTag{:evap}(nothing, :surface_flux),
            )
            model = CA.WaterTaggingModel(tags)
            ρq_tot = FT(0.01)
            local_geometry = (; coordinates = (; lat = FT(10), z = FT(500)))

            # Disabled water tagging adds no fields
            @test CA.water_tagging_variables(ρq_tot, local_geometry, nothing) ==
                  (;)

            nt = CA.water_tagging_variables(ρq_tot, local_geometry, model)
            @test propertynames(nt) ==
                  (:ρq_tag_tropics, :ρq_tag_extratropics, :ρq_tag_evap)
            @test eltype(values(nt)) == FT

            # Source tags start at zero; a partition of region tags sums to the
            # parent exactly
            @test nt.ρq_tag_evap == FT(0)
            @test nt.ρq_tag_tropics + nt.ρq_tag_extratropics ≈ ρq_tot rtol =
                4 * eps(FT)

            # Names are ρ-weighted, so the generic tracer machinery picks them
            # up and supplies transport
            @test all(
                CA.is_tracer_var,
                (:ρq_tag_tropics, :ρq_tag_extratropics, :ρq_tag_evap),
            )

            @test CA.water_tag_state_names(model) ==
                  (:ρq_tag_tropics, :ρq_tag_extratropics, :ρq_tag_evap)
            # The residual sums only pure region tags
            @test CA.water_region_tag_state_names(model) ==
                  (:ρq_tag_tropics, :ρq_tag_extratropics)
        end

        @testset "Config parsing ($FT)" begin
            entries = [
                Dict{String, Any}(
                    "name" => "tropics",
                    "region" => Dict{String, Any}(
                        "type" => "tanh_latitude",
                        "lat_bound" => 20.0,
                        "width" => 2.0,
                    ),
                ),
                Dict{String, Any}(
                    "name" => "evap",
                    "source" => "surface_flux",
                ),
                Dict{String, Any}("name" => "forced", "source" => "forcing"),
            ]
            tags = CA.water_tracer_tuple(entries, FT)
            @test length(tags) == 3
            @test map(CA.tag_name, tags) == (:tropics, :evap, :forced)
            @test tags[1].region isa CA.TanhLatitudeRegion{FT}
            @test tags[2].sources == (:surface_flux,)
            # Groups expand to their members
            @test tags[3].sources == CA.WATER_TAG_SOURCE_GROUPS.forcing
            @test Set(CA.WATER_TAG_SOURCE_GROUPS.all) ==
                  Set(CA.KNOWN_WATER_TAG_SOURCES)

            # Water and energy have deliberately different source tables:
            # radiation and Held-Suarez do not move water, and precipitation is
            # mirrored rather than attributed.
            @test !(:radiation in CA.KNOWN_WATER_TAG_SOURCES)
            @test !(:held_suarez in CA.KNOWN_WATER_TAG_SOURCES)
            @test !(:precipitation in CA.KNOWN_WATER_TAG_SOURCES)
            @test :radiation in CA.KNOWN_TAG_SOURCES

            @test_throws ErrorException CA.water_tracer_tuple(
                [Dict{String, Any}("source" => "surface_flux")],
                FT,
            ) # missing name
            @test_throws ErrorException CA.water_tracer_tuple(
                [Dict{String, Any}("name" => "bare")],
                FT,
            ) # neither region nor source
            @test_throws ErrorException CA.water_tracer_tuple(
                [
                    Dict{String, Any}("name" => "a", "source" => "surface_flux"),
                    Dict{String, Any}("name" => "a", "source" => "subsidence"),
                ],
                FT,
            ) # duplicate names
            @test_throws ErrorException CA.water_tracer_tuple(
                [Dict{String, Any}("name" => "a", "source" => "radiation")],
                FT,
            ) # energy-only source label
        end

        @testset "Donor fraction ($FT)" begin
            @test CA.water_tag_fraction(FT(2), FT(8)) == FT(0.25)
            # Clamped: tags that have drifted out of partition cannot
            # over-deplete, and a negative tag cannot produce water
            @test CA.water_tag_fraction(FT(9), FT(8)) == FT(1)
            @test CA.water_tag_fraction(FT(-1), FT(8)) == FT(0)
            # Dry-cell fallback: no water means no share, and no division
            @test CA.water_tag_fraction(FT(1), FT(0)) == FT(0)
            @test CA.water_tag_fraction(FT(1), FT(-1)) == FT(0)
            @test isfinite(CA.water_tag_fraction(FT(1), FT(0)))
        end

        @testset "Rescale shift ($FT)" begin
            # A partition tag takes the parent's increment in proportion to what
            # it holds, over the positive part of the partition sum. Two tags
            # holding 2 and 6 of a parent that goes 8 -> 12 split the +4.
            @test CA.water_tag_rescale_shift(FT(2), FT(12), FT(8), FT(8)) ==
                  FT(1)
            @test CA.water_tag_rescale_shift(FT(6), FT(12), FT(8), FT(8)) ==
                  FT(3)
            # Nothing clamps the shift from above: both limiters move water
            # between cells, so a cell that was clipped up legitimately needs
            # its tags raised.
            @test CA.water_tag_rescale_shift(FT(4), FT(16), FT(8), FT(8)) ==
                  FT(4)

            # The shares are renormalized, so what the tags absorb is the
            # parent's whole increment even when they do not add up to it. Two
            # tags holding 3 of a parent of 8 each take half of +4.
            @test CA.water_tag_rescale_shift(FT(3), FT(12), FT(8), FT(6)) ==
                  FT(2)

            # The loss is floored at what the partition holds, so a tag cannot
            # be driven negative. Two tags holding 1 each cannot pay out 8.
            @test CA.water_tag_rescale_shift(FT(1), FT(0), FT(8), FT(2)) ==
                  FT(-1)
            # On a closed partition that floor is exactly the old factor's floor
            # at zero: a parent clipped from 8 to -4 empties its tags.
            @test CA.water_tag_rescale_shift(FT(6), FT(-4), FT(8), FT(8)) ==
                  FT(-6)

            # A negative tag is left for `repair_water_tag_partition!`, and an
            # empty partition gets nothing invented into it
            @test CA.water_tag_rescale_shift(FT(-1), FT(12), FT(8), FT(5)) ==
                  FT(0)
            @test CA.water_tag_rescale_shift(FT(0), FT(12), FT(8), FT(0)) ==
                  FT(0)
            @test isfinite(
                CA.water_tag_rescale_shift(FT(1), FT(12), FT(8), FT(0)),
            )

            # A non-positive parent empties every tag, whatever it held. This is
            # the branch a nonnegativity constraint reaches, and the ledger has
            # to see the removal.
            @test CA.water_tag_rescale_shift(FT(-1), FT(0), FT(-2), FT(0)) ==
                  FT(1)
            @test CA.water_tag_rescale_shift(FT(2), FT(3), FT(0), FT(2)) ==
                  FT(-2)

            # A source tag uses its own unnormalized donor share instead, as it
            # does for sedimentation: it is not a member of the partition
            @test CA.water_tag_source_rescale_shift(FT(2), FT(12), FT(8)) ==
                  FT(1)
            @test CA.water_tag_source_rescale_shift(FT(2), FT(4), FT(8)) ==
                  FT(-1)
            # Its loss is floored at the parent, so it cannot go negative either
            @test CA.water_tag_source_rescale_shift(FT(2), FT(-8), FT(8)) ==
                  FT(-2)
            @test CA.water_tag_source_rescale_shift(FT(1), FT(3), FT(0)) ==
                  FT(-1)
        end

        @testset "Attribution: production and loss ($FT)" begin
            tropics = CA.WaterTag{:tropics}(
                CA.TanhLatitudeRegion(FT(20), FT(2), true),
            )
            extratropics = CA.WaterTag{:extratropics}(
                CA.TanhLatitudeRegion(FT(20), FT(2), false),
            )
            evap = CA.WaterTag{:evap}(nothing, :surface_flux)
            tags = (tropics, extratropics, evap)

            # Masks partition unity; the tags partition ρq_tot
            ᶜmasks = (;
                ρq_tag_tropics = FT[1, 0.75, 0.25, 0],
                ρq_tag_extratropics = FT[0, 0.25, 0.75, 1],
            )
            ᶜY = (;
                ρq_tot = FT[8, 8, 8, 8],
                ρq_tag_tropics = FT[6, 4, 2, 0],
                ρq_tag_extratropics = FT[2, 4, 6, 8],
                ρq_tag_evap = FT[4, 4, 4, 4],
            )
            zero_tendency() = (;
                ρq_tag_tropics = zeros(FT, 4),
                ρq_tag_extratropics = zeros(FT, 4),
                ρq_tag_evap = zeros(FT, 4),
            )

            # --- Pure production ------------------------------------------
            ᶜΔ = FT[1, 2, 3, 4]
            ᶜYₜ = zero_tendency()
            CA._accumulate_water_tags!(
                ᶜYₜ, ᶜY, ᶜmasks, ᶜΔ, :surface_flux, tags,
            )
            # Region tags receive every source, masked
            @test ᶜYₜ.ρq_tag_tropics ≈ ᶜmasks.ρq_tag_tropics .* ᶜΔ
            @test ᶜYₜ.ρq_tag_extratropics ≈ ᶜmasks.ρq_tag_extratropics .* ᶜΔ
            # A region-less source tag receives its own source unweighted
            @test ᶜYₜ.ρq_tag_evap ≈ ᶜΔ
            # The region partition reproduces the parent increment exactly
            @test ᶜYₜ.ρq_tag_tropics .+ ᶜYₜ.ρq_tag_extratropics ≈ ᶜΔ

            # A source the tag does not list produces nothing for it
            ᶜYₜ = zero_tendency()
            CA._accumulate_water_tags!(
                ᶜYₜ, ᶜY, ᶜmasks, ᶜΔ, :subsidence, tags,
            )
            @test all(iszero, ᶜYₜ.ρq_tag_evap)
            @test ᶜYₜ.ρq_tag_tropics ≈ ᶜmasks.ρq_tag_tropics .* ᶜΔ

            # --- Pure loss ------------------------------------------------
            # Loss is donor-proportional, NOT mask-weighted, and reaches every
            # tag regardless of the sources it lists. This is the rule that
            # differs from the energy tags.
            ᶜΔ = FT[-1, -2, -3, -4]
            ᶜYₜ = zero_tendency()
            CA._accumulate_water_tags!(
                ᶜYₜ, ᶜY, ᶜmasks, ᶜΔ, :subsidence, tags,
            )
            @test ᶜYₜ.ρq_tag_tropics ≈ ᶜΔ .* ᶜY.ρq_tag_tropics ./ ᶜY.ρq_tot
            # Had the mask rule been used for loss, the tropics tag would have
            # lost mask*Δ = -1 in the first cell instead of its own share
            @test ᶜYₜ.ρq_tag_tropics[1] ≉ ᶜmasks.ρq_tag_tropics[1] * ᶜΔ[1]
            # The source tag is depleted even though `subsidence` is not its
            # source: it is a water mass, not a running source integral
            @test ᶜYₜ.ρq_tag_evap ≈ ᶜΔ .* ᶜY.ρq_tag_evap ./ ᶜY.ρq_tot
            @test all(<=(0), ᶜYₜ.ρq_tag_evap)
            # Donor shares of a partition sum to 1, so the loss closes
            @test ᶜYₜ.ρq_tag_tropics .+ ᶜYₜ.ρq_tag_extratropics ≈ ᶜΔ

            # --- Mixed sign, per-process closure --------------------------
            # Σₖ Δₖ == Δ for the partition, with production in some cells and
            # loss in others.
            ᶜΔ = FT[3, -2, 5, -4]
            ᶜYₜ = zero_tendency()
            CA._accumulate_water_tags!(
                ᶜYₜ, ᶜY, ᶜmasks, ᶜΔ, :surface_flux, tags,
            )
            @test ᶜYₜ.ρq_tag_tropics .+ ᶜYₜ.ρq_tag_extratropics ≈ ᶜΔ

            # --- Positivity -----------------------------------------------
            # A loss clamped so that |Δ| ≤ ρq_tot (which the 0M limiter
            # enforces) cannot drive any tag below zero over one Euler step
            # Parenthesized because `.-ᶜ` parses as the suffixed operator `.-ᶜ`,
            # which does not exist as a unary operator
            ᶜΔ = .-(ᶜY.ρq_tot)
            ᶜYₜ = zero_tendency()
            CA._accumulate_water_tags!(
                ᶜYₜ, ᶜY, ᶜmasks, ᶜΔ, :surface_flux, tags,
            )
            @test all(>=(0), ᶜY.ρq_tag_tropics .+ ᶜYₜ.ρq_tag_tropics)
            @test all(>=(0), ᶜY.ρq_tag_evap .+ ᶜYₜ.ρq_tag_evap)

            # --- Dry column ------------------------------------------------
            # No water anywhere: losses must be finite and zero, not NaN
            ᶜY_dry = (;
                ρq_tot = zeros(FT, 4),
                ρq_tag_tropics = zeros(FT, 4),
                ρq_tag_extratropics = zeros(FT, 4),
                ρq_tag_evap = zeros(FT, 4),
            )
            ᶜYₜ = zero_tendency()
            CA._accumulate_water_tags!(
                ᶜYₜ, ᶜY_dry, ᶜmasks, FT[-1, -2, -3, -4], :surface_flux, tags,
            )
            @test all(isfinite, ᶜYₜ.ρq_tag_tropics)
            @test all(iszero, ᶜYₜ.ρq_tag_tropics)
            @test all(iszero, ᶜYₜ.ρq_tag_evap)
        end

        @testset "Limiter rescale ($FT)" begin
            tags = (
                CA.WaterTag{:tropics}(
                    CA.TanhLatitudeRegion(FT(20), FT(2), true),
                ),
                CA.WaterTag{:extratropics}(
                    CA.TanhLatitudeRegion(FT(20), FT(2), false),
                ),
            )
            # Cells 1-5 have the tags summing exactly to the parent, so the
            # closure error is zero and the correction can only be checked
            # against the partition. Cells 6-9 are the cases that matter for
            # issue #64: the tags do not add up to the parent, in both
            # directions, so the correction has a nonzero error to act on.
            #
            # Parent went 8 -> 4 (clipped down), 8 -> 8 (untouched),
            # 8 -> 12 (borrowed up), 0 -> 2 (water where there was none),
            # -2 -> 0 (a negative parent clipped to zero), 10 -> 14 with the
            # tags 4 short of the parent, 10 -> 14 with the tags 2 over it,
            # 10 -> 2 with the tags holding less than the parent loses, and
            # 10 -> 12 with one tag already negative.
            ᶜρq_tot_before = FT[8, 8, 8, 0, -2, 10, 10, 10, 10]
            ᶜY = (;
                ρq_tot = FT[4, 8, 12, 2, 0, 14, 14, 2, 12],
                ρq_tag_tropics = FT[6, 4, 2, 0, -1, 3, 7, 1, -1],
                ρq_tag_extratropics = FT[2, 4, 6, 0, -1, 3, 5, 1, 5],
            )
            ᶜfix = (;
                ρq_tag_tropics = zeros(FT, 9),
                ρq_tag_extratropics = zeros(FT, 9),
            )
            p = (;
                tagging = (; ᶜwater_fix = ᶜfix, ᶜwater_pos = zeros(FT, 9)),
            )
            model = CA.WaterTaggingModel(tags)
            before_tropics = copy(ᶜY.ρq_tag_tropics)
            before_extra = copy(ᶜY.ρq_tag_extratropics)
            # The closure error the `q_tag_res` diagnostic reports, per cell.
            # Before the correction it is measured against the parent the tags
            # were in step with, `ᶜρq_tot_before`. `ᶜY.ρq_tot` already holds the
            # corrected parent, which is the one it is measured against
            # afterwards, so reading both from `ᶜY` would compare the tags
            # against a parent that has already moved.
            tagged(Y) = Y.ρq_tag_tropics .+ Y.ρq_tag_extratropics
            before_residual = ᶜρq_tot_before .- tagged(ᶜY)

            CA._rescale_water_tags!((; c = ᶜY), p, ᶜρq_tot_before, model)

            # Handing the parent's increment out in proportion to what each tag
            # holds preserves the partition wherever it was already closed
            @test ᶜY.ρq_tag_tropics[1:3] .+ ᶜY.ρq_tag_extratropics[1:3] ≈
                  ᶜY.ρq_tot[1:3]
            # ... and cannot invent water in a cell that had none, so that
            # water surfaces in `q_tag_res` instead of being attributed
            @test ᶜY.ρq_tag_tropics[4] == FT(0)
            # A negative tag is removed when the total water is set to zero.
            # The ledger records the amount removed as an increase.
            @test ᶜY.ρq_tag_tropics[5] == FT(0)
            @test ᶜfix.ρq_tag_tropics[5] == FT(1)
            @test all(>=(0), ᶜY.ρq_tag_tropics[1:8])

            # The closure error is what the multiplicative rule amplified. The
            # shares sum to one, so the partition absorbs the whole increment
            # and the error comes out exactly where it went in. Cell 6 is 4
            # short of its parent and cell 7 is 2 over it; the old rule would
            # have returned 4 * 1.4 = 5.6 and -2 * 1.4 = -2.8 instead.
            after_residual = ᶜY.ρq_tot .- tagged(ᶜY)
            atol = 32 * eps(FT) * maximum(abs.(ᶜρq_tot_before))
            @test after_residual[6] ≈ before_residual[6] atol = atol
            @test after_residual[7] ≈ before_residual[7] atol = atol
            @test after_residual[9] ≈ before_residual[9] atol = atol
            # Cell 8 is the one cell where the error moves: the parent loses 8
            # while the tags hold 2, so they empty and the 6 they could not pay
            # for surfaces in the residual. That is bounded, not amplified.
            @test after_residual[8] < before_residual[8]

            # Wherever the parent was positive the error moves by at most the
            # parent's own increment, in either direction. This is the property
            # the multiplicative rule did not have: it returned r * e, which
            # grows without bound when r > 1 persists.
            Δ = ᶜY.ρq_tot .- ᶜρq_tot_before
            moved = abs.(after_residual .- before_residual)
            positive_parent = ᶜρq_tot_before .> 0
            @test all(
                moved[positive_parent] .<=
                abs.(Δ[positive_parent]) .+ atol,
            )
            # Where the parent was not positive the tags are emptied instead, so
            # the whole of the new parent is the error. That branch is what a
            # nonnegativity constraint reaches, and it is bounded by the parent
            # rather than by what came before.
            @test all(
                isapprox.(
                    after_residual[.!positive_parent],
                    ᶜY.ρq_tot[.!positive_parent];
                    atol = atol,
                ),
            )
            # Either way the error ends no larger than the error already there
            # or the cell's own parent, whichever is bigger. Nothing in this
            # correction can take it past both.
            @test all(
                abs.(after_residual) .<=
                max.(abs.(before_residual), abs.(ᶜY.ρq_tot)) .+ atol,
            )

            # A tag that transport has driven negative is left alone, for
            # `repair_water_tag_partition!` to absorb into the positive tags.
            # Scaling it would have made it more negative.
            @test ᶜY.ρq_tag_tropics[9] == before_tropics[9]

            # The ledger records the signed correction applied to each tag
            @test ᶜfix.ρq_tag_tropics ≈ ᶜY.ρq_tag_tropics .- before_tropics
            @test ᶜfix.ρq_tag_extratropics ≈
                  ᶜY.ρq_tag_extratropics .- before_extra
            @test ᶜfix.ρq_tag_tropics[1] < 0  # clipped down
            @test ᶜfix.ρq_tag_tropics[2] == 0 # untouched
            @test ᶜfix.ρq_tag_tropics[3] > 0  # borrowed up

            # The ledger accumulates across calls rather than being overwritten
            CA._rescale_water_tags!((; c = ᶜY), p, copy(ᶜY.ρq_tot), model)
            @test ᶜfix.ρq_tag_tropics ≈ ᶜY.ρq_tag_tropics .- before_tropics
        end

        @testset "Limiter rescale does not amplify the residual ($FT)" begin
            # The regression test for issue #64. A cell whose element minimum
            # sits above it is lifted by the SEM quasimonotone limiter every
            # stage, so the same ratio is applied over and over. Multiplying
            # the tags multiplied the closure error with them, at 1.4 per
            # application; after sixteen applications that is a factor of 220,
            # and after a simulated day it reached 1e113 while `ρq_tot` stayed
            # bounded. Adding the increment leaves the error where it was.
            tags = (
                CA.WaterTag{:tropics}(
                    CA.TanhLatitudeRegion(FT(20), FT(2), true),
                ),
                CA.WaterTag{:extratropics}(
                    CA.TanhLatitudeRegion(FT(20), FT(2), false),
                ),
            )
            model = CA.WaterTaggingModel(tags)
            ᶜY = (;
                ρq_tot = FT[10],
                ρq_tag_tropics = FT[3],
                ρq_tag_extratropics = FT[3],
            )
            p = (;
                tagging = (;
                    ᶜwater_fix = (;
                        ρq_tag_tropics = zeros(FT, 1),
                        ρq_tag_extratropics = zeros(FT, 1),
                    ),
                    ᶜwater_pos = zeros(FT, 1),
                ),
            )
            ᶜρq_tot_before = zeros(FT, 1)
            for _ in 1:16
                ᶜρq_tot_before .= ᶜY.ρq_tot
                ᶜY.ρq_tot .= FT(1.4) .* ᶜρq_tot_before
                CA._rescale_water_tags!(
                    (; c = ᶜY),
                    p,
                    ᶜρq_tot_before,
                    model,
                )
            end
            residual =
                ᶜY.ρq_tot[1] - ᶜY.ρq_tag_tropics[1] -
                ᶜY.ρq_tag_extratropics[1]
            # The error started at 10 - 6 = 4 and stays there. The tolerance is
            # loose because the parent has grown by 1.4^16 by now and Float32
            # rounding at that magnitude is not negligible against 4. Under the
            # rule this replaced the error would be 4 * 1.4^16, about 870.
            @test residual ≈ FT(4) rtol = 1e-2
            @test residual < FT(8)
            # Bounded by the cell's own parent, which is the property the
            # diverged run lost: there the tags reached 1e130 against a parent
            # of 1.6e16.
            @test abs(residual) <= ᶜY.ρq_tot[1]
            @test ᶜY.ρq_tag_tropics[1] > 0
            @test ᶜY.ρq_tag_tropics[1] < ᶜY.ρq_tot[1]
        end

        @testset "Partition repair ($FT)" begin
            tropics = CA.WaterTag{:tropics}(
                CA.TanhLatitudeRegion(FT(20), FT(2), true),
            )
            extratropics = CA.WaterTag{:extratropics}(
                CA.TanhLatitudeRegion(FT(20), FT(2), false),
            )
            evap = CA.WaterTag{:evap}(nothing, :surface_flux)
            tags = (tropics, extratropics, evap)

            @test CA.water_tag_repair_factor(FT(6), FT(-2)) ≈ FT(2) / FT(3)
            @test CA.water_tag_repair_factor(FT(1), FT(-3)) == FT(0)
            @test CA.water_tag_repair_factor(FT(0), FT(-1)) == FT(0)

            ᶜY = (;
                ρq_tot = FT[4, 0, 4],
                ρq_tag_tropics = FT[6, 1, 2],
                ρq_tag_extratropics = FT[-2, -3, 2],
                ρq_tag_evap = FT[-1, 3, 1],
            )
            ᶜwater_fix = (;
                ρq_tag_tropics = fill(FT(0.5), 3),
                ρq_tag_extratropics = fill(FT(0.5), 3),
                ρq_tag_evap = fill(FT(0.5), 3),
            )
            before_tropics = copy(ᶜY.ρq_tag_tropics)
            before_extra = copy(ᶜY.ρq_tag_extratropics)
            before_evap = copy(ᶜY.ρq_tag_evap)
            p = (;
                tagging = (;
                    ᶜwater_fix,
                    ᶜwater_pos = zeros(FT, 3),
                    ᶜwater_neg = zeros(FT, 3),
                ),
            )

            CA._repair_water_tag_partition!(
                (; c = ᶜY),
                p,
                CA.WaterTaggingModel(tags),
            )

            # A feasible signed sum is preserved while all partition tags are
            # made non-negative. If negatives exceed positives, both are zero.
            @test ᶜY.ρq_tag_tropics[1] + ᶜY.ρq_tag_extratropics[1] ≈
                  before_tropics[1] + before_extra[1]
            @test all(>=(0), ᶜY.ρq_tag_tropics)
            @test all(>=(0), ᶜY.ρq_tag_extratropics)
            @test ᶜY.ρq_tag_tropics[2] == FT(0)
            @test ᶜY.ρq_tag_extratropics[2] == FT(0)
            # Source tags are outside the partition and remain unchanged.
            @test ᶜY.ρq_tag_evap == before_evap
            @test ᶜwater_fix.ρq_tag_evap == fill(FT(0.5), 3)
            # Corrections accumulate on top of the existing fix ledger.
            @test ᶜwater_fix.ρq_tag_tropics ≈
                  fill(FT(0.5), 3) .+ ᶜY.ρq_tag_tropics .- before_tropics
            @test ᶜwater_fix.ρq_tag_extratropics ≈
                  fill(FT(0.5), 3) .+ ᶜY.ρq_tag_extratropics .- before_extra
        end

        @testset "Sedimentation shares ($FT)" begin
            region_tag = CA.WaterTag{:tropics}(
                CA.TanhLatitudeRegion(FT(20), FT(2), true),
            )
            source_tag = CA.WaterTag{:evap}(nothing, :surface_flux)
            region_and_source_tag = CA.WaterTag{:evap_tropics}(
                CA.TanhLatitudeRegion(FT(20), FT(2), true),
                :surface_flux,
            )

            # Only a region tag with no sources belongs to the partition whose
            # shares are renormalized. Resolved on the tag's type.
            @test CA._is_partition_tag(region_tag)
            @test !CA._is_partition_tag(source_tag)
            @test !CA._is_partition_tag(region_and_source_tag)

            # A partition share is the clamped donor share over the norm
            @test CA.water_tag_sediment_share(FT(2), FT(8), FT(0.5)) == FT(0.5)
            # Renormalization is what restores closure once the tags have
            # drifted: two tags holding 3 and 3 of 8 have raw shares summing to
            # 0.75, and normalized shares summing to exactly 1
            norm = FT(0.75)
            s1 = CA.water_tag_sediment_share(FT(3), FT(8), norm)
            s2 = CA.water_tag_sediment_share(FT(3), FT(8), norm)
            @test s1 + s2 ≈ one(FT)
            # Never amplifies: each clamped share is a term of the norm, so the
            # result stays within [0, 1] however small the norm gets
            @test CA.water_tag_sediment_share(FT(1e-9), FT(8), FT(1e-9 / 8)) ≈
                  one(FT)
            @test CA.water_tag_sediment_share(FT(2), FT(8), FT(1)) <= one(FT)
            # No tagged water to sediment, and no division by zero
            @test CA.water_tag_sediment_share(FT(2), FT(8), FT(0)) == FT(0)
            @test isfinite(CA.water_tag_sediment_share(FT(2), FT(8), FT(0)))
            @test CA.water_tag_sediment_share(FT(1), FT(0), FT(1)) == FT(0)

            # A source tag is not in the partition, so its share is its own
            # clamped donor share, unnormalized
            @test CA.water_tag_source_sediment_share(FT(2), FT(8)) == FT(0.25)
            @test CA.water_tag_source_sediment_share(FT(9), FT(8)) == FT(1)
            @test CA.water_tag_source_sediment_share(FT(-1), FT(8)) == FT(0)
            @test CA.water_tag_source_sediment_share(FT(1), FT(0)) == FT(0)

            # Derivatives used by the implicit sedimentation Jacobian.
            # Interior of the clamp, partition tag: the (1 - φ̂) factor means a
            # tag that already owns all the local water cannot grow its share
            @test CA.water_tag_sediment_dshare(FT(2), FT(8), FT(1)) ≈
                  (1 - FT(0.25)) / (FT(8) * FT(1))
            @test CA.water_tag_sediment_dshare(FT(8), FT(8), FT(1)) == FT(0)
            # Zero wherever the clamp is active, matching the tendency
            @test CA.water_tag_sediment_dshare(FT(-1), FT(8), FT(1)) == FT(0)
            @test CA.water_tag_sediment_dshare(FT(9), FT(8), FT(1)) == FT(0)
            # Guards
            @test CA.water_tag_sediment_dshare(FT(2), FT(0), FT(1)) == FT(0)
            @test CA.water_tag_sediment_dshare(FT(2), FT(8), FT(0)) == FT(0)
            @test isfinite(CA.water_tag_sediment_dshare(FT(2), FT(8), FT(0)))

            @test CA.water_tag_source_sediment_dshare(FT(2), FT(8)) ≈
                  inv(FT(8))
            @test CA.water_tag_source_sediment_dshare(FT(-1), FT(8)) == FT(0)
            @test CA.water_tag_source_sediment_dshare(FT(9), FT(8)) == FT(0)
            @test CA.water_tag_source_sediment_dshare(FT(2), FT(0)) == FT(0)
        end

        @testset "Sedimentation share norm ($FT)" begin
            # The norm sums the clamped shares of the partition tags only: a
            # source tag holds real water, but it is not a partition member and
            # including it would make the normalized shares sum to less than 1.
            tags = (
                CA.WaterTag{:tropics}(
                    CA.TanhLatitudeRegion(FT(20), FT(2), true),
                ),
                CA.WaterTag{:extratropics}(
                    CA.TanhLatitudeRegion(FT(20), FT(2), false),
                ),
                CA.WaterTag{:evap}(nothing, :surface_flux),
            )
            ᶜY = (;
                ρq_tot = FT[8, 8, 8, 8],
                # Cell 1 partitions exactly; cell 2 has drifted low; cell 3 has
                # a negative tag that the clamp removes; cell 4 is all empty
                ρq_tag_tropics = FT[6, 3, -1, 0],
                ρq_tag_extratropics = FT[2, 3, 6, 0],
                ρq_tag_evap = FT[4, 4, 4, 4],
            )
            ᶜnorm = zeros(FT, 4)
            CA._accumulate_share_norm!(ᶜnorm, ᶜY, tags)

            # The source tag is excluded, so cell 1 sums to exactly 1
            @test ᶜnorm ≈ FT[1, 0.75, 0.75, 0]

            # Normalized partition shares sum to 1 wherever the norm is
            # positive — this is the property the mirrored flux relies on
            for i in 1:3
                s =
                    CA.water_tag_sediment_share(
                        ᶜY.ρq_tag_tropics[i], ᶜY.ρq_tot[i], ᶜnorm[i],
                    ) + CA.water_tag_sediment_share(
                        ᶜY.ρq_tag_extratropics[i], ᶜY.ρq_tot[i], ᶜnorm[i],
                    )
                @test s ≈ one(FT)
            end
            # Where every tag is empty there is nothing to sediment, so the
            # shares are zero and the discrepancy surfaces in `q_tag_res`
            @test CA.water_tag_sediment_share(
                ᶜY.ρq_tag_tropics[4], ᶜY.ρq_tot[4], ᶜnorm[4],
            ) == FT(0)
        end
    end

    @testset "AtmosModel integration" begin
        model = CA.AtmosModel()
        @test isnothing(model.water_tagging_model)
        @test isnothing(model.tagging.water_tagging_model)

        tags = (CA.WaterTag{:evap}(nothing, :surface_flux),)
        model = CA.AtmosModel(; water_tagging_model = CA.WaterTaggingModel(tags))
        @test model.water_tagging_model isa CA.WaterTaggingModel
        @test CA.tag_name(model.water_tagging_model.tags[1]) == :evap
        # The two families are independent
        @test isnothing(model.tagging_model)
    end

    @testset "Microphysics support guard" begin
        @test isnothing(
            CA.check_water_tagging_supported(CA.EquilibriumMicrophysics0M()),
        )
        # A dry model has no ρq_tot to partition
        @test_throws ErrorException CA.check_water_tagging_supported(
            CA.DryModel(),
        )
        # 1M moves ρq_tot by sedimentation, which the tags now mirror
        @test isnothing(
            CA.check_water_tagging_supported(
                CA.NonEquilibriumMicrophysics1M(),
            ),
        )
        # 2M and P3 add prognostic number concentrations, whose provenance is a
        # separate question from the mass provenance the tags partition
        @test_throws ErrorException CA.check_water_tagging_supported(
            CA.NonEquilibriumMicrophysics2M(),
        )
    end

    @testset "Diagnostics registration" begin
        tags = (
            CA.WaterTag{:tropics}(CA.TanhLatitudeRegion(20.0, 2.0, true)),
            CA.WaterTag{:evap}(nothing, :surface_flux),
        )
        @test isnothing(
            CA.Diagnostics.register_water_tagging_diagnostics!(nothing),
        )

        CA.Diagnostics.register_water_tagging_diagnostics!(
            CA.WaterTaggingModel(tags),
        )
        q_trop = CA.Diagnostics.get_diagnostic_variable("q_tag_tropics")
        qv_trop = CA.Diagnostics.get_diagnostic_variable("qv_tag_tropics")
        q_res = CA.Diagnostics.get_diagnostic_variable("q_tag_res")
        q_fix = CA.Diagnostics.get_diagnostic_variable("q_tag_fix_tropics")
        @test q_trop.units == "kg kg^-1"
        # The long names must not repeat the `hus` ambiguity between total
        # water and vapor
        @test occursin("Total Water", q_trop.long_name)
        @test occursin("Vapor", qv_trop.long_name)

        state = (;
            c = (;
                ρ = [2.0, 2.0],
                ρq_tot = [0.02, 0.02],
                ρq_tag_tropics = [0.008, 0.004],
                ρq_tag_evap = [0.002, 0.002],
            )
        )
        cache = (;
            precomputed = (; ᶜq_liq = [0.0, 0.0025], ᶜq_ice = [0.0, 0.0]),
            tagging = (; ᶜwater_fix = (; ρq_tag_tropics = [-0.002, 0.0])),
        )

        @test q_trop.compute!(nothing, state, cache, 0.0) == [0.004, 0.002]
        # Residual sums only the region tag, so the source tag is left out
        @test q_res.compute!(nothing, state, cache, 0.0) == [0.006, 0.008]
        @test q_fix.compute!(nothing, state, cache, 0.0) == [-0.001, 0.0]

        # Vapor share: all vapor in the first column, half condensed in the
        # second (ρq_liq = 2 * 0.0025 = 0.005 of ρq_tot = 0.02)
        @test qv_trop.compute!(nothing, state, cache, 0.0) ≈
              [0.004, 0.002 * 0.75]

        # Mutating form writes into `out`
        out = zeros(2)
        q_res.compute!(out, state, cache, 0.0)
        @test out == [0.006, 0.008]

        # Registration is idempotent for per-tag entries
        CA.Diagnostics.register_water_tagging_diagnostics!(
            CA.WaterTaggingModel(tags),
        )
        @test CA.Diagnostics.get_diagnostic_variable("q_tag_tropics") ===
              q_trop

        # Residual diagnostics belong to a model, while the diagnostic catalog
        # is global. Registering a source-only model has to clear the residual
        # an earlier model left behind, rather than keep its region-tag
        # closure.
        source_only_tags =
            (CA.WaterTag{:forced}(nothing, :external_forcing),)
        CA.Diagnostics.register_water_tagging_diagnostics!(
            CA.WaterTaggingModel(source_only_tags),
        )
        @test_throws ErrorException CA.Diagnostics.get_diagnostic_variable(
            "q_tag_res",
        )

        # A later region model installs a fresh residual over its own tags.
        # The earlier field stays in the state with a large value, so this
        # assertion also shows the stale `:ρq_tag_tropics` closure is gone.
        replacement_tags =
            (CA.WaterTag{:global}(CA.EntireDomain()),)
        CA.Diagnostics.register_water_tagging_diagnostics!(
            CA.WaterTaggingModel(replacement_tags),
        )
        replacement_q_res =
            CA.Diagnostics.get_diagnostic_variable("q_tag_res")
        @test replacement_q_res !== q_res
        replacement_state = (;
            c = (;
                ρ = [2.0, 2.0],
                ρq_tot = [0.02, 0.02],
                ρq_tag_global = [0.012, 0.016],
                ρq_tag_tropics = [10.0, 10.0],
            )
        )
        @test replacement_q_res.compute!(
            nothing,
            replacement_state,
            nothing,
            0.0,
        ) ≈ [0.004, 0.002]
    end

    @testset "Tagged name predicate" begin
        @test CA.is_water_tag_name(:ρq_tag_tropics)
        @test !CA.is_water_tag_name(:ρq_tot)
        @test !CA.is_water_tag_name(:ρe_tag_strat)
        @test CA.is_energy_tag_name(:ρe_tag_strat)
        @test !CA.is_energy_tag_name(:ρq_tag_tropics)
        # Both families are covered by the shared predicate, so both are
        # excluded from independent tracer limiting
        @test CA.is_tagged_tracer_name(:ρq_tag_tropics)
        @test CA.is_tagged_tracer_name(:ρe_tag_strat)
        @test !CA._should_apply_limiter_to_tracer(:ρq_tag_tropics, nothing)
        @test CA._should_apply_limiter_to_tracer(:ρq_tot, nothing)

        # A water tag must not be mistaken for a moisture species by the
        # process classification: it belongs on the passive path
        @test isnothing(
            CA.sedimentation_velocity_name(@name(ρq_tag_tropics)),
        )
        @test isnothing(CA.condensate_phase(@name(ρq_tag_tropics)))
    end
end
