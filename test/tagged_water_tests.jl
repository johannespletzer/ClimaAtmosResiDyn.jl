using Test
import ClimaAtmos as CA
import ClimaCore.MatrixFields: @name

# `AtmosModel` takes a grid. These tests read only the model's tagging fields,
# so the smallest column serves.
column_atmos_model(; kwargs...) =
    CA.AtmosModel(CA.ColumnGrid(Float64; z_elem = 10); kwargs...)

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
        model = column_atmos_model()
        @test isnothing(model.water_tagging_model)
        @test isnothing(model.tagging.water_tagging_model)

        tags = (CA.WaterTag{:evap}(nothing, :surface_flux),)
        model = column_atmos_model(; water_tagging_model = CA.WaterTaggingModel(tags))
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
        # The copies' residual and the leaks describe a partition too, so a
        # region model with copies registers them first, and the source-only
        # model with copies must clear them.
        CA.Diagnostics.register_water_tagging_diagnostics!(
            CA.WaterTaggingModel(tags; updraft_copies = true),
        )
        @test !isnothing(CA.Diagnostics.get_diagnostic_variable("q_tag_copy_res"))
        @test !isnothing(CA.Diagnostics.get_diagnostic_variable("q_tag_leak_vdiff"))
        # The residual's metadata no longer says the operators are identical.
        @test !occursin(
            "identical",
            CA.Diagnostics.get_diagnostic_variable("q_tag_res").comments,
        )
        CA.Diagnostics.register_water_tagging_diagnostics!(
            CA.WaterTaggingModel(source_only_tags; updraft_copies = true),
        )
        for short_name in (
            "q_tag_res",
            "q_tag_copy_res",
            "q_tag_leak_vdiff",
            "q_tag_leak_diffusion_up",
            "q_tag_upfix_forced",
        )
            @test_throws ErrorException CA.Diagnostics.get_diagnostic_variable(
                short_name,
            )
        end

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

# The water tags' restart guard. As the energy source tags' guard, it needs no
# simulation: a small checkpoint, and a model and a state that carry only what
# the check reads.
@testset "The water tags' restart guard" begin
    context = CA.ClimaComms.context()
    HDF5 = CA.InputOutput.HDF5
    tags(width = 100.0; sources = (:surface_flux,)) = (
        CA.WaterTag{:tropo}(CA.TanhAltitudeRegion(750.0, width, false)),
        CA.WaterTag{:strat}(CA.TanhAltitudeRegion(750.0, width, true)),
        CA.WaterTag{:evap}(nothing, sources),
    )
    water_model(; width = 100.0, sources = (:surface_flux,), copies = false) =
        CA.WaterTaggingModel(tags(width; sources); updraft_copies = copies)
    atmos(model) = (; water_tagging_model = model)
    names = (:ρq_tag_tropo, :ρq_tag_strat, :ρq_tag_evap)
    copy_names = (:q_tag_tropo, :q_tag_strat, :q_tag_evap)
    updraft(names...) = NamedTuple{(:ρa, names...)}(Tuple(zeros(1 + length(names))))
    state(names...; updrafts = ()) = (;
        c = (;
            NamedTuple{(:ρ, :ρq_tot, names...)}(Tuple(zeros(2 + length(names))))...,
            (isempty(updrafts) ? (;) : (; sgsʲs = updrafts))...,
        ),
    )
    tagged = state(names...)
    directory = mktempdir()
    function checkpoint(model, name; record = true, edit = file -> nothing)
        path = joinpath(directory, "$name.hdf5")
        writer = CA.InputOutput.HDF5Writer(path, context)
        record && CA.write_water_tag_checkpoint_attributes!(writer.file, model)
        edit(writer.file)
        Base.close(writer)
        return path
    end
    check(path, model, Y = tagged) =
        CA.check_water_tag_checkpoint(path, atmos(model), Y, context)

    written = checkpoint(water_model(), "written")
    # The same tags restart.
    @test isnothing(check(written, water_model()))
    # A changed region or source is refused, and the error names both.
    @test_throws r"water tag `tropo`.*width = 100\.0.*width = 200\.0" check(
        written,
        water_model(; width = 200.0),
    )
    @test_throws r"water tag `evap`.*sources `surface_flux`.*sources `none`" check(
        written,
        water_model(; sources = ()),
    )
    # A tag field missing from the file, or one the run does not configure.
    @test_throws r"water tags tropo, strat, and this run.*Missing from the file: evap" check(
        written,
        water_model(),
        state(:ρq_tag_tropo, :ρq_tag_strat),
    )
    @test_throws r"Not configured: tropo, strat, evap.*`water_tracers`" check(
        written,
        nothing,
    )
    # The copies: a changed `water_tag_updraft_copy` is refused either way.
    with_copies = state(names...; updrafts = (updraft(copy_names...),))
    without_copies = state(names...; updrafts = (updraft(),))
    @test isnothing(check(written, water_model(; copies = true), with_copies))
    @test isnothing(check(written, water_model(), without_copies))
    @test_throws r"updraft copies of the water tags none.*`water_tag_updraft_copy`" check(
        written,
        water_model(; copies = true),
        without_copies,
    )
    @test_throws r"Not configured: tropo, strat, evap.*`water_tag_updraft_copy`" check(
        written,
        water_model(),
        with_copies,
    )
    # A file with no updrafts does not pass a run with copies.
    @test_throws r"updraft copies of the water tags none" check(
        written,
        water_model(; copies = true),
    )
    # The increment's ledger: a changed `water_tag_transport` is refused either
    # way, since the ledger is in the file or is not.
    increment_model = CA.WaterTaggingModel(
        tags();
        transport = CA.IncrementWaterTagTransport(),
    )
    with_ledger =
        (; c = (; tagged.c..., q_tag_inc_left = 0.0, q_tag_inc_moved = 0.0))
    @test isnothing(check(written, increment_model, with_ledger))
    @test_throws r"water_tag_transport" check(written, increment_model)
    @test_throws r"water_tag_transport" check(
        written,
        water_model(),
        with_ledger,
    )

    # A checkpoint from before the guard is checked by its fields, with a
    # warning, and restarts.
    unrecorded = checkpoint(water_model(), "unrecorded"; record = false)
    @test_logs (:warn, r"written before") check(unrecorded, water_model())
    # A checkpoint in another version of the format is refused.
    newer = checkpoint(
        water_model(),
        "newer";
        edit = file -> begin
            HDF5.delete_attribute(file, "water_tag_checkpoint")
            HDF5.write_attribute(file, "water_tag_checkpoint", 2)
        end,
    )
    @test_throws r"version 2 of the checkpoint format.*reads version 1" check(
        newer,
        water_model(),
    )
    # A tag the file holds but records no definition for is refused.
    undefined = checkpoint(
        water_model(),
        "undefined";
        edit = file -> HDF5.delete_attribute(file, "water_tag.evap"),
    )
    @test_throws r"no definition for the water tag `evap`" check(
        undefined,
        water_model(),
    )
