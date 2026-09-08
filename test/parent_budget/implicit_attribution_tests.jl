using Test
using ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
import ClimaAtmos.Internals.ParentBudget as PB
import ClimaTimeSteppers as CTS

# Stack step 5, with the final maps of step 7: the implicit envelope, the final
# accepted-state maps, and the implicit channel's own rows.
#
# With every term of the parent identity collected, the identity can pass, and
# this file is where it first does, on a dry column under all three constraint
# cadences and on a moist column built from the configuration path. The rest is
# the implicit channel seen from inside in audit mode: the solve defect measured
# on the Newton-solved stage, the post-implicit correction, the hooks the
# stepper folds into the stored tendency, and the stage firings kept as
# observations. The defect is a leading-order term at one Newton iteration and
# shrinks when the solve converges, which is the test that separates a solver
# from a bookkeeping error.

const FT = Float64
const ATMOS = PB.ATMOSPHERE_ENDPOINT_GROUP

# A provisional tolerance for these tests: no floor, no relative term, and the
# arithmetic term at κ = 64. Not a calibrated value; step 8 calibrates κ.
provisional_tolerances() = Dict(
    quantity =>
        PB.BudgetTolerance(; absolute = 0.0, relative = 0.0, scale = 1.0, kappa = 64.0)
    for quantity in PB.BUDGET_QUANTITIES
)

newton(max_iters) = CTS.NewtonsMethod(;
    max_iters,
    update_j = CTS.UpdateEvery(CTS.NewNewtonIteration),
)

function column_simulation(;
    parent_budget_mode = "summary",
    update_constrain_state_every = "step",
    max_iters = 1,
    approximate_solve_iters = 1,
    model = CA.AtmosModel(),
    kwargs...,
)
    return CA.AtmosSimulation{FT}(;
        model,
        grid = CA.ColumnGrid(FT; z_elem = 10),
        dt = 60,
        t_end = 600,
        job_id = "parent_budget_implicit",
        output_dir = mktempdir(),
        default_callbacks = false,
        diagnostics = CA.DiagnosticsConfig(; default = false),
        update_cache_every = "step",
        ode_config = CTS.IMEXAlgorithm(CTS.ARS343(), newton(max_iters)),
        jacobian = CA.ManualSparseJacobian(; approximate_solve_iters),
        parent_budget_tolerances = provisional_tolerances(),
        parent_budget_mode,
        update_constrain_state_every,
        kwargs...,
    )
end

adapter_of(simulation) = simulation.integrator.p.parent_budget
step!(simulation, n) = foreach(_ -> CTS.step!(simulation.integrator), 1:n)

function parent_row(adapter, quantity; control_volume = :atmosphere_only)
    return only(
        filter(
            r -> r.quantity === quantity && r.control_volume === control_volume,
            PB.latest_commit(adapter).parent,
        ),
    )
end

function attribution_row(adapter, channel, quantity)
    return only(
        filter(
            r ->
                r.channel === channel && r.quantity === quantity &&
                r.control_volume === :atmosphere_only,
            PB.latest_commit(adapter).attribution,
        ),
    )
end

legs_of(adapter, process) = filter(l -> l.process === process, adapter.last_legs)
final_map_legs(adapter) = filter(l -> l.level isa PB.FinalMap, adapter.last_legs)

# The size of the solve defect over one step, as the sum of the absolute energy
# amounts of its per-stage legs.
defect_energy(adapter) = sum(
    abs(PB.budget_component(l, :energy).amount) for l in legs_of(adapter, :solve_defect);
    init = 0.0,
)

