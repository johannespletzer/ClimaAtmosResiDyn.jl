# Measure how the stratospheric passive tracers scale with tracer count.
#
#   usage: julia --project=.buildkite perf/tracer_scaling.jl
#
# Two numbers decide how to reach a large tracer count, and neither can be
# guessed from the source:
#
#   1. Compile time per tracer. Roughly 64 sites in `src/` unroll over
#      `gs_tracer_names(Y)`, so each tracer adds an inlined body at every one of
#      them. If that cost is superlinear, adding tracers to the prognostic state
#      stops being viable well before the state itself gets large.
#   2. Run time per tracer, against a tracer-free baseline. This says whether
#      splitting a large tracer set across several runs is cheap (dynamics is
#      the cost, and tracers ride along) or ruinous (tracers are the cost, and
#      repeating the dynamics is the cheaper half).
#
# Each tracer count runs in a fresh Julia process, because otherwise a later
# count reuses code compiled for an earlier one and its compile time reads low.
# Set TRACER_SCALING_INPROCESS=1 to run them all in this process instead, which
# is faster but only meaningful for the run-time column.
#
# The 12 x 12 ceiling below is `MAX_TRACER_LATITUDE_BANDS` x
# `MAX_TRACER_HEIGHT_BANDS`: diagnostics are registered statically at load time,
# so the model refuses a larger grid. Raising that ceiling is a prerequisite for
# any tracer count past 144, independent of what this script measures.
#
# The source-region geometry here is chosen to fit many bands into the domain,
# not to be physically sensible. This measures cost, not science.

import Random
import ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
import ClimaTimeSteppers as CTS
import Statistics
using Printf

Random.seed!(1234)

# (n_latitude_bands, n_height_bands); (0, 0) is the tracer-free baseline.
#const BAND_GRIDS = [(0, 0), (4, 8), (12, 12)]
const BAND_GRIDS = [(0, 0), (2, 4), (4, 4), (4, 8), (8, 8), (12, 12)]

const N_TIMED_STEPS = 5

"""
    probe_config(n_latitude_bands, n_height_bands)

Configuration `Dict` for one point of the sweep. Held-Suarez forcing stands in
for radiation, as in `config/model_configs/passive_stratospheric_tracers_ci.yml`:
it is cheap and still produces the tropopause the tracers are bounded by.
"""
function probe_config(n_latitude_bands, n_height_bands)
    config = Dict{String, Any}(
        "job_id" => "tracer_scaling_$(n_latitude_bands)x$(n_height_bands)",
        "config" => "sphere",
        "FLOAT_TYPE" => get(ENV, "TRACER_SCALING_FLOAT_TYPE", "Float64"),
        "h_elem" => 4,
        "nh_poly" => 3,
        "z_elem" => 31,
        "z_max" => 60000.0,
        "dz_bottom" => 30.0,
        "dt" => "150secs",
        "t_end" => "1days",  # never reached; the steps below are taken by hand
        "ode_algo" => "ARS343",
        "rad" => "held_suarez",
        "vert_diff" => "VerticalDiffusion",
        # Implicit diffusion on purpose: it is what gives every passive tracer
        # its own Jacobian block (`manual_sparse_jacobian.jl`), which is the
        # steepest per-tracer cost in the model. Set TRACER_SCALING_IMPLICIT=0
        # if this combination is rejected; the sweep then under-reports.
        "implicit_diffusion" =>
            get(ENV, "TRACER_SCALING_IMPLICIT", "1") == "1",
        "approximate_linear_solve_iters" => 1,
        "hyperdiff" => "Hyperdiffusion",
        "toml" => ["toml/sphere_held_suarez.toml"],
        "output_default_diagnostics" => false,
    )
    n_latitude_bands * n_height_bands == 0 && return config

    # Bands are packed tightly so that 12 of them still fit under the model top
    # and 12 latitude bands stay narrower than their 15 degree division.
    config["chemistry_model"] = "stratospheric_passive_tracers"
    config["tracer_source_latitude_bands"] = n_latitude_bands
    config["tracer_source_latitude_width"] = 10.0
    config["tracer_source_height_bands"] = n_height_bands
    config["tracer_source_band_depth"] = 1000.0
    config["tracer_source_band_spacing"] = 2000.0
    config["tracer_loss_timescale"] = "6hours"
    config["dt_tracer_budget"] = "1days"
    return config
end

"""
    timed_with_compilation(f)

`(value, total_seconds, compile_seconds)` for `f()`, splitting compilation out
of the wall time the way `@time`'s "% compilation time" does.
"""
function timed_with_compilation(f)
    Base.cumulative_compile_timing(true)
    compile_before = first(Base.cumulative_compile_time_ns())
    t_before = time_ns()
    value = f()
    total = (time_ns() - t_before) / 1e9
    compile = (first(Base.cumulative_compile_time_ns()) - compile_before) / 1e9
    Base.cumulative_compile_timing(false)
    return value, total, compile
