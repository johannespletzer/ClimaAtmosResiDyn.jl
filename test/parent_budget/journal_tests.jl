using Test
import ClimaAtmos as CA

# Journal mechanics for the parent-budget ledger.
#
# These tests are deliberately state-free. They exercise the rules the ledger
# enforces rather than the physics it will later measure: a leg is recorded
# once, an unknown component blocks rather than reads as zero, a residual is a
# subtraction and never an entry, and a control-volume total is a projection of
# the legs rather than a separate amount.

# Build a leg with everything defaulted, so a test only names what it is about.
function test_leg(
    FT;
    event = :ev,
    leg = :atmos,
    reservoir = CA.AtmosphereReservoir(),
    mass = CA.not_applicable(FT),
    water = CA.not_applicable(FT),
    energy = CA.not_applicable(FT),
    path = CA.EquationTerm(),
    process = :test,
    phase = :explicit,
    step = 1,
    stage = 0,
    occurrence = 1,
    method = :synthetic,
)
    return CA.BudgetLeg{FT}(;
        event, leg, reservoir, mass, water, energy,
        path, process, phase, step, stage, occurrence, method,
    )
end

# Endpoints with the atmosphere alone, or with a slab surface that owns energy
# and water but never mass.
function test_endpoints(FT, step; m, w, e, sfc_w = nothing, sfc_e = nothing)
    reservoirs = [
        CA.ReservoirEndpoint{FT}(;
            reservoir = CA.AtmosphereReservoir(),
            mass = CA.measured(FT(m)),
            water = CA.measured(FT(w)),
            energy = CA.measured(FT(e)),
        ),
    ]
    if !isnothing(sfc_e)
        push!(
            reservoirs,
            CA.ReservoirEndpoint{FT}(;
                reservoir = CA.SlabSurfaceReservoir(),
                # The slab owns mass and water with the same amount.
                mass = isnothing(sfc_w) ? CA.not_applicable(FT) :
                       CA.measured(FT(sfc_w)),
                water = isnothing(sfc_w) ? CA.not_applicable(FT) :
                        CA.measured(FT(sfc_w)),
                energy = CA.measured(FT(sfc_e)),
            ),
        )
    end
    return CA.BudgetEndpoints{FT}(step, reservoirs)
end

# The atmosphere-only mass reconciliation out of one commit's results. Written
# as a loop rather than a `filter` with a multi-line lambda, which JuliaFormatter
# and a reader both prefer.
function atmosphere_mass_result(reconciliations)
    for r in reconciliations
        if r.quantity === :mass && r.control_volume === :atmosphere_only
            return r
        end
    end
    error("No atmosphere-only mass reconciliation was returned")
end

# Record `n` legs with stage indices starting at `first_stage`, for the
# allocation bound below. The stages have to differ because a repeat of the same
# identity is refused, which is also why the warm-up call cannot reuse them.
function record_many!(ledger::CA.BudgetLedger{FT}, n, first_stage) where {FT}
    for i in first_stage:(first_stage + n - 1)
        CA.record_leg!(
            ledger,
            CA.BudgetLeg{FT}(;
                event = :bulk,
                leg = :atmosphere,
                reservoir = CA.AtmosphereReservoir(),
                mass = CA.measured(one(FT)),
                water = CA.invariant_zero(FT),
                energy = CA.not_applicable(FT),
                path = CA.EquationTerm(),
                process = :test,
                phase = :explicit,
                step = ledger.step,
                stage = i,
                method = :synthetic,
            ),
        )
    end
    return nothing
end

