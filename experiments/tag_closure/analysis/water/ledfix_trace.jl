#=
W53, stage B: the switch and the trace of V5's `led_fix` at site 23
(design/NEGATIVE_PARENT_WATER.md, section 11.12, pre-registered before it runs).

    LEDFIX_ARM=rev|switch \
    CONFIG=experiments/tag_closure/configs/lf_<arm>_s23.yml \
    DRIVER=experiments/tag_closure/analysis/water/ledfix_trace.jl \
        experiments/tag_closure/runscripts/submit_g3.sh ...

Optional: `LEDFIX_WINDOWS` (default `11.25-11.75,15.75-16.0,55.75-56.25`),
`LEDFIX_UNIT` (`days`, the default, or `seconds`, for a short check) and
`LEDFIX_LEVELS` (1-based, default `8,9,10,11,12,13,14`, 310 m to 764 m).

`run_tag_closure.jl`'s run, with two things added:

  - **The switch** (`LEDFIX_ARM=switch`). Before the simulation is built, the
    three methods that give the rule `TargetGain()` its numbers are redefined
    to those of `ParentGain()`, the rule before the revision: a tag's gain is
    `max(Δ, 0)` wherever the parent is, nothing is withheld, and the copies'
    split change is `x`. Every bracket then gives the parent's gain, as on
    `main`. No file of the run tree changes. The job id must contain the arm's
    name, so that the configuration names the arm.
  - **The trace.** In each window, after every step, the driver writes the
    end-of-step values of the parent, the region tags and their ledgers at
    the traced levels, and their column integrals (as level 0). The first row
    of a window is the state at its first step's start. Rows go to
    `<job_id>_trace.csv` in the run's output directory.

After the last window the run continues with `solve_atmos!` to `t_end`.
Nothing here is deleted.
=#
include(joinpath(@__DIR__, "..", "..", "run_tag_closure.jl"))

const ARM = get(ENV, "LEDFIX_ARM", "")
ARM in ("rev", "switch") || error("LEDFIX_ARM must be rev or switch, not \"$ARM\"")
const UNIT = get(ENV, "LEDFIX_UNIT", "days") == "seconds" ? 1.0 : 86400.0
const WINDOWS =
    map(split(get(ENV, "LEDFIX_WINDOWS", "11.25-11.75,15.75-16.0,55.75-56.25"), ",")) do w
        a, b = parse.(Float64, split(w, "-"))
        (a * UNIT, b * UNIT)
    end
const LEVELS = parse.(Int, split(get(ENV, "LEDFIX_LEVELS", "8,9,10,11,12,13,14"), ","))
seconds(x) = Float64(CA.time_to_seconds(x))
in_window(t) = any(((a, b),) -> a - 1e-6 <= t < b - 1e-6, WINDOWS)

# The switch: the rule before the revision, `ParentGain()`'s three numbers,
# under the name the brackets call. Redefined before anything is compiled for
# this run, so every bracket's kernel takes them.
if ARM == "switch"
    @eval CA.water_tag_gain(::CA.TargetGain, Δ, ρq_tot) = max(Δ, 0)
    @eval CA.water_tag_withheld_gain(::CA.TargetGain, Δ, ρq_tot) = zero(Δ)
    @eval CA.water_tag_split_change(::CA.TargetGain, x, ρq_tot) = x
end

# The fields traced, in this order. Each must be in the state.
const FIELDS = (
    :ρq_tot,
    :ρq_tag_pbl,
    :ρq_tag_free,
    :q_tag_led_fix_pbl,
    :q_tag_led_fix_free,
    :q_tag_led_inc_pbl,
    :q_tag_led_inc_free,
    :q_tag_exp_negative,
    :q_tag_inc_negative,
)

function main_trace()
    # The arm's own check, before anything runs: a gain where the parent is
    # below zero reaches the tags under the switch, and not under the rule.
    gain = CA.water_tag_gain(CA.TargetGain(), 1.0, -1.0)
    withheld = CA.water_tag_withheld_gain(CA.TargetGain(), 1.0, -1.0)
    expected = ARM == "switch" ? (1.0, 0.0) : (0.0, 1.0)
    (gain, withheld) == expected ||
        error("the arm $ARM gives gain $gain and withheld $withheld, not $expected")
    @info "The arm" ARM gain withheld

    path = config_path()
    simulation = CA.get_simulation(CA.AtmosConfig(path))
    integrator = simulation.integrator
    job_id = simulation.job_id
    occursin(ARM, job_id) || error("job id $job_id does not name the arm $ARM")
    outdir = simulation.output_dir
    Y = integrator.u
    for f in FIELDS
        hasproperty(Y.c, f) || error("the state has no field $f")
    end

    space = axes(Y.c)
    weights = vec(Array(parent(CA.ClimaCore.Spaces.weighted_jacobian(space))))
    z = vec(Array(parent(CA.ClimaCore.Fields.coordinate_field(space).z)))
    length(weights) == length(z) || error("not a single column")
    total = Float64(sum(Y.c.ρq_tot))
    by_level = sum(weights .* vec(Array(parent(Y.c.ρq_tot))))
    @assert abs(by_level - total) <= 1e-10 * max(abs(total), eps()) (by_level, total)
    all(l -> 1 <= l <= length(z), LEVELS) ||
        error("a traced level is outside 1:$(length(z))")
    @info "The trace" job_id outdir WINDOWS LEVELS z_traced = z[LEVELS]

    header = ["t_seconds", "step_end", "level", "z_m", String.(FIELDS)...]
    csv = joinpath(outdir, "$(job_id)_trace.csv")
    io = open(csv, "w")
    println(io, join(header, ","))
    function write_rows(t, step_end)
        values = map(f -> vec(Array(parent(getproperty(integrator.u.c, f)))), FIELDS)
        println(
            io,
            join([t, step_end, 0, 0.0, (sum(weights .* v) for v in values)...], ","),
        )
        for l in LEVELS
            println(io, join([t, step_end, l, z[l], (v[l] for v in values)...], ","))
        end
    end

    t_last = maximum(last, WINDOWS)
    steps = 0
    was_in = false
    while seconds(integrator.t) < t_last - 1e-6
        t = seconds(integrator.t)
        now_in = in_window(t)
        now_in && !was_in && write_rows(t, 0)
        CA.CTS.step!(integrator)
        if now_in
            write_rows(seconds(integrator.t), 1)
            steps += 1
            steps % 500 == 0 && flush(io)
        end
        was_in = now_in
    end
    close(io)
    @info "The trace finished" csv steps
    println("TRACE run=$job_id arm=$ARM steps=$steps csv=$csv")

    result = CA.solve_atmos!(simulation)
    @info "Tag-closure run finished" job_id result.ret_code
    print_closure_summary(outdir)
    if result.ret_code != :success
        @error "The solve did not succeed." result.ret_code
        exit(1)
    end
    return nothing
end

main_trace()
