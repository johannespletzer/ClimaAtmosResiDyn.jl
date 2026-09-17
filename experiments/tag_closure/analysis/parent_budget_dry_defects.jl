# Decision 13: the dry solve defect of
# test/parent_budget/implicit_attribution_tests.jl, beside the rounding unit
# eps × ∫|ρe_tot|, for (Newton iterations, approximate solve iterations) =
# (1, 1), (3, 1) and (1, 2). Same setup as the test.
#
#   julia +1.11 --project=.buildkite experiments/tag_closure/analysis/parent_budget_dry_defects.jl
#
# Run on the terrabyte login node on 2026-09-17 in the worktree of
# claude/parent-budget-defect-test at 4c15038f (src/ as main 2f60df85).
# Output: 1.95, 1.90 and 1.95 rounding units; (1, 2) gives the same defect
# as (1, 1) to the last bit, 2.0054965205325395e-7 J/m².
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
function column_simulation(; max_iters = 1, approximate_solve_iters = 1)
    return CA.AtmosSimulation{FT}(;
        model = CA.AtmosModel(),
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
        parent_budget_mode = "audit",
        update_constrain_state_every = "step",
    )
end
legs_of(adapter, process) = filter(l -> l.process === process, adapter.last_legs)
stage_defects(adapter) =
    [PB.budget_component(l, :energy).amount for l in legs_of(adapter, :solve_defect)]

for (max_iters, approximate_solve_iters) in ((1, 1), (3, 1), (1, 2))
    simulation = column_simulation(; max_iters, approximate_solve_iters)
    adapter = simulation.integrator.p.parent_budget
    foreach(_ -> CTS.step!(simulation.integrator), 1:2)
    Y = simulation.integrator.u
    # The column integral of the energy, and of its absolute value, per unit
    # area, with the model's own quadrature.
    energy = sum(Y.c.ρe_tot)
    energy_abs = sum(abs.(Y.c.ρe_tot))
    defects = stage_defects(adapter)
    total = sum(abs, defects; init = 0.0)
    println(
        "max_iters = $max_iters, approximate_solve_iters = $approximate_solve_iters: ",
        "defect sum |.| = $total, per stage = $defects",
    )
    println(
        "    ∫ρe_tot = $energy, ∫|ρe_tot| = $energy_abs, eps × ∫|ρe_tot| = $(eps(FT) * energy_abs), ",
        "defect / (eps × ∫|ρe_tot|) = $(total / (eps(FT) * energy_abs))",
    )
    println(
        "    max |u₃| = $(maximum(abs, parent(Y.f.u₃))), max |uₕ| = $(maximum(abs, parent(Y.c.uₕ)))",
    )
    flush(stdout)
end
