#=
Where the build time of an EDMF column with tags goes, stage by stage (P4).

    julia +1.11 --project=<worktree>/.buildkite \
        experiments/tag_closure/analysis/p4_build_stages.jl <config.yml>

P4's split test found that tags and records make the EDMF build slow, faster
than their number grows, and that most of the time lies outside the three build
stages the driver logs (FINDINGS E44b). This script times every stage of the
build and of the first steps, and prints each time as soon as it has it, so a
job stopped at its limit still says where it was.

  1. loading ClimaAtmos;
  2. `AtmosConfig` and `get_simulation`, which logs the cache, the tendency
     function and the integrator itself;
  3. single calls of the pieces the first step compiles: the precomputed
     quantities, the explicit tendency, the implicit tendency and the Jacobian
     update. Each is called twice, so the first call's time less the second's is
     its compile time;
  4. the first step and the second step;
  5. the rest of the run.

Each stage runs inside `try`, so a stage that fails prints its error and the
next still runs. Calling the pieces on the integrator's own state changes its
caches, and that is fine here: nothing of the run is read but its times.

The model refuses `prognostic_edmfx` with energy source tags since `57ed9c1f`,
so a run with tags uses the model of a worktree from before that, as P4 did.
=#

const T_START = time()

using Printf
import ClimaComms as CC
CC.@import_required_backends
import ClimaAtmos as CA
import ClimaTimeSteppers as CTS

function report(label, seconds)
    @printf(
        "[p4] %-44s %9.1f s   (since start %7.1f s)\n",
        label,
        seconds,
        time() - T_START
    )
    flush(stdout)
    return nothing
end

# Call `f(args...)` and print how long it took. The call goes through
# `invokelatest`, which inference cannot see through. So `f` is inferred and
# compiled inside the timer, and not ahead of it, when `timed` is compiled. A
# first version called a closure directly, and its first calls read 0.0 s while
# the clock since the start moved by half a minute.
function timed(label, f, args...; kwargs...)
    t0 = time()
    try
        result = Base.invokelatest(f, args...; kwargs...)
        report(label, time() - t0)
        return result
    catch err
        report(label * " FAILED", time() - t0)
        println("[p4]   ", first(sprint(showerror, err), 600))
        flush(stdout)
        return nothing
    end
end

function main(path)
    report("loading ClimaAtmos", time() - T_START)
    name = splitext(basename(path))[1]
    config = timed("AtmosConfig", CA.AtmosConfig, path; job_id = "stages_$name")
    simulation = timed("get_simulation", CA.get_simulation, config)
    isnothing(simulation) && return nothing
    integrator = simulation.integrator
    Y = integrator.u
    p = integrator.p
    t = integrator.t
    FT = eltype(Y)
    dtγ = FT(float(integrator.dt))
    problem = hasproperty(integrator, :prob) ? integrator.prob : integrator.sol.prob
    f = problem.f
    println("[p4] prognostic fields: ", propertynames(Y.c))
    flush(stdout)

    for call in 1:2
        timed("precomputed quantities, call $call", CA.set_precomputed_quantities!, Y, p, t)
    end
    Yₜ = zero(Y)
    Yₜ_lim = zero(Y)
    for call in 1:2
        timed("explicit tendency, call $call", CA.remaining_tendency!, Yₜ, Yₜ_lim, Y, p, t)
    end
    for call in 1:2
        timed("implicit tendency, call $call", CA.implicit_tendency!, Yₜ, Y, p, t)
    end
    T_imp! = f.T_imp!
    if !isnothing(T_imp!)
        W = T_imp!.jac_prototype
        for call in 1:2
            timed("Jacobian update, call $call", T_imp!.Wfact, W, Y, p, dtγ, t)
        end
    end

    timed("first step", CTS.step!, integrator)
    timed("second step", CTS.step!, integrator)
    timed("the rest of the run", CA.solve_atmos!, simulation)
    report("done", 0.0)
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    isempty(ARGS) && error("Usage: p4_build_stages.jl <config.yml>")
    main(abspath(only(ARGS)))
end