end

# The default mode's plume and the audit's blend factors, point by point. The
# EDMF column in `tagged_water_edmf_integration.jl` checks them in the model.
@testset "The water plume and the exchange's bound" begin
    partition = Val((true, true, false))
    step = CA.WaterPlumeStep(partition)
    # tropo, strat, and the source tag evap; the partition holds 0.008.
    ε̄ = (0.006, 0.002, 0.001)
    # The lowest level starts from the grid mean's composition, scaled so the
    # partition holds the updraft's water. The source tag keeps its share.
    start = step((NaN, NaN, NaN), (ε̄, 0.0, false, 0.010))
    @test start[1] + start[2] ≈ 0.010
    @test start[1] / start[2] ≈ 3
    @test start[3] / (start[1] + start[2]) ≈ ε̄[3] / (ε̄[1] + ε̄[2])
    # A level that mixes nothing keeps the composition and takes the new water.
    kept = step(start, ((0.001, 0.003, 0.0), 0.0, false, 0.012))
    @test kept[1] + kept[2] ≈ 0.012
    @test kept[1] / kept[2] ≈ 3
    # Full mixing takes the grid mean's composition.
    mixed = step(start, ((0.001, 0.003, 0.0), 1.0, false, 0.008))
    @test mixed[1] / mixed[2] ≈ 1 / 3
    @test mixed[1] + mixed[2] ≈ 0.008
    # Where the plume starts again, it takes the grid mean's composition.
    restarted = step(start, (ε̄, 0.5, true, 0.010))
    @test collect(restarted) ≈ collect(ε̄ .* (0.010 / 0.008))
    # Without water in the updraft the values are left as mixed.
    @test step(start, (ε̄, 0.5, false, 0.0)) ==
          CA._plume_step(start, (ε̄, 0.5, false))
    # A partition that holds a denormal amount is still scaled to finite
    # values: the share is taken before the water.
    tiny = step((NaN, NaN, NaN), ((1e-322, 1e-322, 0.0), 0.0, false, 0.010))
    @test all(isfinite, tiny)
    @test tiny[1] + tiny[2] ≈ 0.010

    # The audit's factors are those the exchange applies, and `-1` where it
    # does not run.
    factors = CA.WaterBlendFactors(partition)
    differences = CA.ShareDifferences(partition, false)
    @test factors(start, ε̄, -1.0, 1.0) == (-1.0, -1.0, -1.0)
    @test factors(start, ε̄, 1.0, 0.0) == (-1.0, -1.0, -1.0)
    # The same composition leaves nothing to bound.
    @test factors(ε̄ .* 2, ε̄, 0.5, 1.0) == (1.0, 1.0, 1.0)
    @test all(abs.(differences(ε̄ .* 2, ε̄, 0.5, 1.0)) .< 1e-16)
    # A plume far richer in `tropo` than the grid mean, with little room,
    # binds the partition's common factor below one.
    rich = (0.0099, 0.0001, 0.001)
    θ = factors(rich, ε̄, 0.05, 1.0)
    @test 0 <= θ[1] < 1
    @test θ[1] == θ[2]
    unbound = differences(rich, ε̄, Inf, 1.0)
    bound = differences(rich, ε̄, 0.05, 1.0)
    @test bound[1] ≈ θ[1] * unbound[1]

    # The copies' sedimentation Jacobian: the falling share's derivative.
    @test CA.water_tag_copy_fall_share_derivative(0.002, 0.010) ≈ 0.2
    @test CA.water_tag_copy_fall_share_derivative(0.002, 0.0) == 0
end