@testset "Parent-budget implicit attribution" begin
    @testset "The parent identity passes on a dry column" begin
        for cadence in ("step", "stage", "dss")
            simulation = column_simulation(; update_constrain_state_every = cadence)
            adapter = adapter_of(simulation)
            step!(simulation, 3)
            for quantity in (:mass, :energy)
                r = parent_row(adapter, quantity)
                @test r.status === :pass
                @test isempty(r.missing_expectations)
                @test isempty(r.blocked_by)
                @test abs(r.residual) <= r.tolerance
            end
            @test parent_row(adapter, :water).status === :not_applicable
            # Three envelopes and three final maps, the maps booked as the
            # invariant zeros the registry proves for this configuration.
            envelopes = filter(l -> l.level isa PB.ChannelEnvelope, adapter.last_legs)
            @test sort([l.channel for l in envelopes]) ==
                  [:explicit_limited, :explicit_main, :implicit]
            maps = final_map_legs(adapter)
            @test sort([l.channel for l in maps]) == [:constrain_state!, :dss!, :lim!]
            for leg in maps
                @test PB.component_status(leg.energy) isa PB.InvariantZero
                @test PB.component_status(leg.water) isa PB.NotApplicable
            end
            @test adapter.reductions == 4
            @test isempty(adapter.last_observations)
        end
    end

    @testset "The energy identity is a real test" begin
        simulation = column_simulation()
        adapter = adapter_of(simulation)
        step!(simulation, 3)
        r = parent_row(adapter, :energy)
        # The tolerance is tiny against the update, and the update is large
        # against the residual: a missing or misweighted term could not hide.
        @test r.tolerance < 1e-6 * abs(r.endpoint_change)
        @test abs(r.residual) < 1e-9 * abs(r.endpoint_change)
        @test abs(r.envelopes) > 1e3
    end

    @testset "A moist column built from the configuration passes for water too" begin
        # DYCOMS_RF02 is a 1.5 km marine boundary layer, so it gets the geometry
        # the shipped DYCOMS configs use; the default 30 km column extrapolates
        # the profile into negative pressure. Its idealized radiation forces the
        # energy so the water and energy identities carry real updates.
        config = CA.AtmosConfig(
            Dict(
                "initial_condition" => "DYCOMS_RF02",
                "z_max" => 1500.0,
                "z_elem" => 30,
                "z_stretch" => false,
                "rad" => "DYCOMS",
                "microphysics_model" => "0M",
                "config" => "column",
                "FLOAT_TYPE" => "Float64",
                "dt" => "10secs",
                "t_end" => "600secs",
                "output_default_diagnostics" => false,
                "output_dir" => mktempdir(),
                "parent_budget_mode" => "summary",
            );
            job_id = "parent_budget_moist_column",
        )
        simulation = CA.get_simulation(config)
        adapter = adapter_of(simulation)
        @test adapter isa PB.ParentBudgetAdapter
        step!(simulation, 3)
        tolerances = provisional_tolerances()
        for quantity in PB.BUDGET_QUANTITIES
            r = parent_row(adapter, quantity)
            @test r.applicable
            # The configuration path carries no tolerance, so the verdict is
            # blocked by exactly that, and the residual is judged here.
            @test r.status === :blocked
            @test r.blocked_by == [PB.UNCALIBRATED_TOLERANCE_BLOCKER]
            @test isempty(r.missing_expectations)
            before =
                PB.endpoint_total(adapter.ledger.last_closing, quantity, PB.ATMOSPHERE_ONLY).total
            limit =
                PB.tolerance_value(tolerances[quantity], before, before, abs(r.recorded))
            @test abs(r.residual) <= limit
        end
    end

    @testset "Audit mode books the implicit rows and keeps the observations" begin
        simulation = column_simulation(;
            parent_budget_mode = "audit",
            update_constrain_state_every = "stage",
        )
        adapter = adapter_of(simulation)
        step!(simulation, 2)
        stages = adapter.template.implicit_stages
        @test stages == [2, 3, 4]
        for process in (:solve_defect, :post_implicit_correction, :folded_constraint)
            legs = legs_of(adapter, process)
            @test sort([l.stage for l in legs]) == stages
            @test all(l -> l.channel === :implicit, legs)
            @test all(l -> l.level isa PB.ProcessDecomposition, legs)
        end
        # A column has no DSS, so the folded DSS row is not in the roster.
        @test isempty(legs_of(adapter, :folded_dss))
        # The correction writes no density term.
        for leg in legs_of(adapter, :post_implicit_correction)
            @test PB.component_status(leg.mass) isa PB.InvariantZero
            @test PB.component_status(leg.energy) isa PB.Measured
        end
        # The weights are the accepted ones: `b_imp[i]/γ` for what the stored
        # tendency folds in.
        γ = 0.4358665215084590
        b = adapter.timestepper.b_imp
        for leg in legs_of(adapter, :solve_defect)
            @test leg.weight ≈ b[leg.stage] / γ
        end
        # Every intermediate firing of a state-writing hook is an observation,
        # and none of them is a leg.
        expected = count(PB.is_observation, adapter.template.calls)
        @test length(adapter.last_observations) == expected
        @test expected > 0
        # The parent identity passes, and so does the implicit attribution:
        # vertical advection is booked from the registry as the zero it
        # proves, and the defect and correction rows explain the rest.
        for quantity in (:mass, :energy)
            @test parent_row(adapter, quantity).status === :pass
            r = attribution_row(adapter, :implicit, quantity)
            @test r.status === :pass
            @test isempty(r.blocked_by)
        end
        @test only(legs_of(adapter, :vertical_advection)).measured_at === :coverage_registry
        @test length(adapter.commits) == 2
    end

    @testset "The solve defect shrinks when the solve converges" begin
        defects = Dict{Tuple{Int, Int}, Float64}()
        for (max_iters, approximate_solve_iters) in ((1, 1), (3, 1), (1, 2))
            simulation = column_simulation(;
                parent_budget_mode = "audit",
                max_iters,
                approximate_solve_iters,
            )
            adapter = adapter_of(simulation)
            step!(simulation, 2)
            defects[(max_iters, approximate_solve_iters)] = defect_energy(adapter)
            # The parent identity holds at the arithmetic level whatever the
            # solver did: the stored tendency contains the defect.
            @test parent_row(adapter, :energy).status === :pass
            @test parent_row(adapter, :mass).status === :pass
        end
        @test defects[(1, 1)] > 0
        @test defects[(3, 1)] < defects[(1, 1)]
        # On a dry column without implicit diffusion the manual Jacobian's
        # approximate solve is exact, so a second approximate iteration cannot
        # change the defect; it must not grow it either.
        @test defects[(1, 2)] <= defects[(1, 1)]
    end

    @testset "Without the correction hook the defect is unknown, not zero" begin
        # With no upwind correction the stepper never calls `T_post_imp!`, so
        # the solved stage is never visible with a matching cache and the
        # adapter cannot evaluate the defect without touching the trajectory.
        # The parent identity still passes; the defect rows block by name.
        numerics = CA.AtmosNumerics(; energy_q_tot_upwinding = :none)
        simulation = column_simulation(;
            parent_budget_mode = "audit",
            model = CA.AtmosModel(; numerics),
        )
        adapter = adapter_of(simulation)
        @test isempty(adapter.template.per_hook[:T_post_imp!])
        @test !PB.has_post_implicit_evaluation(adapter)
        step!(simulation, 2)
        @test parent_row(adapter, :energy).status === :pass
        @test isempty(legs_of(adapter, :post_implicit_correction))
        legs = legs_of(adapter, :solve_defect)
        @test [l.stage for l in legs] == [2, 3, 4]
        for leg in legs
            @test PB.component_status(leg.energy) isa PB.UnknownComponent
            @test PB.component_method(leg.energy) === :no_post_implicit_evaluation
        end
        r = attribution_row(adapter, :implicit, :energy)
        @test r.status === :blocked
        @test length(r.blocked_by) == 3
        @test all(b -> occursin("impl.solve_defect", b), r.blocked_by)
    end

    @testset "Audit mode changes nothing either" begin
        off = column_simulation(; parent_budget_mode = "off")
        audit = column_simulation(; parent_budget_mode = "audit")
        step!(off, 2)
        step!(audit, 2)
        @test parent(off.integrator.u.c) == parent(audit.integrator.u.c)
        @test parent(off.integrator.u.f) == parent(audit.integrator.u.f)
    end

    @testset "The hook order is enforced against the template" begin
        simulation = column_simulation()
        adapter = adapter_of(simulation)
        step!(simulation, 1)
        # After a commit the counters are cleared, so the check that runs at
        # the next commit would refuse a step in which the hooks never fired.
        @test_throws ErrorException PB.check_hook_counts(adapter)
        # A hook that fires more often than the template holds is refused at
        # the firing, not a step later.
        for _ in 1:length(adapter.template.per_hook[:lim!])
            PB.next_call!(adapter, :lim!)
        end
        @test_throws ErrorException PB.next_call!(adapter, :lim!)
    end
end