end

"""
    measure(n_latitude_bands, n_height_bands)

Build the simulation and step it, returning a `NamedTuple` of timings.
"""
function measure(n_latitude_bands, n_height_bands)
    config = CA.AtmosConfig([probe_config(n_latitude_bands, n_height_bands)])

    simulation, setup_s, setup_compile_s =
        timed_with_compilation(() -> CA.get_simulation(config))
    (; integrator) = simulation

    # The first step compiles the tendencies, the Jacobian and the solve; the
    # rest are what a long run actually pays.
    _, first_step_s, first_step_compile_s =
        timed_with_compilation(() -> CTS.step!(integrator))
    step_times = map(1:N_TIMED_STEPS) do _
        @elapsed CTS.step!(integrator)
    end

    return (;
        n_tracers = n_latitude_bands * n_height_bands,
        setup_s,
        setup_compile_s,
        first_step_s,
        first_step_compile_s,
        step_s = Statistics.median(step_times),
        maxrss_gb = Sys.maxrss() / 2^30,
    )
end

const RESULT_FIELDS = (
    :n_tracers,
    :setup_s,
    :setup_compile_s,
    :first_step_s,
    :first_step_compile_s,
    :step_s,
    :maxrss_gb,
)

# A worker process reports one row on stdout; the driver parses it back.
print_result(r) =
    println("TRACER_SCALING_RESULT ", join((getfield(r, f) for f in RESULT_FIELDS), " "))

function parse_result(output)
    for line in eachline(IOBuffer(output))
        startswith(line, "TRACER_SCALING_RESULT") || continue
        values = parse.(Float64, split(line)[2:end])
        return NamedTuple{RESULT_FIELDS}(Tuple(values))
    end
    return nothing
end

function run_worker(n_latitude_bands, n_height_bands)
    command = Cmd([
        first(Base.julia_cmd()),
        "--project=$(Base.active_project())",
        "--startup-file=no",
        abspath(@__FILE__),
    ])
    environment = copy(ENV)
    environment["TRACER_SCALING_BANDS"] = "$(n_latitude_bands),$(n_height_bands)"
    output = IOBuffer()
    # The worker's stderr is left attached, so a failure is visible as it happens
    # rather than being swallowed into the buffer this parses.
    pipe = pipeline(setenv(command, environment); stdout = output, stderr = stderr)
    success(pipe) || return nothing
    return parse_result(String(take!(output)))
end

function report(results)
    baseline = findfirst(r -> r.n_tracers == 0, results)
    baseline_step = isnothing(baseline) ? nothing : results[baseline].step_s

    println()
    println("=" ^ 96)
    @printf(
        "%9s %10s %10s %11s %11s %10s %9s %9s\n",
        "tracers", "setup", "of which", "first step", "of which",
        "step", "vs base", "maxrss",
    )
    @printf(
        "%9s %10s %10s %11s %11s %10s %9s %9s\n",
        "", "(s)", "compile", "(s)", "compile", "(s)", "", "(GB)",
    )
    println("-" ^ 96)
    for r in results
        overhead =
            isnothing(baseline_step) || baseline_step == 0 ? NaN :
            100 * (r.step_s - baseline_step) / baseline_step
        # `%.0f` for the tracer count: it is an `Int` in process and a `Float64`
        # when parsed back from a worker.
        @printf(
            "%9.0f %10.1f %10.1f %11.1f %11.1f %10.3f %8.0f%% %9.2f\n",
            r.n_tracers, r.setup_s, r.setup_compile_s, r.first_step_s,
            r.first_step_compile_s, r.step_s, overhead, r.maxrss_gb,
        )
    end
    println("=" ^ 96)
    println()
    println("Read the compile columns for whether more tracers can be added at all,")
    println("and `vs base` for whether splitting them across runs is affordable.")
    println("The 12 x 12 = 144 row is the largest grid the model currently accepts.")
end

if haskey(ENV, "TRACER_SCALING_BANDS")
    bands = parse.(Int, split(ENV["TRACER_SCALING_BANDS"], ','))
    print_result(measure(bands[1], bands[2]))
else
    in_process = get(ENV, "TRACER_SCALING_INPROCESS", "0") == "1"
    results = NamedTuple[]
    for (n_latitude_bands, n_height_bands) in BAND_GRIDS
        n_tracers = n_latitude_bands * n_height_bands
        println("--- measuring $(n_tracers) tracers ---")
        result =
            in_process ? measure(n_latitude_bands, n_height_bands) :
            run_worker(n_latitude_bands, n_height_bands)
        if isnothing(result)
            println("    failed; skipping (see the error above)")
        else
            push!(results, result)
        end
    end
    isempty(results) || report(results)
end