# The default mode's exchange needs region tags that partition the domain. It
# reads only the masks, so plain vectors stand in for the fields.
@testset "The exchange needs a region partition" begin
    edmf = CA.PrognosticEDMFX{1, true}(1e-5)
    region(above) = CA.TanhAltitudeRegion(750.0, 100.0, above)
    tags = (
        CA.WaterTag{:tropo}(region(false)),
        CA.WaterTag{:strat}(region(true)),
        CA.WaterTag{:evap}(nothing, (:surface_flux,)),
    )
    atmos(model; sgs_mass_flux = true) = (;
        water_tagging_model = model,
        turbconv_model = edmf,
        edmfx_model = (; sgs_mass_flux),
    )
    masks(tropo, strat) = (; ᶜwater_masks = (; ρq_tag_tropo = tropo, ρq_tag_strat = strat))
    closed = masks([1.0, 0.5, 0.0], [0.0, 0.5, 1.0])
    gap = masks([1.0, 0.3, 0.0], [0.0, 0.5, 1.0])
    model = CA.WaterTaggingModel(tags)
    @test isnothing(CA.check_water_tag_exchange_partition(closed, atmos(model)))
    @test_throws r"masks sum to 1\s+only to within" CA.check_water_tag_exchange_partition(
        gap,
        atmos(model),
    )
    # Without region tags there is nothing to exchange.
    sources_only = CA.WaterTaggingModel((tags[3],))
    @test_throws r"These tags have\s+none" CA.check_water_tag_exchange_partition(
        (; ᶜwater_masks = (;)),
        atmos(sources_only),
    )
    # The copies, and a run without the SGS mass flux, need no partition.
    copies = CA.WaterTaggingModel(tags; updraft_copies = true)
    @test isnothing(CA.check_water_tag_exchange_partition(gap, atmos(copies)))
    @test isnothing(
        CA.check_water_tag_exchange_partition(
            gap,
            atmos(model; sgs_mass_flux = false),
        ),
    )
end

# The copies' names come from the model's type. The Jacobian asks for them in
# every update of every EDMF run, so the call must infer and not allocate.
@testset "The copies' names are a constant" begin
    tags = (
        CA.WaterTag{:tropo}(CA.TanhAltitudeRegion(750.0, 100.0, false)),
        CA.WaterTag{:evap}(nothing, (:surface_flux,)),
    )
    copies = CA.WaterTaggingModel(tags; updraft_copies = true)
    plain = CA.WaterTaggingModel(tags)
    names = @inferred CA.water_tag_copy_sgs_names(copies)
    @test names == (
        CA.MatrixFields.FieldName(:q_tag_tropo),
        CA.MatrixFields.FieldName(:q_tag_evap),
    )
    @test (@inferred CA.water_tag_copy_sgs_names(plain)) == ()
    @test (@inferred CA.water_tag_copy_sgs_names(nothing)) == ()
    CA.water_tag_copy_sgs_names(copies)
    @test (@allocated CA.water_tag_copy_sgs_names(copies)) == 0
end