@testset "Parent-budget journal" begin
    for FT in (Float32, Float64)

        @testset "Component status ($FT)" begin
            m = CA.measured(FT(3))
            z = CA.invariant_zero(FT)
            n = CA.not_applicable(FT)
            u = CA.unknown_component(FT)

            @test m.amount == FT(3)
            @test CA.is_contributing(m)
            @test !CA.is_blocking(m)

            # A proven zero carries an exact zero, which is what makes it safe
            # to add into a total.
            @test iszero(z.amount)
            @test CA.is_contributing(z)
            @test !CA.is_blocking(z)

            # Not applicable contributes nothing and blocks nothing.
            @test !CA.is_contributing(n)
            @test !CA.is_blocking(n)

            # Unknown is the one that blocks. This is the whole reason the
            # status exists: a component nobody measured must not read as zero.
            @test !CA.is_contributing(u)
            @test CA.is_blocking(u)
        end

        @testset "Control-volume membership ($FT)" begin
            @test CA.is_inside(CA.ATMOSPHERE_ONLY, CA.AtmosphereReservoir())
            @test !CA.is_inside(CA.ATMOSPHERE_ONLY, CA.SlabSurfaceReservoir())
            @test CA.is_inside(
                CA.ATMOSPHERE_AND_SURFACE,
                CA.SlabSurfaceReservoir(),
            )
            # The exterior is in no view. A flux into it is a boundary
            # crossing, never an internal transfer.
            @test !CA.is_inside(
                CA.ATMOSPHERE_AND_SURFACE,
                CA.ExteriorReservoir(),
            )
        end

        @testset "Transaction lifecycle ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            opening = test_endpoints(FT, 0; m = 10, w = 1, e = 100)

            # Nothing may be recorded outside a transaction.
            @test_throws ErrorException CA.record_leg!(ledger, test_leg(FT))

            CA.open_transaction!(ledger, opening)
            @test ledger.is_open
            @test ledger.step == 1

            # Opening twice would mean the previous step neither committed nor
            # aborted.
            @test_throws ErrorException CA.open_transaction!(ledger, opening)

            # A leg for the wrong step is a stage or callback writing into the
            # wrong transaction.
            @test_throws ErrorException CA.record_leg!(
                ledger,
                test_leg(FT; step = 7),
            )

            CA.record_leg!(ledger, test_leg(FT; mass = CA.measured(FT(2))))
            @test length(ledger.legs) == 1

            # The same (event, leg, step) twice is a bracket firing twice.
            @test_throws ErrorException CA.record_leg!(
                ledger,
                test_leg(FT; mass = CA.measured(FT(2))),
            )
            @test length(ledger.legs) == 1

            # A different leg of the same event is fine, and is how the two
            # halves of one exchange are recorded.
            CA.record_leg!(
                ledger,
                test_leg(FT; leg = :surface, mass = CA.measured(FT(-2))),
            )
            @test length(ledger.legs) == 2

            closing = test_endpoints(FT, 1; m = 10, w = 1, e = 100)
            @test_throws ErrorException CA.commit_transaction!(
                ledger,
                test_endpoints(FT, 5; m = 10, w = 1, e = 100),
            )
            CA.commit_transaction!(ledger, closing)
            @test !ledger.is_open
            @test ledger.committed_steps == 1
            @test isempty(ledger.legs)
        end

        @testset "Aborted transaction commits nothing ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            CA.open_transaction!(
                ledger,
                test_endpoints(FT, 0; m = 10, w = 1, e = 100),
            )
            CA.record_leg!(ledger, test_leg(FT; mass = CA.measured(FT(5))))
            CA.abort_transaction!(ledger)

            @test !ledger.is_open
            @test isempty(ledger.legs)
            @test ledger.committed_steps == 0
            @test isempty(ledger.cumulative_residual)

            # And the same identity may be recorded again afterwards, because
            # the abandoned attempt left nothing behind.
            CA.open_transaction!(
                ledger,
                test_endpoints(FT, 0; m = 10, w = 1, e = 100),
            )
            CA.record_leg!(ledger, test_leg(FT; mass = CA.measured(FT(5))))
            @test length(ledger.legs) == 1
        end

        @testset "Projection separates the identity terms ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            CA.open_transaction!(
                ledger,
                test_endpoints(FT, 0; m = 0, w = 0, e = 0),
            )
            CA.record_leg!(
                ledger,
                test_leg(
                    FT;
                    leg = :eq,
                    mass = CA.measured(FT(1)),
                    path = CA.EquationTerm(),
                ),
            )
            CA.record_leg!(
                ledger,
                test_leg(
                    FT;
                    leg = :mp,
                    mass = CA.measured(FT(2)),
                    path = CA.DiscreteMap(),
                ),
            )
            CA.record_leg!(
                ledger,
                test_leg(
                    FT;
                    leg = :lim,
                    mass = CA.measured(FT(4)),
                    path = CA.NumericalCorrection(),
                ),
            )
            CA.record_leg!(
                ledger,
                test_leg(
                    FT;
                    leg = :defect,
                    mass = CA.measured(FT(8)),
                    path = CA.AlgebraicSolveDefect(),
                ),
            )

            p = CA.project_legs(ledger, :mass, CA.ATMOSPHERE_ONLY)
            @test p.equation == FT(1)
            @test p.map == FT(2)
            @test p.correction == FT(4)
            @test p.solve_defect == FT(8)
            @test p.recorded == FT(15)
            @test isempty(p.blocked_by)
        end

        @testset "An unknown component blocks but does not sum ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            CA.open_transaction!(
                ledger,
                test_endpoints(FT, 0; m = 0, w = 0, e = 0),
            )
            CA.record_leg!(
                ledger,
                test_leg(FT; leg = :known, energy = CA.measured(FT(3))),
            )
            CA.record_leg!(
                ledger,
                test_leg(FT; leg = :gap, energy = CA.unknown_component(FT)),
            )

            p = CA.project_legs(ledger, :energy, CA.ATMOSPHERE_ONLY)
            @test p.recorded == FT(3)
            # Blocked, and the report names which leg would unblock it.
            @test length(p.blocked_by) == 1
            @test occursin("gap", only(p.blocked_by))
        end

        @testset "The same legs give two control-volume views ($FT)" begin
            # One exchange, two legs, equal and opposite. It is a boundary
            # crossing for the atmosphere alone and internal to the coupled
            # system, from the same recorded legs.
            ledger = CA.BudgetLedger{FT}()
            CA.open_transaction!(
                ledger,
                test_endpoints(FT, 0; m = 0, w = 0, e = 0, sfc_e = 0),
            )
            CA.record_leg!(
                ledger,
                test_leg(
                    FT;
                    event = :surface_flux,
                    leg = :atmosphere,
                    reservoir = CA.AtmosphereReservoir(),
                    energy = CA.measured(FT(7)),
                ),
            )
            CA.record_leg!(
                ledger,
                test_leg(
                    FT;
                    event = :surface_flux,
                    leg = :surface,
                    reservoir = CA.SlabSurfaceReservoir(),
                    energy = CA.measured(FT(-7)),
                ),
            )

            atmos = CA.project_legs(ledger, :energy, CA.ATMOSPHERE_ONLY)
            coupled =
                CA.project_legs(ledger, :energy, CA.ATMOSPHERE_AND_SURFACE)
            @test atmos.recorded == FT(7)
            @test coupled.recorded == FT(0)

            # Cancellation is measured, not imposed.
            m = CA.transfer_mismatch(ledger, :surface_flux, :energy)
            @test m.found
            @test m.total == FT(0)
            @test isempty(m.blocked_by)

            # "The legs cancel", "there were no legs", and "nobody measured the
            # legs" are three different answers and must stay distinguishable.
            no_event = CA.transfer_mismatch(ledger, :no_such_event, :energy)
            @test !no_event.found

            unmeasured = CA.transfer_mismatch(ledger, :surface_flux, :mass)
            @test unmeasured.found
            @test unmeasured.total == FT(0)
        end

        @testset "A coupling mismatch is preserved ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            CA.open_transaction!(
                ledger,
                test_endpoints(FT, 0; m = 0, w = 0, e = 0, sfc_e = 0),
            )
            CA.record_leg!(
                ledger,
                test_leg(
                    FT;
                    event = :precip,
                    leg = :atmosphere,
                    reservoir = CA.AtmosphereReservoir(),
                    water = CA.measured(FT(-5)),
                ),
            )
            # A lagged or separately discretized surface leg. Nothing forces
            # the two to agree, and the ledger must not hide the difference.
            CA.record_leg!(
                ledger,
                test_leg(
                    FT;
                    event = :precip,
                    leg = :surface,
                    reservoir = CA.SlabSurfaceReservoir(),
                    water = CA.measured(FT(4)),
                ),
            )
            @test CA.transfer_mismatch(ledger, :precip, :water).total == FT(-1)
        end

        @testset "The residual is a subtraction ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            CA.open_transaction!(
                ledger,
                test_endpoints(FT, 0; m = 100, w = 10, e = 1000),
            )
            CA.record_leg!(
                ledger,
                test_leg(
                    FT;
                    leg = :eq,
                    mass = CA.measured(FT(2)),
                    path = CA.EquationTerm(),
                ),
            )
            CA.record_leg!(
                ledger,
                test_leg(
                    FT;
                    leg = :defect,
                    mass = CA.measured(FT(1)),
                    path = CA.AlgebraicSolveDefect(),
                ),
            )

            # The endpoint moved by 4 while 3 was recorded, so 1 is unaccounted
            # for. Nothing in the ledger may make that go away.
            closing = test_endpoints(FT, 1; m = 104, w = 10, e = 1000)
            rs = CA.commit_transaction!(ledger, closing)
            r = atmosphere_mass_result(rs)
            @test r.endpoint_change == FT(4)
            @test r.recorded == FT(3)
            @test r.residual == FT(1)
            # Without the solve defect the discrepancy is larger, and the two
            # are reported separately because the defect is a leading-order
            # term under the default Newton configuration.
            @test r.discrepancy_before_defect == FT(2)
            @test !CA.is_blocked(r)
            @test r.applicable
        end

        @testset "Per-step residuals survive cancellation ($FT)" begin
            # The mass goes 0 → 1 → 0 with nothing recorded, so each step has a
            # residual and the two cancel. Reporting only the cumulative number
            # would show a perfectly closed budget over a run that closed on
            # neither step, which is the failure a whole-run conservation check
            # cannot see. Both are reported for exactly this reason.
            ledger = CA.BudgetLedger{FT}()
            per_step = FT[]
            last = nothing
            for (step, before, after) in ((1, FT(0), FT(1)), (2, FT(1), FT(0)))
                CA.open_transaction!(
                    ledger,
                    test_endpoints(FT, step - 1; m = before, w = 0, e = 0),
                )
                last = test_endpoints(FT, step; m = after, w = 0, e = 0)
                rs = CA.commit_transaction!(ledger, last)
                push!(per_step, atmosphere_mass_result(rs).residual)
            end
            @test ledger.committed_steps == 2
            @test per_step == [FT(1), FT(-1)]

            key = (:mass, :atmosphere_only)
            # The signed totals cancel, which is exactly why they are not the
            # whole report.
            @test ledger.cumulative_change[key] == FT(0)
            @test ledger.cumulative_residual[key] == FT(0)
            # The magnitude aggregates cannot cancel, and they are what a
            # tolerance is checked against.
            @test ledger.cumulative_abs_residual[key] == FT(2)
            @test ledger.max_abs_residual[key] == FT(1)
        end

        @testset "Quantities stay separate ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            CA.open_transaction!(
                ledger,
                test_endpoints(FT, 0; m = 0, w = 0, e = 0),
            )
            # A water-only leg. Its mass and energy components are unknown, not
            # zero, so neither budget may be inferred from it.
            CA.record_leg!(
                ledger,
                test_leg(
                    FT;
                    water = CA.measured(FT(6)),
                    mass = CA.unknown_component(FT),
                    energy = CA.unknown_component(FT),
                ),
            )
            @test CA.project_legs(ledger, :water, CA.ATMOSPHERE_ONLY).recorded ==
                  FT(6)
            @test CA.project_legs(ledger, :mass, CA.ATMOSPHERE_ONLY).recorded ==
                  FT(0)
            @test !isempty(
                CA.project_legs(ledger, :mass, CA.ATMOSPHERE_ONLY).blocked_by,
            )
            @test !isempty(
                CA.project_legs(ledger, :energy, CA.ATMOSPHERE_ONLY).blocked_by,
            )
        end

        @testset "A stage-repeated correction is not a duplicate ($FT)" begin
            # `update_constrain_state_every` accepts "stage", and then the same
            # correction fires once per ARS343 stage. Each firing is its own
            # leg. Without a stage index the four would collide and three would
            # be refused, so the identity has to carry one.
            ledger = CA.BudgetLedger{FT}()
            CA.open_transaction!(
                ledger,
                test_endpoints(FT, 0; m = 0, w = 0, e = 0),
            )
            for stage in 1:4
                CA.record_leg!(
                    ledger,
                    test_leg(
                        FT;
                        event = :constrain_state,
                        leg = :atmosphere,
                        stage = stage,
                        mass = CA.measured(FT(1)),
                        path = CA.NumericalCorrection(),
                    ),
                )
            end
            @test length(ledger.legs) == 4
            @test CA.project_legs(ledger, :mass, CA.ATMOSPHERE_ONLY).recorded ==
                  FT(4)

            # The same stage twice is still a duplicate, which is the case the
            # check exists for.
            @test_throws ErrorException CA.record_leg!(
                ledger,
                test_leg(
                    FT;
                    event = :constrain_state,
                    leg = :atmosphere,
                    stage = 2,
                    mass = CA.measured(FT(1)),
                    path = CA.NumericalCorrection(),
                ),
            )
            # And a genuine second firing within one stage says so.
            CA.record_leg!(
                ledger,
                test_leg(
                    FT;
                    event = :constrain_state,
                    leg = :atmosphere,
                    stage = 2,
                    occurrence = 2,
                    mass = CA.measured(FT(1)),
                    path = CA.NumericalCorrection(),
                ),
            )
            @test length(ledger.legs) == 5
        end

        @testset "An inapplicable quantity is not a closed budget ($FT)" begin
            # A dry model owns no water. That has to read differently from a
            # water budget that closed at zero, because the ledger never made a
            # claim about it either way.
            dry = CA.BudgetEndpoints{FT}(
                0,
                [
                    CA.ReservoirEndpoint{FT}(;
                        reservoir = CA.AtmosphereReservoir(),
                        mass = CA.measured(FT(10)),
                        water = CA.not_applicable(FT),
                        energy = CA.measured(FT(100)),
                    ),
                ],
            )
            water = CA.endpoint_total(dry, :water, CA.ATMOSPHERE_ONLY)
            @test !water.applicable
            @test water.total == FT(0)
            @test isempty(water.blocked_by)

            mass = CA.endpoint_total(dry, :mass, CA.ATMOSPHERE_ONLY)
            @test mass.applicable
            @test mass.total == FT(10)

            # The coupled view of a configuration with no slab is the same
            # situation seen from the other side: the atmosphere is in the view
            # and owns mass, so mass stays applicable there.
            coupled = CA.endpoint_total(dry, :water, CA.ATMOSPHERE_AND_SURFACE)
            @test !coupled.applicable
        end

        @testset "Endpoint continuity is enforced ($FT)" begin
            ledger = CA.BudgetLedger{FT}()
            CA.open_transaction!(
                ledger,
                test_endpoints(FT, 0; m = 10, w = 1, e = 100),
            )
            CA.commit_transaction!(
                ledger,
                test_endpoints(FT, 1; m = 12, w = 1, e = 100),
            )

            # Opening the next transaction somewhere other than where the last
            # one closed would lose the gap from every total.
            @test_throws ErrorException CA.open_transaction!(
                ledger,
                test_endpoints(FT, 1; m = 99, w = 1, e = 100),
            )
            # The matching endpoint is accepted.
            CA.open_transaction!(
                ledger,
                test_endpoints(FT, 1; m = 12, w = 1, e = 100),
            )
            @test ledger.is_open
            @test ledger.step == 2
        end

        @testset "The slab owns mass and water alike ($FT)" begin
            # Deposition takes water out of the atmosphere, and `ρ` carries the
            # whole of `ρq_tot`, so the same event has a mass leg of the same
            # size. In the coupled view both cancel.
            ledger = CA.BudgetLedger{FT}()
            CA.open_transaction!(
                ledger,
                test_endpoints(FT, 0; m = 0, w = 0, e = 0, sfc_w = 0, sfc_e = 0),
            )
            for (leg, reservoir, sign) in (
                (:atmosphere, CA.AtmosphereReservoir(), -1),
                (:surface, CA.SlabSurfaceReservoir(), 1),
            )
                CA.record_leg!(
                    ledger,
                    test_leg(
                        FT;
                        event = :precipitation_deposition,
                        leg = leg,
                        reservoir = reservoir,
                        mass = CA.measured(FT(sign * 3)),
                        water = CA.measured(FT(sign * 3)),
                    ),
                )
            end

            for quantity in (:mass, :water)
                @test CA.project_legs(
                    ledger,
                    quantity,
                    CA.ATMOSPHERE_ONLY,
                ).recorded == FT(-3)
                @test CA.project_legs(
                    ledger,
                    quantity,
                    CA.ATMOSPHERE_AND_SURFACE,
                ).recorded == FT(0)
                @test CA.transfer_mismatch(
                    ledger,
                    :precipitation_deposition,
                    quantity,
                ).total == FT(0)
            end
        end

        @testset "Recording stays cheap ($FT)" begin
            # The leg types carry abstract status, reservoir and path fields,
            # so a leg is not isbits and recording one allocates. That is a
            # deliberate trade: legs are host-side records created a few dozen
            # times per accepted step, each next to a global reduction that
            # costs orders of magnitude more, and concretely parametrising five
            # more type parameters would cost the readability that makes the
            # status distinctions legible. Nothing here runs on the device.
            #
            # The bound is generous on purpose. It is here to catch an
            # order-of-magnitude regression, such as a leg accidentally holding
            # a field or a copy of the state, not to pin an exact figure that
            # would differ between Julia versions.
            ledger = CA.BudgetLedger{FT}()
            CA.open_transaction!(
                ledger,
                test_endpoints(FT, 0; m = 0, w = 0, e = 0),
            )
            record_many!(ledger, 1, 1)  # warm up, so compilation is not counted
            bytes = @allocated record_many!(ledger, 100, 2)
            @test bytes < 200_000
            @test length(ledger.legs) == 101
        end

        @testset "Bad quantity names are refused ($FT)" begin
            @test_throws ErrorException CA.budget_component(
                test_leg(FT),
                :enthalpy,
            )
        end
    end
end
