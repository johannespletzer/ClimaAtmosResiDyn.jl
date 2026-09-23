# Decision 13, review of #81: does a dry column with a uniform 10 m/s wind
# (ConstantBuoyancyFrequencyProfile), otherwise like the one of
# test/parent_budget/implicit_attribution_tests.jl, with implicit vertical
# diffusion, leave a solve defect far above rounding at one Newton iteration,
# and less at three? Same setup as the test, plus the diffusion.
#
#   julia +1.11 --project=.buildkite experiments/tag_closure/analysis/parent_budget_defect_dry_wind.jl
#
# Run on the terrabyte login node on 2026-09-17 in the worktree of
# claude/parent-budget-defect-test at e88f5c31 (src/ as main 2f60df85),
# with implicit diffusion confirmed (`AtmosModel(; diff_mode)` gives
# `Implicit()`). Output: every defect is rounding, at most 8.0 units, on
# both grids, and three Newton iterations do not shrink it reliably.
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
const PARAMS = CA.ClimaAtmosParameters(FT)
const VDP = CA.Parameters.vert_diff_params(PARAMS)
println("vert_diff_params = ", VDP)

diffusion_models = (
    decay_with_height = CA.DecayWithHeightDiffusion{FT}(;
        disable_momentum_vertical_diffusion = false,
        H = VDP.H,
        D₀ = VDP.D₀,
    ),
    surface_driven = CA.VerticalDiffusion{FT}(;
        disable_momentum_vertical_diffusion = false,
        C_E = VDP.C_E,
    ),
)

function column_simulation(;
    vertical_diffusion,
    max_iters,
    approximate_solve_iters,
    dt,
    grid,
)
    return CA.AtmosSimulation{FT}(;
        model = CA.AtmosModel(; vertical_diffusion, diff_mode = CA.Implicit()),
        grid,
        setup = CA.Setups.ConstantBuoyancyFrequencyProfile(),
        dt,
        t_end = 100dt,
        job_id = "q13_windy",
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
defect(adapter) = sum(
    abs(PB.budget_component(l, :energy).amount) for l in legs_of(adapter, :solve_defect);
    init = 0.0,
)
function parent_status(adapter, quantity)
    rows = filter(
        r -> r.quantity === quantity && r.control_volume === :atmosphere_only,
        PB.latest_commit(adapter).parent,
    )
    return only(rows).status
end

grids = (
    default = () -> CA.ColumnGrid(FT; z_elem = 10),
    fine = () -> CA.ColumnGrid(FT; z_elem = 30, dz_bottom = 50.0),
)
for (gname, grid) in pairs(grids),
    (name, vertical_diffusion) in pairs(diffusion_models),
    dt in (60, 600)

    for (max_iters, approximate_solve_iters) in ((1, 1), (3, 1), (1, 2))
        label = "$gname $name dt=$dt newton=$max_iters approx=$approximate_solve_iters"
        try
            simulation = column_simulation(;
                vertical_diffusion,
                max_iters,
                approximate_solve_iters,
                dt,
                grid = grid(),
            )
            adapter = simulation.integrator.p.parent_budget
            foreach(_ -> CTS.step!(simulation.integrator), 1:2)
            Y = simulation.integrator.u
            unit = eps(FT) * sum(abs.(Y.c.ρe_tot))
            d = defect(adapter)
            println(
                rpad(label, 50),
                " defect ", d, "  units ", d / unit,
                "  energy ", parent_status(adapter, :energy),
                "  mass ", parent_status(adapter, :mass),
                "  max|uₕ| ", maximum(abs, parent(Y.c.uₕ)),
            )
        catch err
            println(rpad(label, 50), " ERROR ", sprint(showerror, err)[1:min(end, 400)])
        end
        flush(stdout)
    end
end
