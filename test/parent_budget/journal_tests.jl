using Test
import ClimaAtmos as CA

# Journal mechanics for the parent-budget ledger.
#
# These tests are deliberately state-free. They exercise the rules the ledger
# enforces rather than the physics it will later measure: a leg is recorded once,
# an unknown component blocks rather than reads as zero, an envelope and its
# decomposition never land in one sum, a residual is a subtraction and never an
# entry, and a control-volume total is a projection of the legs rather than a
# separate amount.

# Components, with the evidence every constructor now requires.
mval(FT, x) = CA.measured(FT(x); method = :synthetic, source = :test)
zval(FT) = CA.invariant_zero(FT; proof = :writes_no_such_field, source = :test)
naval(FT) = CA.not_applicable(FT)
unkval(FT) = CA.unknown_component(FT)

# A leg with everything defaulted, so a test only names what it is about.
function test_leg(
    FT;
    event = :ev,
    leg = :atmos,
    reservoir = CA.AtmosphereReservoir(),
    channel = :explicit_main,
    level = CA.ChannelEnvelope(),
    mass = naval(FT),
    water = naval(FT),
    energy = naval(FT),
    path = CA.EquationTerm(),
    process = :test,
    phase = :explicit,
    step = 1,
    stage = 0,
    occurrence = 1,
    weight = one(FT),
    measured_at = :accepted_state,
)
    return CA.BudgetLeg{FT}(;
        event,
        leg,
        reservoir,
        channel,
        level,
        mass,
        water,
        energy,
        path,
        process,
        phase,
        step,
        stage,
        occurrence,
        weight,
        measured_at,
    )
end

# Endpoints with the atmosphere alone, or with a slab surface that owns energy
# and, in a moist configuration, water and the mass that goes with it.
function test_endpoints(FT, step; m, w, e, sfc_w = nothing, sfc_e = nothing)
    reservoirs = [
        CA.ReservoirEndpoint{FT}(;
            reservoir = CA.AtmosphereReservoir(),
            mass = isnothing(m) ? naval(FT) : mval(FT, m),
            water = isnothing(w) ? naval(FT) : mval(FT, w),
            energy = isnothing(e) ? naval(FT) : mval(FT, e),
        ),
    ]
    if !isnothing(sfc_e)
        # The slab's mass and water are one endpoint projected twice.
        sfc = isnothing(sfc_w) ? naval(FT) : mval(FT, sfc_w)
        push!(
            reservoirs,
            CA.ReservoirEndpoint{FT}(;
                reservoir = CA.SlabSurfaceReservoir(),
                mass = sfc,
                water = sfc,
                energy = mval(FT, sfc_e),
            ),
        )
    end
    return CA.BudgetEndpoints{FT}(step, reservoirs)
end

# A tolerance loose enough that only a real defect fails it. `kappa` has no
# default in the implementation on purpose, so every test that wants a verdict
# has to declare one.
loose_tolerance(FT, scale = 1) = Dict(
    q => CA.BudgetTolerance(;
        absolute = FT(1e-6) * FT(scale),
        relative = FT(0),
        scale = FT(0),
        kappa = FT(64),
    ) for q in CA.BUDGET_QUANTITIES
)

parent_for(commit, quantity, cv) = only(
    filter(
        r -> r.quantity === quantity && r.control_volume === cv,
        commit.parent,
    ),
)

attribution_for(commit, quantity, cv, channel) = only(
    filter(
        r ->
            r.quantity === quantity &&
            r.control_volume === cv &&
            r.channel === channel,
        commit.attribution,
    ),
)

transfer_for(commit, quantity, event, cv) = only(
    filter(
        r ->
            r.quantity === quantity &&
            r.event === event &&
            r.control_volume === cv,
        commit.transfer,
    ),
)

# One committed step, opening at zero and closing at the given atmospheric
# totals, with whatever legs the caller wants recorded in between.
function run_step!(ledger, FT, opening, closing, legs; tolerances = nothing)
    CA.open_transaction!(ledger, opening)
    for leg in legs
        CA.record_leg!(ledger, leg)
    end
    return CA.commit_transaction!(ledger, closing; tolerances)
