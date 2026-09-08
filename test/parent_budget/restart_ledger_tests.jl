using Test
using ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
import ClimaAtmos.Internals.ParentBudget as PB
import ClimaTimeSteppers as CTS

# Stack step 7: the restart transition and the callback rules.
#
# A restart restores a state that no transaction produced. The checkpoint
# carries the ledger's endpoint of the state it holds, and the first
# transaction after the restart measures the restored state and compares it
# with that endpoint exactly before it opens: the same integrals of the same
# state in the same arithmetic are equal, or something changed the state on
# the way and that change belongs to no step. A checkpoint written without a
# ledger carries no endpoint, and a restart from it is recorded as unverified
# rather than refused. A custom callback runs on the accepted state between
# two transactions, so with the ledger on it is accepted only inside a
# read-only declaration, which audit mode holds it to.

const FT = Float64

provisional_tolerances() = Dict(
    quantity =>
        PB.BudgetTolerance(; absolute = 0.0, relative = 0.0, scale = 1.0, kappa = 64.0)
    for quantity in PB.BUDGET_QUANTITIES
)

newton() = CTS.NewtonsMethod(;
    max_iters = 1,
    update_j = CTS.UpdateEvery(CTS.NewNewtonIteration),
)

function column_simulation(;
    parent_budget_mode = "summary",
    output_dir = mktempdir(),
    kwargs...,
)
    return CA.AtmosSimulation{FT}(;
        grid = CA.ColumnGrid(FT; z_elem = 10),
        dt = 60,
        t_end = 600,
        job_id = "parent_budget_restarts",
        output_dir,
        default_callbacks = false,
        diagnostics = CA.DiagnosticsConfig(; default = false),
        update_cache_every = "step",
        ode_config = CTS.IMEXAlgorithm(CTS.ARS343(), newton()),
        parent_budget_tolerances = provisional_tolerances(),
        parent_budget_mode,
        kwargs...,
    )
end

adapter_of(simulation) = simulation.integrator.p.parent_budget
step!(simulation, n) = foreach(_ -> CTS.step!(simulation.integrator), 1:n)
context_of(simulation) = ClimaComms.context(simulation.integrator.u.c)

# The checkpoint a run wrote, two steps in, with the default callbacks on.
function checkpoint_after_two_steps(; parent_budget_mode)
    simulation = column_simulation(;
        parent_budget_mode,
        default_callbacks = true,
        checkpoint_frequency = 120,
    )
    step!(simulation, 2)
    files = filter(f -> endswith(f, ".hdf5"), readdir(simulation.output_dir; join = true))
    return simulation, only(files)
end

function parent_row(adapter, quantity)
    return only(
        filter(
            r -> r.quantity === quantity && r.control_volume === :atmosphere_only,
            PB.latest_commit(adapter).parent,
        ),
    )
end