# `water_tag_transport: increment`: the key, the model's refusals, the stepper
# check it shares with the energy source tags, and the one hook both families'
# corrections run in. The correction itself runs in
# `tagged_water_increment_integration.jl`.
@testset "The water tags following the implicit increment" begin
    CTS = CA.CTS
    region(above) = CA.TanhAltitudeRegion(750.0, 100.0, above)
    tags = (
        CA.WaterTag{:tropo}(region(false)),
        CA.WaterTag{:strat}(region(true)),
        CA.WaterTag{:evap}(nothing, (:surface_flux,)),
    )

    @testset "The key" begin
        @test CA.water_tag_transport_from_config("tracer") isa
              CA.TracerWaterTagTransport
        @test CA.water_tag_transport_from_config(nothing) isa
              CA.TracerWaterTagTransport
        @test CA.water_tag_transport_from_config("increment") isa
              CA.IncrementWaterTagTransport
        @test_throws r"must be `tracer` or `increment`" CA.water_tag_transport_from_config(
            "enthalpy",
        )
        increment = CA.WaterTaggingModel(
            tags;
            transport = CA.IncrementWaterTagTransport(),
        )
        @test CA.follows_water_increment(increment)
        @test !CA.follows_water_increment(CA.WaterTaggingModel(tags))
        @test !CA.follows_water_increment(nothing)
        @test CA.water_tag_increment_ledger_names(increment) ==
              (:q_tag_inc_left, :q_tag_inc_moved)
        @test CA.water_tag_increment_ledger_names(CA.WaterTaggingModel(tags)) ==
              ()
        @test CA.water_tag_increment_ledger_variables(1.0, increment) ==
              (; q_tag_inc_left = 0.0, q_tag_inc_moved = 0.0)
        @test CA.water_tag_increment_ledger_variables(1.0, nothing) == (;)
        # The ledger's names are not tracers, so no transport reaches them,
        # and the reserved tag names keep the diagnostics apart.
        @test !CA.is_tracer_var(:q_tag_inc_left)
        @test CA.is_water_tag_ledger_name(:q_tag_inc_moved)
        @test !CA.is_water_tag_ledger_name(:ρq_tag_tropo)
        # The copies and the increment go together.
        @test CA.follows_water_increment(
            CA.WaterTaggingModel(
                tags;
                updraft_copies = true,
                transport = CA.IncrementWaterTagTransport(),
            ),
        )
    end

    # The owner's review of #102, point 4: on two equal cells with mismatch
    # (1, -0.1), spreading the column's total by |m| leaves out (0.818,
    # 0.082) and moves (0.182, -0.182), more than the second cell's mismatch.
    # By the same-sign rule it leaves out (0.9, 0) and moves (0.1, -0.1).
    @testset "The part left out goes where the mismatch has its sign" begin
        for m in ([1.0, -0.1], [-1.0, 0.1], [0.3, 0.3], [0.5, -0.5])
            M = sum(m)
            weight = CA.water_increment_left_weight.(m, M)
            left = sum(weight) > 0 ? M .* weight ./ sum(weight) : zero(m)
            moved = m .- left
            @test sum(left) ≈ M atol = 1e-15
            @test abs(sum(moved)) < 1e-15
            @test all(abs.(moved) .<= abs.(m) .+ 1e-15)
            @test all(left .* m .>= 0)
        end
        m = [1.0, -0.1]
        weight = CA.water_increment_left_weight.(m, sum(m))
        @test sum(m) .* weight ./ sum(weight) ≈ [0.9, 0.0]
    end

    @testset "The model's refusals" begin
        # Without a partition the source tags would take the parent's whole
        # implicit transport.
        @test_throws r"needs region tags without\s+sources" CA.WaterTaggingModel(
            (tags[3],);
            transport = CA.IncrementWaterTagTransport(),
        )
        model = CA.WaterTaggingModel(
            tags;
            transport = CA.IncrementWaterTagTransport(),
        )
        masks(tropo, strat) =
            (; ρq_tag_tropo = tropo, ρq_tag_strat = strat)
        names = CA.water_region_tag_state_names(model)
        @test isnothing(
            CA._check_water_increment_partition(
                masks([1.0, 0.5, 0.0], [0.0, 0.5, 1.0]),
                names,
                model,
            ),
        )
        @test_throws r"sum to 1 only to within" CA._check_water_increment_partition(
            masks([1.0, 0.3, 0.0], [0.0, 0.5, 1.0]),
            names,
            model,
        )
        # A uniform gap of half a percent, 2.5 times the closure budget, is
        # refused too (the owner's review of #102).
        @test_throws r"sum to 1 only to within" CA._check_water_increment_partition(
            masks([0.5, 0.5, 0.5], [0.495, 0.495, 0.495]),
            names,
            model,
        )
        # A region and its complement, as the model builds them on a column,
        # pass in both float types.
        for FT in (Float32, Float64)
            column_region(above) =
                CA.TanhAltitudeRegion(FT(750), FT(100), above)
            column_tags = (
                CA.WaterTag{:tropo}(column_region(false)),
                CA.WaterTag{:strat}(column_region(true)),
            )
            column_model = CA.WaterTaggingModel(
                column_tags;
                transport = CA.IncrementWaterTagTransport(),
            )
            ᶜcoordinates = CA.Fields.coordinate_field(
                CA.ClimaCore.CommonSpaces.ColumnSpace(
                    FT;
                    z_min = 0,
                    z_max = 1500,
                    z_elem = 64,
                    staggering = CA.ClimaCore.CommonSpaces.CellCenter(),
                ),
            )
            column_masks = CA._tag_masks(ᶜcoordinates, column_tags)
            @test isnothing(
                CA._check_water_increment_partition(
                    column_masks,
                    CA.water_region_tag_state_names(column_model),
                    column_model,
                ),
            )
            @test CA.water_increment_partition_tolerance(FT) == 100 * eps(FT)
        end
        # The default transport only warns about a gap, elsewhere.
        @test isnothing(
            CA._check_water_increment_partition(
                masks([1.0, 0.3, 0.0], [0.0, 0.5, 1.0]),
                names,
                CA.WaterTaggingModel(tags),
            ),
        )
    end

    @testset "The stepper check, shared with the energy source tags" begin
        # 0M, stepped implicitly: the explicit-1M refusal does not apply.
        atmos(transport) = (;
            water_tagging_model = CA.WaterTaggingModel(tags; transport),
            microphysics_model = CA.EquilibriumMicrophysics0M(),
            microphysics_tendency_timestepping = CA.Implicit(),
        )
        increment = atmos(CA.IncrementWaterTagTransport())
        newton = CTS.NewtonsMethod()
        imex(tableau) = CTS.IMEXAlgorithm(tableau, newton)
        T_imp! = (Yₜ, Y, p, t) -> nothing
        post = (dY, U, p, t) -> nothing
        check = CA.check_water_tag_increment_supported
        # ARS222, which the tagging experiments run, and ARS343, the default,
        # solve every stage they use.
        for tableau in (CTS.ARS222(), CTS.ARS343(), CTS.SSP222())
            @test isnothing(CA.implicit_increment_gap(imex(tableau), T_imp!))
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
        # Without the parent's own post-solve correction the hook would
        # change the model.
        @test_throws r"no post-solve correction of its own" check(
            increment,
            imex(CTS.ARS343()),
            T_imp!,
            nothing,
        )
        # The default transport is never refused.
        @test isnothing(
            check(
                atmos(CA.TracerWaterTagTransport()),
                imex(CTS.SSP333()),
                T_imp!,
                nothing,
            ),
        )
        @test isnothing(
            check((; water_tagging_model = nothing), imex(CTS.SSP333()), T_imp!, nothing),
        )
    end

    @testset "One hook for both families" begin
        post = (dY, U, p, t) -> nothing
        water = CA.WaterTaggingModel(
            tags;
            transport = CA.IncrementWaterTagTransport(),
        )
        energy_tags = (
            CA.EnergySourceTag{:strat}(region(true)),
            CA.EnergySourceTag{:tropo}(region(false)),
        )
        energy = CA.EnergySourceTaggingModel(
            energy_tags,
            50000.0;
            transport = CA.EnthalpyIncrementEnergySourceTransport(),
        )
        both = CA.tag_post_implicit(
            post,
            (; energy_source_tagging_model = energy, water_tagging_model = water),
        )
        @test both isa CA.WaterTagIncrementCorrection{
            <:CA.EnergySourceIncrementCorrection{typeof(post)},
        }
        @test CA.tag_post_implicit(
            post,
            (; energy_source_tagging_model = nothing, water_tagging_model = water),
        ) isa CA.WaterTagIncrementCorrection{typeof(post)}
        # Without either family the parent's correction is the hook, as it is.
        @test CA.tag_post_implicit(
            post,
            (;
                energy_source_tagging_model = nothing,
                water_tagging_model = CA.WaterTaggingModel(tags),
            ),
        ) === post
        @test isnothing(
            CA.tag_post_implicit(
                nothing,
                (; energy_source_tagging_model = nothing, water_tagging_model = nothing),
            ),
        )
    end