end

@testset "Parent-budget journal" begin
    for FT in (Float32, Float64)

        @testset "A non-measured component cannot be nonzero ($FT)" begin
            # Three separate constructors, three separate ways to smuggle a real
            # amount in under a label that says it cannot be wrong.
            @test_throws ErrorException CA.BudgetComponent{FT}(
                FT(1),
                CA.BudgetEvidence(;
                    status = CA.InvariantZero(),
                    method = :proof,
                ),
            )
            @test_throws ErrorException CA.BudgetComponent{FT}(
                FT(1),
                CA.BudgetEvidence(; status = CA.NotApplicable()),
            )
            @test_throws ErrorException CA.BudgetComponent{FT}(
                FT(-1),
                CA.BudgetEvidence(; status = CA.UnknownComponent()),
            )
            # A measured component may hold anything, including zero.
            @test mval(FT, 0).amount == 0
            @test mval(FT, -3).amount == FT(-3)
        end

        @testset "An invariant zero must name its proof ($FT)" begin
            # A zero with no proof is an assumption, which is exactly what the
            # unknown status exists to keep out of a total.
            @test_throws ErrorException CA.BudgetComponent{FT}(
                zero(FT),
                CA.BudgetEvidence(; status = CA.InvariantZero()),
            )
            proven = CA.invariant_zero(FT; proof = :momentum_only)
            @test CA.component_method(proven) === :momentum_only
            @test CA.is_contributing(proven)
        end

        @testset "Evidence is per component ($FT)" begin
            # One event routinely measures energy, proves a mass zero, and has
            # nothing to say about water. A per-leg status would misdescribe two
            # of the three.
            leg = test_leg(
                FT;
                mass = CA.invariant_zero(FT; proof = :writes_no_ρ),
                water = mval(FT, 5),
                energy = unkval(FT),
            )
            @test CA.component_status(leg.mass) isa CA.InvariantZero
            @test CA.component_method(leg.mass) === :writes_no_ρ
            @test CA.component_status(leg.water) isa CA.Measured
            @test CA.component_method(leg.water) === :synthetic
            @test CA.component_status(leg.energy) isa CA.UnknownComponent
            @test CA.is_blocking(leg.energy)
            @test !CA.is_blocking(leg.mass)
        end

        @testset "An unknown blocks and does not sum ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            opening = test_endpoints(FT, 0; m = 100, w = 10, e = 1000)
            closing = test_endpoints(FT, 1; m = 100, w = 10, e = 1000)
            commit = run_step!(
                ledger,
                FT,
                opening,
                closing,
                [test_leg(FT; energy = unkval(FT))];
                tolerances = loose_tolerance(FT),
            )
            r = parent_for(commit, :energy, :atmosphere_only)
            @test r.status === :blocked
            @test !isempty(r.blocked_by)
            @test r.recorded == 0
        end

        @testset "All-inapplicable is not a closed budget ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            # A dry configuration: the atmosphere owns no water at all.
            opening = test_endpoints(FT, 0; m = 100, w = nothing, e = 1000)
            closing = test_endpoints(FT, 1; m = 100, w = nothing, e = 1000)
            commit = run_step!(
                ledger,
                FT,
                opening,
                closing,
                CA.BudgetLeg{FT}[];
                tolerances = loose_tolerance(FT),
            )
            r = parent_for(commit, :water, :atmosphere_only)
            @test r.status === :not_applicable
            @test !r.applicable
            @test r.endpoint_change == 0
            # Mass in the same step is an ordinary passing budget, so the
            # inapplicable water is not an artefact of the whole step failing.
            @test parent_for(commit, :mass, :atmosphere_only).status === :pass
        end

        @testset "A leg is recorded once ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            CA.open_transaction!(
                ledger,
                test_endpoints(FT, 0; m = 1, w = 1, e = 1),
            )
            correction = CA.ProcessDecomposition()
            CA.record_leg!(
                ledger,
                test_leg(FT; level = correction, mass = mval(FT, 1)),
            )
            @test_throws ErrorException CA.record_leg!(
                ledger,
                test_leg(FT; level = correction, mass = mval(FT, 1)),
            )
            # A different stage is a different firing, not a duplicate. This is
            # the `constrain_state!` case at `update_constrain_state_every =
            # "stage"`, where the same correction fires once per ARS343 stage.
            CA.record_leg!(
                ledger,
                test_leg(FT; level = correction, mass = mval(FT, 1), stage = 2),
            )
            @test length(ledger.legs) == 2
        end

        @testset "An event has one collection level ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            CA.open_transaction!(
                ledger,
                test_endpoints(FT, 0; m = 1, w = 1, e = 1),
            )
            CA.record_leg!(
                ledger,
                test_leg(FT; event = :ev, level = CA.ChannelEnvelope()),
            )
            # The same event cannot also be a decomposition: one event is one
            # kind of thing, and classifying it twice makes both identities wrong.
            @test_throws ErrorException CA.record_leg!(
                ledger,
                test_leg(
                    FT;
                    event = :ev,
                    leg = :other,
                    level = CA.ProcessDecomposition(),
                ),
            )
            # A second envelope for the same channel and reservoir is refused
            # too: a channel applies one accepted update to one reservoir.
            @test_throws ErrorException CA.record_leg!(
                ledger,
                test_leg(FT; event = :other_event, level = CA.ChannelEnvelope()),
            )
        end

        @testset "An envelope is never summed with its parts ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            opening = test_endpoints(FT, 0; m = 100, w = 10, e = 1000)
            closing = test_endpoints(FT, 1; m = 106, w = 10, e = 1000)
            legs = [
                test_leg(
                    FT;
                    event = :env_explicit,
                    level = CA.ChannelEnvelope(),
                    mass = mval(FT, 6),
                ),
                test_leg(
                    FT;
                    event = :part_a,
                    leg = :a,
                    level = CA.ProcessDecomposition(),
                    mass = mval(FT, 4),
                ),
                test_leg(
                    FT;
                    event = :part_b,
                    leg = :b,
                    level = CA.ProcessDecomposition(),
                    mass = mval(FT, 2),
                ),
            ]
            commit = run_step!(
                ledger,
                FT,
                opening,
                closing,
                legs;
                tolerances = loose_tolerance(FT),
            )
            parent = parent_for(commit, :mass, :atmosphere_only)
            # The primary identity sees the envelope alone. Adding the parts
            # would give 12 against an endpoint change of 6.
            @test parent.envelopes == FT(6)
            @test parent.recorded == FT(6)
            @test parent.residual == 0
            @test parent.status === :pass

            # The attribution identity sees the parts against the envelope.
            attribution =
                attribution_for(commit, :mass, :atmosphere_only, :explicit_main)
            @test attribution.envelope == FT(6)
            @test attribution.attributed == FT(6)
            @test attribution.residual == 0
            @test attribution.status === :pass
        end

        @testset "A missing leg shows up in attribution, not in parent ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            opening = test_endpoints(FT, 0; m = 100, w = 10, e = 1000)
            closing = test_endpoints(FT, 1; m = 106, w = 10, e = 1000)
            legs = [
                test_leg(
                    FT;
                    event = :env_explicit,
                    level = CA.ChannelEnvelope(),
                    mass = mval(FT, 6),
                ),
                test_leg(
                    FT;
                    event = :part_a,
                    leg = :a,
                    level = CA.ProcessDecomposition(),
                    mass = mval(FT, 4),
                ),
            ]
            commit = run_step!(
                ledger,
                FT,
                opening,
                closing,
                legs;
                tolerances = loose_tolerance(FT),
            )
            # This is the whole reason the two residuals are separate: the step
            # transition is reproduced exactly while the named processes explain
            # only two thirds of it.
            @test parent_for(commit, :mass, :atmosphere_only).status === :pass
            attribution =
                attribution_for(commit, :mass, :atmosphere_only, :explicit_main)
            @test attribution.residual == FT(2)
            @test attribution.status === :fail
        end

        @testset "A sign-reversed leg is caught ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            opening = test_endpoints(FT, 0; m = 100, w = 10, e = 1000)
            closing = test_endpoints(FT, 1; m = 105, w = 10, e = 1000)
            commit = run_step!(
                ledger,
                FT,
                opening,
                closing,
                [
                    test_leg(
                        FT;
                        level = CA.ChannelEnvelope(),
                        mass = mval(FT, -5),
                    ),
                ];
                tolerances = loose_tolerance(FT),
            )
            r = parent_for(commit, :mass, :atmosphere_only)
            @test r.residual == FT(10)
            @test r.status === :fail
        end

        @testset "No verdict without a calibrated tolerance ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            opening = test_endpoints(FT, 0; m = 100, w = 10, e = 1000)
            closing = test_endpoints(FT, 1; m = 100, w = 10, e = 1000)
            commit =
                run_step!(ledger, FT, opening, closing, CA.BudgetLeg{FT}[])
            r = parent_for(commit, :mass, :atmosphere_only)
            # A perfectly closing step still reports blocked, because kappa has
            # not been calibrated and a guessed tolerance is not a tolerance.
            @test r.residual == 0
            @test r.status === :blocked
            @test isnothing(r.tolerance)
            @test CA.UNCALIBRATED_TOLERANCE_BLOCKER in r.blocked_by
        end

        @testset "A tolerance scale is never a signed total ($FT)" begin
            @test_throws ErrorException CA.BudgetTolerance(;
                absolute = FT(0),
                relative = FT(1),
                scale = FT(-1),
                kappa = FT(1),
            )
            τ = CA.BudgetTolerance(;
                absolute = FT(2),
                relative = FT(0),
                scale = FT(0),
                kappa = FT(0),
            )
            @test CA.tolerance_value(τ, 1e6, 1e6, 1e3) == FT(2)
        end

        @testset "A residual is a subtraction, never an entry ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            opening = test_endpoints(FT, 0; m = 100, w = 10, e = 1000)
            closing = test_endpoints(FT, 1; m = 107, w = 10, e = 1000)
            commit = run_step!(
                ledger,
                FT,
                opening,
                closing,
                [
                    test_leg(
                        FT;
                        level = CA.ChannelEnvelope(),
                        mass = mval(FT, 4),
                    ),
                ];
                tolerances = loose_tolerance(FT),
            )
            r = parent_for(commit, :mass, :atmosphere_only)
            @test r.endpoint_change == FT(7)
            @test r.recorded == FT(4)
            @test r.residual == FT(3)
            # Nothing was written back: the ledger holds the legs it was given
            # and no balancing entry appeared to make the step close.
            @test r.status === :fail
            @test length(commit.parent) == 3
        end

        @testset "Signed drift cancels; absolute drift does not ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            # +5 unaccounted, then -5 unaccounted. The signed sum is zero and
            # would report a perfectly closed run that closed on neither step.
            run_step!(
                ledger,
                FT,
                test_endpoints(FT, 0; m = 100, w = 10, e = 1000),
                test_endpoints(FT, 1; m = 105, w = 10, e = 1000),
                CA.BudgetLeg{FT}[],
            )
            commit = run_step!(
                ledger,
                FT,
                test_endpoints(FT, 1; m = 105, w = 10, e = 1000),
                test_endpoints(FT, 2; m = 100, w = 10, e = 1000),
                CA.BudgetLeg{FT}[],
            )
            r = parent_for(commit, :mass, :atmosphere_only)
            @test r.cumulative_residual == 0
            @test r.cumulative_abs_residual == FT(10)
            @test r.max_abs_residual == FT(5)
        end

        @testset "The cumulative change has a second reading ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            run_step!(
                ledger,
                FT,
                test_endpoints(FT, 0; m = 100, w = 10, e = 1000),
                test_endpoints(FT, 1; m = 103, w = 10, e = 1000),
                CA.BudgetLeg{FT}[],
            )
            commit = run_step!(
                ledger,
                FT,
                test_endpoints(FT, 1; m = 103, w = 10, e = 1000),
                test_endpoints(FT, 2; m = 108, w = 10, e = 1000),
                CA.BudgetLeg{FT}[],
            )
            r = parent_for(commit, :mass, :atmosphere_only)
            # `Bᴺ − B⁰` read directly from the retained initial endpoint, beside
            # the telescoped sum of the per-step differences. The telescoped sum
            # can only reproduce the same measurements, so a difference between
            # the two is an accumulation error rather than a rederivation.
            @test r.endpoint_change_from_initial == FT(8)
            @test r.cumulative_endpoint_change == FT(8)
            @test r.telescoping_discrepancy == 0
        end

        @testset "Endpoint amounts must be continuous ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            run_step!(
                ledger,
                FT,
                test_endpoints(FT, 0; m = 100, w = 10, e = 1000),
                test_endpoints(FT, 1; m = 100, w = 10, e = 1000),
                CA.BudgetLeg{FT}[],
            )
            # A gap between one step's closing state and the next one's opening
            # state is a change nothing accounted for.
            @test_throws ErrorException CA.open_transaction!(
                ledger,
                test_endpoints(FT, 1; m = 101, w = 10, e = 1000),
            )
        end

        @testset "Endpoint statuses must be continuous ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            run_step!(
                ledger,
                FT,
                test_endpoints(FT, 0; m = 100, w = 10, e = 1000),
                test_endpoints(FT, 1; m = 100, w = 10, e = 1000),
                CA.BudgetLeg{FT}[],
            )
            # Comparing amounts alone would let a reservoir change what it owns
            # unnoticed, because the check skips any pair that does not
            # contribute — which is exactly the pair a status change produces.
            @test_throws ErrorException CA.open_transaction!(
                ledger,
                test_endpoints(FT, 1; m = 100, w = nothing, e = 1000),
            )
        end

        @testset "A refused commit changes nothing ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            run_step!(
                ledger,
                FT,
                test_endpoints(FT, 0; m = 100, w = 10, e = 1000),
                test_endpoints(FT, 1; m = 105, w = 10, e = 1000),
                CA.BudgetLeg{FT}[],
            )
            before = copy(ledger.cumulative_residual)
            committed = ledger.committed_steps

            CA.open_transaction!(
                ledger,
                test_endpoints(FT, 1; m = 105, w = 10, e = 1000),
            )
            # A closing endpoint whose reservoir set changed mid-step is refused
            # before anything is advanced, which is what makes the commit atomic.
            bad = test_endpoints(
                FT,
                2;
                m = 110,
                w = 10,
                e = 1000,
                sfc_w = 1,
                sfc_e = 1,
            )
            @test_throws ErrorException CA.commit_transaction!(ledger, bad)
            @test ledger.cumulative_residual == before
            @test ledger.committed_steps == committed
            @test ledger.is_open
        end

        @testset "An internal transfer cancels ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            opening =
                test_endpoints(FT, 0; m = 100, w = 10, e = 1000, sfc_w = 5, sfc_e = 50)
            closing =
                test_endpoints(FT, 1; m = 98, w = 8, e = 1000, sfc_w = 7, sfc_e = 50)
            legs = [
                test_leg(
                    FT;
                    event = :deposition,
                    leg = :atmosphere,
                    level = CA.ReservoirTransfer(),
                    reservoir = CA.AtmosphereReservoir(),
                    mass = mval(FT, -2),
                    water = mval(FT, -2),
                ),
                test_leg(
                    FT;
                    event = :deposition,
                    leg = :surface,
                    level = CA.ReservoirTransfer(),
                    reservoir = CA.SlabSurfaceReservoir(),
                    mass = mval(FT, 2),
                    water = mval(FT, 2),
                ),
            ]
            commit = run_step!(
                ledger,
                FT,
                opening,
                closing,
                legs;
                tolerances = loose_tolerance(FT),
            )
            coupled = transfer_for(
                commit,
                :water,
                :deposition,
                :atmosphere_and_surface,
            )
            @test coupled.expectation === :cancellation
            @test coupled.total == 0
            @test coupled.leg_count == 2
            @test coupled.status === :pass

            # The same legs, seen from the atmosphere alone, are a boundary
            # crossing. There is no cancellation to claim there, and the total is
            # the flux rather than a residual.
            atmos =
                transfer_for(commit, :water, :deposition, :atmosphere_only)
            @test atmos.expectation === :boundary_crossing
            @test atmos.total == FT(-2)
            @test atmos.leg_count == 1
            @test atmos.status === :not_applicable
        end

        @testset "A coupling mismatch is preserved ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            opening =
                test_endpoints(FT, 0; m = 100, w = 10, e = 1000, sfc_w = 5, sfc_e = 50)
            closing =
                test_endpoints(FT, 1; m = 98, w = 8, e = 1000, sfc_w = 7.5, sfc_e = 50)
            legs = [
                test_leg(
                    FT;
                    event = :deposition,
                    leg = :atmosphere,
                    level = CA.ReservoirTransfer(),
                    reservoir = CA.AtmosphereReservoir(),
                    water = mval(FT, -2),
                ),
                test_leg(
                    FT;
                    event = :deposition,
                    leg = :surface,
                    level = CA.ReservoirTransfer(),
                    reservoir = CA.SlabSurfaceReservoir(),
                    water = mval(FT, 2.5),
                ),
            ]
            commit = run_step!(
                ledger,
                FT,
                opening,
                closing,
                legs;
                tolerances = loose_tolerance(FT),
            )
            coupled = transfer_for(
                commit,
                :water,
                :deposition,
                :atmosphere_and_surface,
            )
            # Two quadratures of one physical flux are allowed to disagree, and
            # the disagreement is the finding. Nothing here forces it to zero.
            @test coupled.total ≈ FT(0.5) rtol = 100 * eps(FT)
            @test coupled.status === :fail
        end

        @testset "An inapplicable transfer is not a cancellation ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            opening = test_endpoints(FT, 0; m = 100, w = nothing, e = 1000)
            closing = test_endpoints(FT, 1; m = 100, w = nothing, e = 1000)
            legs = [
                test_leg(
                    FT;
                    event = :radiation,
                    leg = :atmosphere,
                    level = CA.ReservoirTransfer(),
                    energy = mval(FT, 0),
                ),
            ]
            commit = run_step!(
                ledger,
                FT,
                opening,
                closing,
                legs;
                tolerances = loose_tolerance(FT),
            )
            r = transfer_for(commit, :water, :radiation, :atmosphere_only)
            # Water does not exist for this event. Reporting a total of zero
            # with no blockers would look exactly like a measured cancellation.
            @test !r.applicable
            @test r.status === :not_applicable
            @test r.status_counts[:not_applicable] == 1
            @test r.status_counts[:measured] == 0
        end

        @testset "A stage observation is not a leg ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            opening = test_endpoints(FT, 0; m = 100, w = 10, e = 1000)
            closing = test_endpoints(FT, 1; m = 100, w = 10, e = 1000)
            CA.open_transaction!(ledger, opening)
            observation = CA.StageObservation{FT}(;
                event = :limiter,
                observation = :stage_2,
                reservoir = CA.AtmosphereReservoir(),
                mass = mval(FT, 7),
                water = naval(FT),
                energy = naval(FT),
                process = :limiter,
                step = 1,
                stage = 2,
            )
            CA.record_observation!(ledger, observation)
            @test_throws MethodError CA.record_leg!(ledger, observation)
            commit = CA.commit_transaction!(
                ledger,
                closing;
                tolerances = loose_tolerance(FT),
            )
            # A raw intermediate-stage difference is evidence, and evidence moves
            # no budget: the step still closes at zero.
            r = parent_for(commit, :mass, :atmosphere_only)
            @test r.recorded == 0
            @test r.residual == 0
            @test r.status === :pass
        end

        @testset "An unknown channel is refused ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            CA.open_transaction!(
                ledger,
                test_endpoints(FT, 0; m = 1, w = 1, e = 1),
            )
            # A channel nobody reconciles would take part in no identity and
            # vanish from every total, so it fails closed.
            @test_throws ErrorException CA.record_leg!(
                ledger,
                test_leg(FT; channel = :made_up),
            )
        end

        @testset "The two views come from the same legs ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            opening =
                test_endpoints(FT, 0; m = 100, w = 10, e = 1000, sfc_w = 5, sfc_e = 50)
            closing =
                test_endpoints(FT, 1; m = 98, w = 8, e = 1000, sfc_w = 7, sfc_e = 50)
            legs = [
                test_leg(
                    FT;
                    event = :env_atmos,
                    leg = :atmosphere,
                    level = CA.ChannelEnvelope(),
                    reservoir = CA.AtmosphereReservoir(),
                    mass = mval(FT, -2),
                    water = mval(FT, -2),
                    energy = mval(FT, 0),
                ),
                test_leg(
                    FT;
                    event = :env_surface,
                    leg = :surface,
                    level = CA.ChannelEnvelope(),
                    reservoir = CA.SlabSurfaceReservoir(),
                    mass = mval(FT, 2),
                    water = mval(FT, 2),
                    energy = mval(FT, 0),
                ),
            ]
            commit = run_step!(
                ledger,
                FT,
                opening,
                closing,
                legs;
                tolerances = loose_tolerance(FT),
            )
            atmos = parent_for(commit, :water, :atmosphere_only)
            coupled = parent_for(commit, :water, :atmosphere_and_surface)
            @test atmos.endpoint_change == FT(-2)
            @test atmos.recorded == FT(-2)
            @test coupled.endpoint_change == 0
            @test coupled.recorded == 0
            @test atmos.status === :pass
            @test coupled.status === :pass
        end

        @testset "The coupled view is refused without a slab ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            opening = test_endpoints(FT, 0; m = 100, w = 10, e = 1000)
            closing = test_endpoints(FT, 1; m = 100, w = 10, e = 1000)
            commit =
                run_step!(ledger, FT, opening, closing, CA.BudgetLeg{FT}[])
            # An unavailable view is not emitted at all, which is different from
            # a view that exists and is inapplicable for one quantity.
            @test all(r -> r.control_volume === :atmosphere_only, commit.parent)
            @test !CA.control_volume_available(
                closing,
                CA.ATMOSPHERE_AND_SURFACE,
            )
        end

        @testset "Quantities stay separate ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            opening = test_endpoints(FT, 0; m = 100, w = 10, e = 1000)
            closing = test_endpoints(FT, 1; m = 100, w = 12, e = 1000)
            commit = run_step!(
                ledger,
                FT,
                opening,
                closing,
                [
                    test_leg(
                        FT;
                        level = CA.ChannelEnvelope(),
                        mass = CA.invariant_zero(FT; proof = :writes_no_ρ),
                        water = mval(FT, 2),
                        energy = mval(FT, 0),
                    ),
                ];
                tolerances = loose_tolerance(FT),
            )
            # A forcing path adds water without adding air. The mass component
            # is a proven zero and is never manufactured from the water leg.
            @test parent_for(commit, :mass, :atmosphere_only).status === :pass
            @test parent_for(commit, :water, :atmosphere_only).recorded == FT(2)
            @test parent_for(commit, :water, :atmosphere_only).status === :pass
        end

        @testset "An aborted transaction commits nothing ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            CA.open_transaction!(
                ledger,
                test_endpoints(FT, 0; m = 100, w = 10, e = 1000),
            )
            CA.record_leg!(
                ledger,
                test_leg(FT; level = CA.ChannelEnvelope(), mass = mval(FT, 5)),
            )
            CA.abort_transaction!(ledger)
            @test !ledger.is_open
            @test isempty(ledger.legs)
            @test ledger.committed_steps == 0
            @test isempty(ledger.cumulative_residual)
        end

        @testset "Bad quantity names are refused ($FT)" begin
            leg = test_leg(FT)
            @test_throws ErrorException CA.budget_component(leg, :entropy)
        end
    end
end
