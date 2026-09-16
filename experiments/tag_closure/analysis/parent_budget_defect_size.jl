# Decision 13: the size of the parent-budget solve defect against the rounding
# of the column energy, on the dry column of
# test/parent_budget/implicit_attribution_tests.jl and on the moist DYCOMS
# column, for one and three Newton iterations.
#
#   julia +1.11 --project=.buildkite experiments/tag_closure/analysis/parent_budget_defect_size.jl
#
# Run on the terrabyte login node on 2026-09-16, in the worktree of
# claude/energy-source-tag-allocations (#74) at 2067875f. Output:
# the dry column stays within 2.3 rounding units at one and three iterations;
# the moist column at dt 10 s gives 2.5e6 units at one iteration and 2.3e4
# at three.
using ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
import ClimaAtmos.Internals.ParentBudget as PB
import ClimaTimeSteppers as CTS

const FT = Float64
provisional_tolerances() = Dict(
    quantity =>
        PB.BudgetTolerance(; absolute = 0.0, relative = 0.0, scale = 1.0, kappa = 64.0)
    for quantity in PB.BUDGET_QUANTITIES
)
newton(max_iters) = CTS.NewtonsMethod(;
    max_iters,
    update_j = CTS.UpdateEvery(CTS.NewNewtonIteration),
)
dry_column(; max_iters, dt) = CA.AtmosSimulation{FT}(;
    model = CA.AtmosModel(),
    grid = CA.ColumnGrid(FT; z_elem = 10),
    dt,
    t_end = 100dt,
    job_id = "q13_dry",
    output_dir = mktempdir(),
    default_callbacks = false,
    diagnostics = CA.DiagnosticsConfig(; default = false),
    update_cache_every = "step",
    ode_config = CTS.IMEXAlgorithm(CTS.ARS343(), newton(max_iters)),
    jacobian = CA.ManualSparseJacobian(; approximate_solve_iters = 1),
    parent_budget_tolerances = provisional_tolerances(),
    parent_budget_mode = "audit",
    update_constrain_state_every = "step",
)
moist_column(; max_iters, dt) = CA.get_simulation(
    CA.AtmosConfig(
        Dict(
            "initial_condition" => "DYCOMS_RF02",
            "z_max" => 1500.0,
            "z_elem" => 30,
            "z_stretch" => false,
            "rad" => "DYCOMS",
            "microphysics_model" => "0M",
            "config" => "column",
            "FLOAT_TYPE" => "Float64",
            "dt" => "$(dt)secs",
            "t_end" => "$(100dt)secs",
            "max_newton_iters_ode" => max_iters,
            "output_default_diagnostics" => false,
            "output_dir" => mktempdir(),
            "parent_budget_mode" => "audit",
        );
        job_id = "q13_moist",
    ),
)
legs_of(adapter, process) = filter(l -> l.process === process, adapter.last_legs)
defect(adapter) = sum(
    abs(PB.budget_component(l, :energy).amount) for l in legs_of(adapter, :solve_defect);
    init = 0.0,
)

function report(label, build; nsteps = 2)
    simulation = build()
    adapter = simulation.integrator.p.parent_budget
    foreach(_ -> CTS.step!(simulation.integrator), 1:nsteps)
    floor = eps(FT) * sum(abs.(simulation.integrator.u.c.ρe_tot))
    d = defect(adapter)
    println(rpad(label, 40), " defect ", d, "   rounding floor ", floor, "   ratio ", d / floor)
    flush(stdout)
end

for dt in (60, 600)
    for max_iters in (1, 3)
        report("dry dt=$dt iters=$max_iters", () -> dry_column(; max_iters, dt))
    end
end
for dt in (10, 60)
    for max_iters in (1, 3)
        report("moist 0M dt=$dt iters=$max_iters", () -> moist_column(; max_iters, dt))
    end
end