end

# WP5b: a water tag's sedimentation cross blocks to a falling species. The tag
# stays uncoupled, is solved after the coupled fields by back-substitution, and
# the coupled fields' increments do not change.
@testset "The split solver back-substitutes a tag's cross block" begin
    CC = CA.ClimaCore
    MF = CA.MatrixFields
    for FT in (Float32, Float64)
        column(staggering) = CC.CommonSpaces.ColumnSpace(
            FT;
            z_min = 0,
            z_max = 1000,
            z_elem = 12,
            staggering,
        )
        ᶜspace = column(CC.CommonSpaces.CellCenter())
        ᶠspace = column(CC.CommonSpaces.CellFace())
        ᶜnames = (:ρ, :ρe_tot, :ρq_rai, :ρq_tag_tropo)
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
        fill_pattern!(values, shift) =
            values .=
                sin.(shift .+ FT(0.7) .* reshape(1:length(values), size(values)))
        R = similar(Y)
        fill_pattern!(parent(R.c), 0)
        fill_pattern!(parent(R.f), 1)
        function band_block(space, row_type, diagonal, shift)
            block = fill(zero(row_type), space)
            n_levels = size(parent(block), 1)
            values = reshape(parent(block), n_levels, :)
            fill_pattern!(values, shift)
            values .*= FT(0.1)
            n_entries = size(values, 2)
            isodd(n_entries) && (values[:, (n_entries + 1) ÷ 2] .+= diagonal)
            if n_entries > 1
                values[1, 1] = 0
                values[end, end] = 0
            end
            return block
        end
        ᶜdiagonal(shift) =
            band_block(ᶜspace, MF.DiagonalMatrixRow{FT}, -1, shift)
        ᶜtridiagonal(shift, diagonal = -1) =
            band_block(ᶜspace, MF.TridiagonalMatrixRow{FT}, diagonal, shift)
        ᶠtridiagonal(shift) =
            band_block(ᶠspace, MF.TridiagonalMatrixRow{FT}, -1, shift)
        ᶜᶠbidiagonal(shift) =
            band_block(ᶜspace, MF.BidiagonalMatrixRow{FT}, 0, shift)
        ᶠᶜbidiagonal(shift) =
            band_block(ᶠspace, MF.BidiagonalMatrixRow{FT}, 0, shift)
        c(n) = MF.FieldName(:c, n)
        u₃ = CA.MatrixFields.@name(f.u₃)
        plain_pairs = (
            (c(:ρ), c(:ρ)) => ᶜdiagonal(2),
            (c(:ρe_tot), c(:ρe_tot)) => ᶜdiagonal(3),
            # Diagonal, as the direct arrowhead solve needs for its first group.
            (c(:ρq_rai), c(:ρq_rai)) => ᶜdiagonal(4),
            (c(:ρ), u₃) => ᶜᶠbidiagonal(5),
            (c(:ρe_tot), u₃) => ᶜᶠbidiagonal(6),
            (u₃, c(:ρ)) => ᶠᶜbidiagonal(7),
            (u₃, c(:ρe_tot)) => ᶠᶜbidiagonal(8),
            (u₃, u₃) => ᶠtridiagonal(9),
            (c(:ρq_tag_tropo), c(:ρq_tag_tropo)) => ᶜtridiagonal(10),
        )
        # Under prognostic EDMF a species' row names `u₃` too.
        model_pairs = (plain_pairs..., (c(:ρq_rai), u₃) => ᶜᶠbidiagonal(13))
        cross = (c(:ρq_tag_tropo), c(:ρq_rai)) => ᶜtridiagonal(11, 0)
        with_cross = (model_pairs..., cross)
        # The tag stays uncoupled with a block to a coupled column in its own
        # row.
        @test CA.uncoupled_jacobian_names(with_cross) == (c(:ρq_tag_tropo),)
        # A block that names the tag in another row, or a column block to
        # another splittable field, makes it coupled. So does a column that
        # contains the tag, such as `@name(c)`.
        @test isempty(
            CA.uncoupled_jacobian_names((
                with_cross...,
                (c(:ρq_rai), c(:ρq_tag_tropo)) => ᶜtridiagonal(12, 0),
            )),
        )
        @test isempty(
            CA.uncoupled_jacobian_names((
                with_cross...,
                (c(:ρq_tag_tropo), MF.FieldName(:c)) => ᶜtridiagonal(12, 0),
            )),
        )

        velocity_alg = MF.BlockLowerTriangularSolve(u₃)
        iterative_alg(n_iters) = MF.ApproximateBlockArrowheadIterativeSolve(
            c(:ρ),
            c(:ρe_tot),
            c(:ρq_rai);
            alg₂ = velocity_alg,
            P_alg₁ = MF.MainDiagonalPreconditioner(),
            n_iters,
        )
        direct_alg = MF.BlockArrowheadSolve(
            c(:ρ),
            c(:ρe_tot),
            c(:ρq_rai);
            alg₂ = velocity_alg,
        )
        function split_solver(pairs, alg)
            matrix = MF.FieldMatrix(pairs...)
            return CA.split_jacobian_solver(
                matrix,
                Y,
                alg,
                CA.uncoupled_jacobian_names(pairs),
            )
        end
        function increments(solver)
            ΔY = zero(Y)
            CA.LinearAlgebra.ldiv!(ΔY, solver, R)
            return ΔY
        end
        tolerance = 1000 * eps(FT)
        for alg in (iterative_alg(2), direct_alg)
            solver = split_solver(with_cross, alg)
            ΔY = increments(solver)
            ΔY_plain = increments(split_solver(model_pairs, alg))
            # The coupled fields' increments are those without the cross
            # block.
            for n in (:ρ, :ρe_tot, :ρq_rai)
                @test isequal(
                    parent(getproperty(ΔY.c, n)),
                    parent(getproperty(ΔY_plain.c, n)),
                )
            end
            @test isequal(parent(ΔY.f), parent(ΔY_plain.f))
            # The tag solves its own row: D Δtag + C Δρq_rai = R_tag.
            D = plain_pairs[end].second
            C = cross.second
            residual =
                @. D * ΔY.c.ρq_tag_tropo + C * ΔY.c.ρq_rai - R.c.ρq_tag_tropo
            @test maximum(abs, parent(residual)) <=
                  tolerance * maximum(abs, parent(R.c.ρq_tag_tropo))
            # And it differs from the solve without the cross block.
            @test !isapprox(
                parent(ΔY.c.ρq_tag_tropo),
                parent(ΔY_plain.c.ρq_tag_tropo),
            )
            # Repeated solves allocate nothing (Julia 1.10 allocates in the
            # split solve, as `energy_source_tags_integration.jl` records).
            ΔY_again = zero(Y)
            CA.LinearAlgebra.ldiv!(ΔY_again, solver, R)
            bytes = @allocated CA.LinearAlgebra.ldiv!(ΔY_again, solver, R)
            @test bytes <= 64 skip = VERSION < v"1.11"
        end

        # Without a species-`u₃` block the unsplit nested solve can take the
        # cross block too. Its coupled increments are the split's, and so is
        # its tag's, to rounding, at every iteration count.
        # (Under prognostic EDMF a species' row does name `u₃`, and the
        # unsplit form does not carry the cross blocks; see `_derivative_flags`.)
        plain_with_cross = (plain_pairs..., cross)
        split_reference = increments(split_solver(plain_with_cross, direct_alg))
        tag_differences = map((1, 2, 4)) do n_iters
            unsplit = MF.FieldMatrixWithSolver(
                MF.FieldMatrix(plain_with_cross...),
                Y,
                iterative_alg(n_iters),
            )
            ΔY_unsplit = zero(Y)
            CA.LinearAlgebra.ldiv!(ΔY_unsplit, unsplit, R)
            split = increments(split_solver(plain_with_cross, iterative_alg(n_iters)))
            for n in (:ρ, :ρe_tot, :ρq_rai)
                @test isapprox(
                    parent(getproperty(ΔY_unsplit.c, n)),
                    parent(getproperty(split.c, n));
                    rtol = tolerance,
                )
            end
            @test isapprox(parent(ΔY_unsplit.f), parent(split.f); rtol = tolerance)
            maximum(
                abs,
                parent(ΔY_unsplit.c.ρq_tag_tropo) .-
                parent(split_reference.c.ρq_tag_tropo),
            )
        end
        @info "The unsplit tag against the split's" FT tag_differences
        @test maximum(tag_differences) <=
              sqrt(eps(FT)) * maximum(abs, parent(split_reference.c.ρq_tag_tropo))
    end