@testset "Parent-budget restarts and callbacks" begin
    @testset "The checkpoint carries the endpoint and the restart verifies it" begin
        simulation, checkpoint =
            checkpoint_after_two_steps(; parent_budget_mode = "summary")
        adapter = adapter_of(simulation)
        carried = PB.read_checkpoint_endpoints(checkpoint, context_of(simulation))
        @test carried isa PB.CheckpointEndpoints
        @test carried.step == 2
        # The attributes are the closing endpoint of the committed step, as
        # the ledger holds it: the same amounts, the same statuses.
        closing = adapter.ledger.last_closing
        @test closing.step == 2
        for endpoint in closing.reservoirs, quantity in PB.BUDGET_QUANTITIES
            c = PB.budget_component(endpoint, quantity)
            amount, status =
                carried.components[(PB.reservoir_name(endpoint.reservoir), quantity)]
            @test amount == c.amount
            @test status === PB.status_name(PB.component_status(c))
        end
        @test carried.components[(:atmosphere, :water)] == (0.0, :not_applicable)
        # The restarted run measures the restored state and finds it equal.
        restarted = column_simulation(; restart_file = checkpoint)
        adapter = adapter_of(restarted)
        transition = PB.restart_transition(adapter)
        @test transition isa PB.RestartTransition
        @test transition.status === :verified
        @test transition.checkpoint_step == 2
        # The record after the restart is a new segment from the restored
        # endpoint, and its steps close as before.
        @test adapter.ledger.initial.step == 0
        step!(restarted, 2)
        @test adapter.steps_committed == 2
        for quantity in (:mass, :energy)
            @test parent_row(adapter, quantity).status === :pass
        end
        @test isnothing(PB.restart_transition(adapter_of(simulation)))
    end

    @testset "A checkpoint written without a ledger restarts unverified" begin
        _, checkpoint = checkpoint_after_two_steps(; parent_budget_mode = "off")
        @test isnothing(PB.read_checkpoint_endpoints(checkpoint, ClimaComms.context()))
        restarted = column_simulation(; restart_file = checkpoint)
        transition = PB.restart_transition(adapter_of(restarted))
        @test transition.status === :unverified
        @test transition.checkpoint_step == 0
        step!(restarted, 1)
        @test parent_row(adapter_of(restarted), :energy).status === :pass
    end

    @testset "A restored state that differs from its checkpoint is refused" begin
        simulation = column_simulation()
        adapter = adapter_of(simulation)
        step!(simulation, 1)
        measured = adapter.ledger.last_closing
        exact = Dict(
            (PB.reservoir_name(e.reservoir), q) => (
                PB.budget_component(e, q).amount,
                PB.status_name(PB.component_status(PB.budget_component(e, q))),
            ) for e in measured.reservoirs, q in PB.BUDGET_QUANTITIES
        )
        checkpoint = PB.CheckpointEndpoints(1, exact)
        @test PB.check_restart_transition(adapter.schema, measured, checkpoint).status ===
              :verified
        # One unit of energy off, and the transition is a change nobody
        # accounted for.
        moved = copy(exact)
        moved[(:atmosphere, :energy)] = (exact[(:atmosphere, :energy)][1] + 1.0, :measured)
        @test_throws ErrorException PB.check_restart_transition(
            adapter.schema,
            measured,
            PB.CheckpointEndpoints(1, moved),
        )
        # A status that changed across the restart is refused too, and so is
        # a checkpoint of another configuration.
        relabeled = copy(exact)
        relabeled[(:atmosphere, :water)] = (0.0, :measured)
        @test_throws ErrorException PB.check_restart_transition(
            adapter.schema,
            measured,
            PB.CheckpointEndpoints(1, relabeled),
        )
        foreign = copy(exact)
        foreign[(:slab_surface, :energy)] = (1.0, :measured)
        @test_throws ErrorException PB.check_restart_transition(
            adapter.schema,
            measured,
            PB.CheckpointEndpoints(1, foreign),
        )
        # Checkpoint endpoints belong to a restart.
        @test_throws ErrorException column_simulation(; restart_file = nothing) |>
                                    s -> PB.build_parent_budget(
            PB.SummaryMode(),
            s.integrator.p.atmos,
            s.integrator.u;
            ode_config = s.integrator.alg,
            restart = false,
            constraint_cadence = :step,
            checkpoint,
        )
    end

    @testset "A custom callback is accepted only when declared read-only" begin
        fired = Ref(0)
        counting = CTS.DiscreteCallback(
            (u, t, integrator) -> true,
            integrator -> (fired[] += 1; nothing),
        )
        # Undeclared, it is refused at setup.
        @test_throws ErrorException column_simulation(; callbacks = (counting,))
        @test_throws ErrorException PB.ReadOnlyCallback(integrator -> nothing)
        # Declared, it runs after the ledger's callback every step.
        declared = column_simulation(; callbacks = (PB.ReadOnlyCallback(counting),))
        step!(declared, 2)
        @test fired[] == 2
        @test parent_row(adapter_of(declared), :energy).status === :pass
        # Without a ledger the declaration passes through untouched.
        @test PB.declared_callbacks(nothing, (counting,)) === (counting,)
    end

    @testset "Audit mode holds a declared callback to its declaration" begin
        writing = CTS.DiscreteCallback(
            (u, t, integrator) -> true,
            integrator -> (integrator.u.c.ρe_tot .*= (1 + 1e-7); nothing),
        )
        # Summary mode trusts the declaration, so the written change lands in
        # the next step's residual and the identity fails there.
        trusted = column_simulation(; callbacks = (PB.ReadOnlyCallback(writing),))
        step!(trusted, 2)
        @test parent_row(adapter_of(trusted), :energy).status === :fail
        # Audit mode reads the state around the firing and refuses it.
        audited = column_simulation(;
            parent_budget_mode = "audit",
            callbacks = (PB.ReadOnlyCallback(writing),),
        )
        @test_throws ErrorException step!(audited, 1)
    end
end
