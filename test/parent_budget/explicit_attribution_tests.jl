using Test
using ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
import ClimaAtmos.Internals.ParentBudget as PB
import ClimaTimeSteppers as CTS

# Stack step 4: process attribution for the explicit channels, through the
# applied-update event.
#
# Every process that writes a parent field sits inside one bracket in the
# tendency code, and in audit mode the adapter reads what each bracket applied
# at every weighted stage. A row the registry proves zero is booked from the
# registry alone. The sum of the rows is compared with the channel's envelope,
# never with the endpoint change, so a process that writes a parent field
# outside a bracket, or a bracket that misreports, shows up as an attribution
# residual with the envelope intact.
#
# A dry column with a prescribed large-scale subsidence and no surface flux is
# the smallest configuration with a measured explicit row and nothing else
# unattributed: the subsidence of total enthalpy is a genuine energy source,
# and the explicit channel is otherwise the dynamics, which the registry proves
# integrate to zero. The three faults the plan names are injected into the
# adapter's half of the bracket, so the ledger's answer to each is on record.

const FT = Float64
const ATMOS = PB.ATMOSPHERE_ENDPOINT_GROUP

provisional_tolerances() = Dict(
    quantity =>
        PB.BudgetTolerance(; absolute = 0.0, relative = 0.0, scale = 1.0, kappa = 64.0)
    for quantity in PB.BUDGET_QUANTITIES
)

newton() = CTS.NewtonsMethod(;
    max_iters = 1,
    update_j = CTS.UpdateEvery(CTS.NewNewtonIteration),
)

# A weak prescribed descent, strongest above 1.5 km.
subsidence_profile(z) = -0.001 * min(z, 1500.0) / 1500.0

forced_model(; kwargs...) = CA.AtmosModel(;
    subsidence = CA.LargeScaleSubsidence(subsidence_profile),
    disable_surface_flux_tendency = true,
    kwargs...,
)

function column_simulation(;
    parent_budget_mode = "audit",
    parent_budget_attribution = "net",
    model = forced_model(),
    kwargs...,
)
    return CA.AtmosSimulation{FT}(;
        model,
        grid = CA.ColumnGrid(FT; z_elem = 10),
        dt = 60,
        t_end = 600,
        job_id = "parent_budget_explicit",
        output_dir = mktempdir(),
        default_callbacks = false,
        diagnostics = CA.DiagnosticsConfig(; default = false),
        update_cache_every = "step",
        ode_config = CTS.IMEXAlgorithm(CTS.ARS343(), newton()),
        parent_budget_tolerances = provisional_tolerances(),
        parent_budget_mode,
        parent_budget_attribution,
        kwargs...,
    )
end

adapter_of(simulation) = simulation.integrator.p.parent_budget
step!(simulation, n) = foreach(_ -> CTS.step!(simulation.integrator), 1:n)

