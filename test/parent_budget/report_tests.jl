using Test
using ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
import ClimaAtmos.Internals.ParentBudget as PB
import ClimaTimeSteppers as CTS
import YAML

# Stack step 8: the claim certificate, the κ calibration and the performance
# gates.
#
# The certificate is what a run publishes: which claim levels held for which
# quantities in which control volumes, under which configuration, with every
# number the verdicts were judged against. κ is calibrated by the contract's
# protocol and committed as a table, one row per backend, float type and rank
# count; the serial row is re-measured here and must stay below κ/4. Summary
# mode is what a long run uses, so its storage is bounded and its cost per
# step does not grow.

const FT = Float64

newton() = CTS.NewtonsMethod(;
    max_iters = 1,
    update_j = CTS.UpdateEvery(CTS.NewNewtonIteration),
)

function column_simulation(; parent_budget_mode = "summary", t_end = 600, kwargs...)
    return CA.AtmosSimulation{FT}(;
        grid = CA.ColumnGrid(FT; z_elem = 10),
        dt = 60,
        t_end,
        job_id = "parent_budget_report",
        output_dir = mktempdir(),
        default_callbacks = false,
        diagnostics = CA.DiagnosticsConfig(; default = false),
        update_cache_every = "step",
        ode_config = CTS.IMEXAlgorithm(CTS.ARS343(), newton()),
        parent_budget_mode,
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

# The explicit acceptable overhead of summary mode on the dry column, per
# accepted step, beside a run without the ledger: allocations and walltime.
const SUMMARY_ALLOCATION_OVERHEAD = 256 * 1024
const SUMMARY_WALLTIME_OVERHEAD = 2e-3

@testset "Parent-budget report, calibration and performance" begin
    @testset "The calibration table is committed and read at setup" begin
        rows = PB.read_calibration_table()
        row = PB.calibration_row(rows, "CPUSingleThreaded", "Float64", 1)
        @test row isa PB.CalibrationRow
        @test row.kappa == 8.0
        @test row.configuration == PB.CALIBRATION_CONFIGURATION_NAME
        @test row.steps == PB.CALIBRATION_STEPS
        @test row.kappa >= 4 * row.worst_ratio
        @test PB.kappa_from_ratio(0.0) == 1.0
        @test PB.kappa_from_ratio(0.3) == 2.0
        @test PB.kappa_from_ratio(row.worst_ratio) == row.kappa
        @test PB.kappa_from_ratio(2.0) == 8.0
        @test PB.kappa_from_ratio(2.1) == 16.0
        # A run on this backend gets the row's κ unless it brings its own.
        tolerances = PB.calibrated_tolerances(ClimaComms.context(), Float64; rows)
        @test all(
            t -> t.kappa == 8.0 && t.absolute == 0 && t.relative == 0,
            values(tolerances),
        )
        @test isnothing(PB.calibrated_tolerances(ClimaComms.context(), Float32; rows))
        @test isnothing(
            PB.calibrated_tolerances(
                ClimaComms.context(),
                Float64;
                rows = PB.CalibrationRow[],
            ),
        )
        # A malformed row is refused rather than defaulted.
        bad = tempname() * ".yaml"
        write(
            bad,
            "version: 1\nrows:\n  - {backend: CPUSingleThreaded, float_type: Float64, ranks: 1, configuration: x, steps: 50, worst_ratio: 1.0, kappa: 3.0, commit: c, date: d}\n",
        )
        @test_throws ErrorException PB.read_calibration_table(bad)
        write(
            bad,
            "version: 1\nrows:\n  - {backend: CPUSingleThreaded, float_type: Float64, ranks: 1, configuration: x, steps: 50, worst_ratio: 1.0, kappa: 2.0, commit: c, date: d}\n",
        )
        @test_throws ErrorException PB.read_calibration_table(bad)
        write(bad, "version: 2\nrows: []\n")
        @test_throws ErrorException PB.read_calibration_table(bad)
    end

    @testset "A run takes its tolerance from the table unless it brings its own" begin
        simulation = column_simulation()
        adapter = adapter_of(simulation)
        @test adapter.tolerance_source === :calibration_table
        @test adapter.tolerances[:energy].kappa == 8.0
        step!(simulation, 2)
        for quantity in (:mass, :energy)
            @test parent_row(adapter, quantity).status === :pass
        end
        explicit = column_simulation(;
            parent_budget_tolerances = Dict(
                q => PB.BudgetTolerance(;
                    absolute = 0.0,
                    relative = 0.0,
                    scale = 1.0,
                    kappa = 64.0,
                )
                for q in PB.BUDGET_QUANTITIES
            ),
        )
        @test adapter_of(explicit).tolerance_source === :explicit
        @test adapter_of(explicit).tolerances[:energy].kappa == 64.0
        # Without a row every numeric verdict is blocked, naming the tolerance.
        Y = simulation.integrator.u
        bare = PB.build_parent_budget(
            PB.SummaryMode(),
            simulation.integrator.p.atmos,
            Y;
            ode_config = simulation.integrator.alg,
            restart = false,
            constraint_cadence = :step,
            calibration_rows = PB.CalibrationRow[],
        )
        @test bare.tolerance_source === :none
        @test isnothing(bare.tolerances)
    end

    @testset "The serial row is re-measured and stays below κ/4" begin
        config = CA.AtmosConfig(
            merge(PB.calibration_configuration(), Dict("output_dir" => mktempdir()));
            job_id = PB.CALIBRATION_CONFIGURATION_NAME,
        )
        simulation = CA.get_simulation(config)
        adapter = adapter_of(simulation)
        @test adapter.tolerance_source === :calibration_table
        adapter.tolerances = PB.parent_budget_tolerances(PB.protocol_tolerances())
        worst = 0.0
        for _ in 1:PB.CALIBRATION_STEPS
            CTS.step!(simulation.integrator)
            worst = max(worst, PB.worst_parent_ratio(PB.latest_commit(adapter)))
        end
        row = PB.calibration_row(
            PB.read_calibration_table(),
            "CPUSingleThreaded",
            "Float64",
            1,
        )
        @test worst > 0
        @test worst <= row.kappa / 4
        @test PB.kappa_from_ratio(worst) <= row.kappa
    end

    @testset "A run ends with its certificate" begin
        simulation = column_simulation(; t_end = 240)
        results = CA.solve_atmos!(simulation)
        @test results.ret_code === :success
        path = joinpath(simulation.output_dir, PB.REPORT_FILE)
        @test isfile(path)
        report = YAML.load_file(path)
        @test report["version"] == PB.REPORT_VERSION
        @test report["job_id"] == "parent_budget_report"
        @test report["steps_committed"] == 4
        @test report["last_step"] == 4
        @test report["restart"] == "none"
        configuration = report["configuration"]
        @test configuration["mode"] == "summary"
        @test configuration["attribution"] == "net"
        @test configuration["scope"] == "supported"
        @test configuration["backend"] == "CPUSingleThreaded"
        @test configuration["ranks"] == 1
        @test configuration["float_type"] == "Float64"
        @test configuration["accounting_type"] == "Float64"
        @test configuration["timestepper"]["algorithm"] == "ARS343"
        @test configuration["timestepper"]["stages"] == 4
        @test configuration["reservoirs"] == ["atmosphere"]
        @test configuration["control_volumes"] == ["atmosphere_only"]
        @test configuration["channels"] == ["explicit_main", "explicit_limited", "implicit"]
        @test report["tolerances"]["source"] == "calibration_table"
        @test report["tolerances"]["values"]["energy"]["kappa"] == 8.0
        @test !isempty(report["limitations"])
        claims = report["claims"]["atmosphere_only"]
        @test claims["energy"]["parent"]["status"] == "pass"
        @test claims["mass"]["parent"]["status"] == "pass"
        @test claims["water"]["parent"]["status"] == "not_applicable"
        @test claims["energy"]["parent"]["cumulative_abs_residual"] >= 0
        @test length(claims["energy"]["attribution"]) == 3
        # Summary mode records no measured process row, so the main channel's
        # attribution is blocked by name, and the certificate says so.
        main = only(
            filter(a -> a["channel"] == "explicit_main", claims["energy"]["attribution"]),
        )
        @test main["status"] == "blocked"
        @test any(b -> occursin("surface_turbulent_flux", b), main["blocked_by"])
        @test length(claims["energy"]["transfer"]) == 1
        @test claims["energy"]["transfer"][1]["status"] == "blocked"
        summary = PB.budget_summary(adapter_of(simulation))
        @test occursin("Control volume atmosphere_only", summary)
        @test occursin("parent energy pass", summary)
        @test occursin("tolerances from calibration_table", summary)
        # Before the first commit the certificate says so.
        fresh = column_simulation()
        @test isempty(PB.budget_report(adapter_of(fresh))["claims"])
        @test occursin("No step committed yet", PB.budget_summary(adapter_of(fresh)))
    end

    @testset "A restarted run's certificate names the boundary" begin
        first = column_simulation(; default_callbacks = true, checkpoint_frequency = 120)
        step!(first, 2)
        checkpoint =
            only(filter(f -> endswith(f, ".hdf5"), readdir(first.output_dir; join = true)))
        restarted = column_simulation(; restart_file = checkpoint)
        step!(restarted, 1)
        report = PB.budget_report(adapter_of(restarted))
        @test report["restart"]["transition"] == "verified"
        @test report["restart"]["checkpoint_step"] == 2
        @test report["restart"]["segmented"]
        @test report["steps_committed"] == 1
        @test occursin(
            "Restarted: transition verified",
            PB.budget_summary(adapter_of(restarted)),
        )
    end

    @testset "Summary mode is bounded and audit mode is not" begin
        off = column_simulation(; parent_budget_mode = "off", t_end = 6000)
        summary = column_simulation(; parent_budget_mode = "summary", t_end = 6000)
        audit = column_simulation(; parent_budget_mode = "audit", t_end = 6000)
        for simulation in (off, summary, audit)
            step!(simulation, 3)
        end
        adapter = adapter_of(summary)
        size_before = Base.summarysize(adapter)
        # Every accepted step allocates the same amount, and no more than the
        # explicit overhead beside a run without the ledger.
        allocations(simulation) =
            [(@allocated CTS.step!(simulation.integrator)) for _ in 1:4]
        off_allocations = allocations(off)
        summary_allocations = allocations(summary)
        @test allunique([summary_allocations]) && length(unique(summary_allocations)) == 1
        @test summary_allocations[1] <= off_allocations[1] + SUMMARY_ALLOCATION_OVERHEAD
        # The adapter's storage does not grow with the run, and no commit is kept.
        step!(summary, 10)
        @test Base.summarysize(adapter) == size_before
        @test isempty(adapter.commits)
        @test adapter.steps_committed == 17
        # Walltime per step stays within the explicit overhead.
        walltime(simulation) = (@elapsed step!(simulation, 10)) / 10
        off_walltime = walltime(off)
        summary_walltime = walltime(summary)
        @test summary_walltime <= off_walltime + SUMMARY_WALLTIME_OVERHEAD
        # Audit mode keeps every commit, which is why it is not the default.
        step!(audit, 10)
        @test length(adapter_of(audit).commits) == 13
        @test Base.summarysize(adapter_of(audit)) > size_before
    end
end