end

@testset "The tags' sedimentation cross blocks, assembled" begin
    # The real blocks, from `update_sedimentation_jacobian!` on a small column,
    # with a cache that holds what it reads. Each tag's cross block is checked
    # against a finite difference of the tags' real sedimentation tendency
    # (`_sediment_water_tags!`) in the falling species, at fixed `ρq_tot`, `ρ`
    # and terminal velocity. The partition's blocks are checked against the
    # parent's. The partition has drifted, so its shares are renormalized, and
    # clamps bind in three cells.
    CC = CA.ClimaCore
    MF = CA.MatrixFields
    Geometry = CC.Geometry
    for FT in (Float32, Float64)
        column(staggering) = CC.CommonSpaces.ColumnSpace(
            FT;
            z_min = 0,
            z_max = 2000,
            z_elem = 16,
            staggering,
        )
        ᶜspace = column(CC.CommonSpaces.CellCenter())
        ᶠspace = column(CC.CommonSpaces.CellFace())
        ᶜz = CC.Fields.coordinate_field(ᶜspace).z
        region(above) = CA.TanhAltitudeRegion(FT(750), FT(100), above)
        tags = (
            CA.WaterTag{:tropo}(region(false)),
            CA.WaterTag{:strat}(region(true)),
            CA.WaterTag{:evap}(nothing, :surface_flux),
        )
        model = CA.WaterTaggingModel(tags)
        masses = (:ρq_lcl, :ρq_icl, :ρq_rai, :ρq_sno)
        velocities = (:ᶜwₗ, :ᶜwᵢ, :ᶜwᵣ, :ᶜwₛ)
        ᶜnames = (
            :ρ,
            :ρe_tot,
            :ρq_tot,
            masses...,
            :ρq_tag_tropo,
            :ρq_tag_strat,
            :ρq_tag_evap,
        )
        Y = CC.Fields.FieldVector(;
            c = similar(
                CC.Fields.coordinate_field(ᶜspace),
                NamedTuple{ᶜnames, NTuple{length(ᶜnames), FT}},
            ),
            f = similar(
                CC.Fields.coordinate_field(ᶠspace),
                NamedTuple{(:u₃,), Tuple{FT}},
            ),
        )
        fill!(parent(Y.f), 0)
        @. Y.c.ρ = FT(1.2) * exp(-(ᶜz) / 8000)
        @. Y.c.ρe_tot = Y.c.ρ * FT(2.5e5)
        @. Y.c.ρq_tot = Y.c.ρ * (FT(0.012) - FT(4e-6) * ᶜz)
        @. Y.c.ρq_lcl = Y.c.ρ * FT(2e-4) * (1 + sin(ᶜz / 300))
        @. Y.c.ρq_icl = Y.c.ρ * FT(5e-5) * (1 + cos(ᶜz / 400))
        @. Y.c.ρq_rai = Y.c.ρ * FT(3e-4) * (1 + sin(ᶜz / 200 + 1))
        @. Y.c.ρq_sno = Y.c.ρ * FT(1e-4) * (1 + cos(ᶜz / 250 + 2))
        # A drifted partition: `tropo` holds 10% too much, `strat` 5% too
        # little.
        ᶜbelow = @. (1 - tanh((ᶜz - 750) / 100)) / 2
        @. Y.c.ρq_tag_tropo = FT(1.1) * ᶜbelow * Y.c.ρq_tot
        @. Y.c.ρq_tag_strat = FT(0.95) * (1 - ᶜbelow) * Y.c.ρq_tot
        @. Y.c.ρq_tag_evap = FT(0.3) * Y.c.ρq_tot
        # Clamps: `tropo` holds more than the cell's water in one cell, `evap`
        # more in another and less than none in a third.
        ρq_tot = parent(Y.c.ρq_tot)
        parent(Y.c.ρq_tag_tropo)[2] = FT(1.5) * ρq_tot[2]
        parent(Y.c.ρq_tag_evap)[5] = FT(1.2) * ρq_tot[5]
        parent(Y.c.ρq_tag_evap)[9] = FT(-0.1) * ρq_tot[9]
        @test CA.water_tag_fraction(parent(Y.c.ρq_tag_tropo)[2], ρq_tot[2]) == 1
        @test CA.water_tag_fraction(parent(Y.c.ρq_tag_evap)[5], ρq_tot[5]) == 1
        @test CA.water_tag_fraction(parent(Y.c.ρq_tag_evap)[9], ρq_tot[9]) == 0

        ᶜvelocity(scale) = @. FT(scale) * (1 + ᶜz / 2000)
        precomputed = (;
            ᶜwₗ = ᶜvelocity(0.01),
            ᶜwᵢ = ᶜvelocity(0.2),
            ᶜwᵣ = ᶜvelocity(4),
            ᶜwₛ = ᶜvelocity(1),
            ᶜT = fill(FT(275), ᶜspace),
            ᶜu = fill(
                Geometry.Covariant123Vector(FT(0), FT(0), FT(0)),
                ᶜspace,
            ),
        )
        scratch = (;
            ᶜbidiagonal_adjoint_matrix_c3 = CC.Fields.Field(
                MF.BidiagonalMatrixRow{typeof(Geometry.Covariant3Vector(FT(0))')},
                ᶜspace,
            ),
            ᶠband_matrix_wvec = similar(
                Y.f,
                MF.BandMatrixRow{
                    CC.Utilities.PlusHalf{Int64}(0),
                    1,
                    Geometry.WVector{FT},
                },
            ),
            ᶜtagging_q_share_norm = similar(Y.c.ρ),
        )
        ᶜΦ = @. FT(9.81) * ᶜz
        p = (;
            atmos = (;
                microphysics_model = CA.NonEquilibriumMicrophysics1M(),
                water_tagging_model = model,
            ),
            params = CA.ClimaAtmosParameters(FT),
            core = (; ᶜΦ),
            precomputed,
            scratch,
        )
        matrix = MF.FieldMatrix(
            CA.sedimentation_jacobian_blocks(Y, p.atmos, CA.UseDerivative())...,
        )
        dtγ = FT(60)
        CA.update_sedimentation_jacobian!(matrix, Y, p, dtγ, CA.UseDerivative())
        ᶜnorm = p.scratch.ᶜtagging_q_share_norm
        # The update renormalized the drifted partition.
        @test maximum(abs, parent(ᶜnorm) .- 1) > FT(0.04)

        # The tags' sedimentation tendency for one species, as the model
        # computes it (`vertical_advection_of_water_tendency!`).
        ᶜJ = CC.Fields.local_geometry_field(Y.c).J
        ᶠJ = CC.Fields.local_geometry_field(Y.f).J
        ᶠρ = @. CA.ᶠinterp(Y.c.ρ * ᶜJ) / ᶠJ
        function tag_tendencies(ᶜρqₚ, ᶜw)
            ᶜYₜ = CA._water_fix_fields(Y.c.ρ, tags)
            ᶜq = @. ᶜρqₚ / Y.c.ρ
            CA._sediment_water_tags!(ᶜYₜ, Y.c, ᶜnorm, ᶜq, ᶜw, ᶠρ, tags)
            return ᶜYₜ
        end
        c(n) = MF.FieldName(:c, n)
        partition_names = (:ρq_tag_tropo, :ρq_tag_strat)
        for (mass, velocity) in zip(masses, velocities)
            ᶜρqₚ = getproperty(Y.c, mass)
            ᶜw = getproperty(precomputed, velocity)
            parent_block = matrix[c(:ρq_tot), c(mass)]
            scale = maximum(abs, parent(parent_block))
            @test scale > 0
            # The partition's blocks sum to the parent's.
            ᶜpartition_block = copy(parent_block)
            @. ᶜpartition_block =
                matrix[c(:ρq_tag_tropo), c(mass)] +
                matrix[c(:ρq_tag_strat), c(mass)]
            @test maximum(
                abs,
                parent(ᶜpartition_block) .- parent(parent_block),
            ) <= 100 * eps(FT) * scale
            # Each tag's block is the derivative of its tendency in the species.
            ᶜv = @. ᶜρqₚ * (1 + sin(ᶜz / 170)) / 2
            h = FT(0.1)
            base = tag_tendencies(ᶜρqₚ, ᶜw)
            moved = tag_tendencies((@. ᶜρqₚ + h * ᶜv), ᶜw)
            for name in (partition_names..., :ρq_tag_evap)
                block = matrix[c(name), c(mass)]
                ᶜJv = @. block * ᶜv
                ᶜfinite_difference =
                    @. dtγ * (getproperty(moved, name) - getproperty(base, name)) / h
                Jv_scale = maximum(abs, parent(ᶜJv))
                @test Jv_scale > 0
                @test maximum(
                    abs,
                    parent(ᶜJv) .- parent(ᶜfinite_difference),
                ) <= 1000 * eps(FT) * Jv_scale
            end
        end
    end
end

@testset "The tags' cross blocks come only with the split solver" begin
    # Without the split, the tags' rows would join the nested solve's Schur
    # complement. Under prognostic EDMF that gives them blocks to `u₃`, which
    # the solve cannot take, so the unsplit form does not carry the cross
    # blocks at all.
    FT = Float64
    space = CA.ClimaCore.CommonSpaces.ColumnSpace(
        FT;
        z_min = 0,
        z_max = 1000,
        z_elem = 4,
        staggering = CA.ClimaCore.CommonSpaces.CellCenter(),
    )
    ᶜnames = (:ρ, :ρe_tot, :ρq_tot, :ρq_lcl, :ρq_icl, :ρq_rai, :ρq_sno)
    ᶜnames = (ᶜnames..., :ρq_tag_tropo)
    Y = CA.ClimaCore.Fields.FieldVector(;
        c = similar(
            CA.ClimaCore.Fields.coordinate_field(space),
            NamedTuple{ᶜnames, NTuple{length(ᶜnames), FT}},
        ),
    )
    atmos = (;
        microphysics_model = CA.NonEquilibriumMicrophysics1M(),
        diff_mode = CA.Implicit(),
    )
    split_flags = CA._derivative_flags(atmos, Y)
    unsplit_flags = CA._derivative_flags(atmos, Y; split_uncoupled_fields = false)
    @test split_flags.water_tag_cross_flag == CA.UseDerivative()
    @test unsplit_flags.water_tag_cross_flag == CA.IgnoreDerivative()
    block_keys(flags) = map(
        pair -> pair.first,
        CA.sedimentation_jacobian_blocks(Y, atmos, flags.water_tag_cross_flag),
    )
    tag = CA.MatrixFields.FieldName(:c, :ρq_tag_tropo)
    for flags in (split_flags, unsplit_flags)
        @test (tag, tag) in block_keys(flags)
    end
    for mass in (:ρq_lcl, :ρq_icl, :ρq_rai, :ρq_sno)
        cross_key = (tag, CA.MatrixFields.FieldName(:c, mass))
        @test cross_key in block_keys(split_flags)
        @test !(cross_key in block_keys(unsplit_flags))
    end
end