function parent_row(adapter, quantity)
    return only(
        filter(
            r -> r.quantity === quantity && r.control_volume === :atmosphere_only,
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
decomposition_legs(adapter, channel) = filter(
    l -> l.level isa PB.ProcessDecomposition && l.channel === channel,
    adapter.last_legs,
)
status(component) = PB.component_status(component)

@testset "Parent-budget explicit attribution" begin
    @testset "Both explicit channels attribute on a forced dry column" begin
        simulation = column_simulation()
        adapter = adapter_of(simulation)
        @test adapter.events == Set([:subsidence])
        step!(simulation, 3)
        for quantity in (:mass, :energy)
            @test parent_row(adapter, quantity).status === :pass
            for channel in (:explicit_main, :explicit_limited, :implicit)
                r = attribution_row(adapter, channel, quantity)
                @test r.status === :pass
                @test isempty(r.blocked_by)
                @test abs(r.residual) <= r.tolerance
            end
        end
        # The subsidence of total enthalpy is a real energy source, and the
        # rows reproduce the envelope to arithmetic precision.
        r = attribution_row(adapter, :explicit_main, :energy)
        @test abs(r.envelope) > 1e3
        @test abs(r.residual) < 1e-9 * abs(r.envelope)
        @test r.tolerance < 1e-6 * abs(r.envelope)
        # One leg per weighted explicit stage, with the accepted weight, the
        # mass provably zero because the process writes no density term.
        legs = legs_of(adapter, :subsidence)
        @test [l.stage for l in legs] == adapter.template.explicit_stages == [2, 3, 4]
        dt = 60.0
        for leg in legs
            @test leg.event === Symbol("expl.subsidence")
            @test leg.channel === :explicit_main
            @test leg.weight ≈ dt * adapter.timestepper.b_exp[leg.stage]
            @test status(leg.mass) isa PB.InvariantZero
            @test status(leg.water) isa PB.NotApplicable
            @test status(leg.energy) isa PB.Measured
            @test leg.energy.magnitude >= abs(leg.energy.amount)
            @test leg.measured_at === :stage_evaluation
        end
        @test sum(l.energy.amount for l in legs) ≈ r.attributed
        # The rows the registry proves zero are booked from it, once per step,
        # under their registry ids.
        for (channel, process) in (
            (:explicit_main, :horizontal_dynamics),
            (:explicit_main, :explicit_vertical_advection),
            (:explicit_main, :hyperdiffusion),
            (:explicit_limited, :tracer_hyperdiffusion),
            (:implicit, :vertical_advection),
        )
            leg = only(legs_of(adapter, process))
            @test leg.channel === channel
            @test leg.stage == 0
            @test leg.measured_at === :coverage_registry
            @test status(leg.energy) isa PB.InvariantZero
            @test PB.component_method(leg.energy) === :registry_proof
        end
        @test startswith(
            String(only(legs_of(adapter, :tracer_hyperdiffusion)).event),
            "lim_chan.",
        )
        # The envelopes carry the magnitude of what they summed, which is what
        # the tolerance reads, and it exceeds the net where terms cancelled.
        envelope = only(
            filter(
                l -> l.level isa PB.ChannelEnvelope && l.channel === :implicit,
                adapter.last_legs,
            ),
        )
        @test envelope.energy.magnitude > 1e3 * abs(envelope.energy.amount)
        @test adapter.reductions == 4
    end

    @testset "Summary mode books the declared rows and blocks on the measured one" begin
        simulation = column_simulation(; parent_budget_mode = "summary")
        adapter = adapter_of(simulation)
        step!(simulation, 2)
        @test isempty(legs_of(adapter, :subsidence))
        @test !isempty(legs_of(adapter, :horizontal_dynamics))
        r = attribution_row(adapter, :explicit_main, :energy)
        @test r.status === :blocked
        @test r.blocked_by == [
            "expected process subsidence of channel explicit_main in atmosphere was not recorded",
        ]
        # The limited channel has only proven zeros, so it attributes in
        # summary mode too.
        @test attribution_row(adapter, :explicit_limited, :energy).status === :pass
        @test parent_row(adapter, :energy).status === :pass
    end

    @testset "A transfer the channel applies blocks its attribution" begin
        simulation = column_simulation(;
            model = forced_model(; disable_surface_flux_tendency = false),
        )
        adapter = adapter_of(simulation)
        step!(simulation, 2)
        r = attribution_row(adapter, :explicit_main, :energy)
        @test r.status === :blocked
        @test r.blocked_by == [
            "expected leg flux of transfer event xfer.surface_turbulent_flux in " *
            "atmosphere, which channel explicit_main applies, was not recorded",
        ]
        # The residual is reported, not judged: it is the flux nobody booked.
        @test abs(r.residual) > 0
        @test parent_row(adapter, :energy).status === :pass
    end

    @testset "A missing event blocks the row and names it" begin
        simulation = column_simulation()
        adapter = adapter_of(simulation)
        PB.inject_fault!(adapter, :missing, :subsidence)
        step!(simulation, 1)
        legs = legs_of(adapter, :subsidence)
        @test length(legs) == 3
        for leg in legs
            @test status(leg.energy) isa PB.UnknownComponent
            @test PB.component_method(leg.energy) === :event_not_recorded
        end
        r = attribution_row(adapter, :explicit_main, :energy)
        @test r.status === :blocked
        @test length(r.blocked_by) == 3
        @test all(b -> occursin("expl.subsidence", b), r.blocked_by)
        # The envelope is what the stepper applied whatever the bracket did.
        @test parent_row(adapter, :energy).status === :pass
        PB.clear_fault!(adapter)
        step!(simulation, 1)
        @test attribution_row(adapter, :explicit_main, :energy).status === :pass
    end

    @testset "A sign-reversed event fails the attribution by twice its amount" begin
        simulation = column_simulation()
        adapter = adapter_of(simulation)
        PB.inject_fault!(adapter, :sign_reversed, :subsidence)
        step!(simulation, 1)
        r = attribution_row(adapter, :explicit_main, :energy)
        @test r.status === :fail
        @test isempty(r.blocked_by)
        @test r.residual ≈ 2 * r.envelope
        @test abs(r.residual) > r.tolerance
        @test parent_row(adapter, :energy).status === :pass
        @test attribution_row(adapter, :explicit_main, :mass).status === :pass
    end

    @testset "A duplicated, nested, mismatched or unknown event is refused where it fires" begin
        simulation = column_simulation()
        adapter = adapter_of(simulation)
        Yₜ = copy(simulation.integrator.u)
        # Outside a metered evaluation every bracket is a no-op, whatever it
        # names: this is every Newton iteration and every summary-mode step.
        @test adapter.evaluation === :none
        PB.open_ledger_event!(adapter, Yₜ, :not_a_process)
        PB.close_ledger_event!(adapter, Yₜ, :not_a_process)
        @test isempty(adapter.parts)
        PB.begin_evaluation!(adapter, :explicit, 2)
        PB.open_ledger_event!(adapter, Yₜ, :subsidence)
        PB.close_ledger_event!(adapter, Yₜ, :subsidence)
        @test haskey(adapter.parts, (:explicit, :subsidence, 2))
        # Duplicated.
        @test_throws ErrorException PB.open_ledger_event!(adapter, Yₜ, :subsidence)
        # Nested, and closed out of order.
        PB.open_ledger_event!(adapter, Yₜ, :radiation)
        @test_throws ErrorException PB.open_ledger_event!(adapter, Yₜ, :surface_flux)
        @test_throws ErrorException PB.close_ledger_event!(adapter, Yₜ, :surface_flux)
        PB.close_ledger_event!(adapter, Yₜ, :radiation)
        # Unknown to the registry.
        @test_throws ErrorException PB.open_ledger_event!(adapter, Yₜ, :not_a_process)
        # Left open at the end of the evaluation.
        PB.open_ledger_event!(adapter, Yₜ, :viscous_sponge)
        @test_throws ErrorException PB.end_evaluation!(adapter)
        PB.clear_step_state!(adapter)
        @test adapter.evaluation === :none
    end

    @testset "Gross attribution keeps the parts and the identities use the net" begin
        net = column_simulation()
        gross = column_simulation(; parent_budget_attribution = "gross")
        step!(net, 2)
        step!(gross, 2)
        @test isempty(PB.latest_gross(adapter_of(net)))
        records = PB.latest_gross(adapter_of(gross))
        legs = legs_of(adapter_of(gross), :subsidence)
        @test length(records) == length(legs) == 3
        for leg in legs
            record = only(filter(g -> g.stage == leg.stage, records))
            @test record.event === :subsidence
            @test record.weight == leg.weight
            @test all(>=(0), record.positive)
            @test all(<=(0), record.negative)
            # The parts sum to the net and differ by the magnitude.
            @test record.positive[3] + record.negative[3] ≈ leg.energy.amount
            @test record.positive[3] - record.negative[3] ≈ leg.energy.magnitude
        end
        # A negative stage weight puts the whole update in the negative part.
        stage_3 = only(filter(g -> g.stage == 3, records))
        @test stage_3.weight < 0
        @test stage_3.positive[3] == 0
        @test stage_3.negative[3] < 0
        for quantity in (:mass, :energy)
            a = attribution_row(adapter_of(net), :explicit_main, quantity)
            b = attribution_row(adapter_of(gross), :explicit_main, quantity)
            @test a.status === b.status === :pass
            @test a.residual == b.residual
        end
        @test parent(net.integrator.u.c) == parent(gross.integrator.u.c)
        # Gross splits process rows, which only audit mode collects.
        @test_throws ErrorException column_simulation(;
            parent_budget_mode = "summary",
            parent_budget_attribution = "gross",
        )
        @test_throws ErrorException column_simulation(; parent_budget_attribution = "both")
    end

    @testset "The explicit meter counts the evaluations the template names" begin
        simulation = column_simulation()
        adapter = adapter_of(simulation)
        calls =
            [adapter.template.calls[i] for i in adapter.template.per_hook[:T_exp_T_lim!]]
        @test [c.stage for c in calls] == [1, 2, 3, 4]
        @test all(c -> c.role === :evaluate, calls)
        @test adapter.template.explicit_stages == [2, 3, 4]
        step!(simulation, 1)
        # After a commit the counters are cleared, and a fifth evaluation in
        # one step is refused at the firing.
        for _ in 1:4
            PB.next_call!(adapter, :T_exp_T_lim!)
        end
        @test_throws ErrorException PB.next_call!(adapter, :T_exp_T_lim!)
    end

    @testset "The configuration path carries the attribution key" begin
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
                "parent_budget_mode" => "audit",
                "parent_budget_attribution" => "gross",
            );
            job_id = "parent_budget_explicit_moist",
        )
        simulation = CA.get_simulation(config)
        adapter = adapter_of(simulation)
        @test adapter.attribution === :gross
        step!(simulation, 1)
        # The idealized radiation is a flux-form mode, so the two crossings and
        # the surface flux are declared, and the explicit channel is blocked by
        # exactly their unrecorded legs until step 6 records them.
        r = attribution_row(adapter, :explicit_main, :energy)
        @test r.status === :blocked
        @test length(r.blocked_by) == 3
        for event in
            ("xfer.surface_turbulent_flux", "xfer.radiation_toa", "xfer.radiation_surface")
            @test any(b -> occursin(event, b), r.blocked_by)
        end
        @test attribution_row(adapter, :explicit_limited, :water).status === :blocked
        @test attribution_row(adapter, :explicit_limited, :water).blocked_by ==
              [PB.UNCALIBRATED_TOLERANCE_BLOCKER]
    end
end
