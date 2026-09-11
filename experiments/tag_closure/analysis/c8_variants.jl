#=
Where the tags' leftover residuals come from: the one-iteration Newton
increment (FINDINGS E39). A reviewer agent wrote these scripts on 2026-09-11 and
ran them on the terrabyte login node. Their outputs are in
`output/newton_lag/`.

  - `first_hour_0m.jl` steps C9's column one step at a time, in five variants:
    one Newton iteration, a converged solve, no post-Newton upwind correction,
    both, and a 5 s step.
  - `c8_variants.jl` does the same for C8's 1M column. Only its first 60 audit
    steps ran here, because the 1M build takes about 20 minutes on the login
    node. `first_hour_sphere.jl` is the sphere's two-hour test. Both are meant
    for short Slurm jobs.
  - `formb_vs_flux.py`, `after_first_hour.py`, `signed_by_loss_rule.py` and
    `sphere_levels.py` read the per-step tables and the runs' NetCDF.

The paths inside point to the scratch directory they ran from. Change the output
directory before running them again.
=#

# Points 2 and 3: C8's 1M column with the tags moved as enthalpy, and with a
# converged Newton solve. Records per step the closure residual E - (strat + tropo),
# form B, and the column integral of the precipitation record; hourly form A.
import ClimaComms as CC
CC.@import_required_backends
import ClimaAtmos as CA
import ClimaTimeSteppers as CTS

const OUT = ENV["AGENTB_OUT"]
const BASE = "experiments/tag_closure/configs/c8_column_1m.yml"
const NEWTON = Dict{String, Any}(
    "max_newton_iters_ode" => 10,
    "use_newton_rtol" => true,
    "newton_rtol" => 1e-10,
)
const ENTH = Dict{String, Any}("energy_source_tag_transport" => "enthalpy")
const VARIANTS = [
    ("enthalpy", ENTH, 86400.0),
    ("enthalpy_newton", merge(ENTH, NEWTON), 86400.0),
    ("tracer_newton", NEWTON, 3600.0),
    ("tracer", Dict{String, Any}(), 3600.0),
]
const RECORDS = (
    :prc_e_radiation,
    :prc_e_surface_flux,
    :prc_e_subsidence,
    :prc_e_microphysics,
    :prc_e_precipitation,
)
const NEW = (:ρe_src_new_strat, :ρe_src_new_tropo)
const PROC = (:ρe_src_rad, :ρe_src_sfc, :ρe_src_sub, :ρe_src_mp)

function simulation(name, overrides, t_end)
    config = CA.load_yaml_file(BASE)
    merge!(config,
        Dict{String, Any}(
            "job_id" => name, "output_dir" => joinpath(OUT, name),
            "t_end" => "$(Int(t_end))secs",
            "output_default_diagnostics" => false, "diagnostics" => [],
            "log_progress" => false,
        ), overrides)
    return CA.get_simulation(CA.AtmosConfig(config))
end

function residual(Y, c)
    r = @. Y.c.ρe_tot + c * Y.c.ρ - Y.c.ρe_src_strat - Y.c.ρe_src_tropo
    return sum(r), sum(abs.(r))
end
records(Y) = sum(sum(getproperty(Y.c, n)) for n in RECORDS)
fieldsum(obj, names) = (
    f = zero.(getproperty(obj, first(names)));
    foreach(n -> (f .+= getproperty(obj, n)), names);
    f
)

function form_a(Y, p)
    fix = p.tagging.ᶜenergy_source_fix
    gap = parent((fieldsum(Y.c, NEW) .- fieldsum(Y.c, PROC)) ./ Y.c.ρ)[:]
    ledger = parent((fieldsum(fix, NEW) .- fieldsum(fix, PROC)) ./ Y.c.ρ)[:]
    k = argmax(abs.(gap))
    z = parent(CA.Fields.coordinate_field(Y.c).z)[:]
    return maximum(abs, gap), z[k], maximum(abs, gap .- ledger), maximum(abs, ledger)
end

for (name, overrides, t_end) in VARIANTS
    t0 = time()
    sim = simulation(name, overrides, t_end)
    integ = sim.integrator
    Y = integ.u
    c = integ.p.atmos.energy_source_tagging_model.offset
    dt = float(integ.dt)
    E0 = sum(Y.c.ρe_tot)
    steps = open(joinpath(OUT, "$(name)_steps.csv"), "w")
    println(steps, "t,signed,gross,form_b,int_prec,int_rho")
    hourly = open(joinpath(OUT, "$(name)_hourly.csv"), "w")
    println(
        hourly,
        "t,signed,gross,form_b,form_a_max,form_a_z,form_a_unrepaired,ledger_max",
    )
    println("== $name, dt = $dt, t_end = $t_end")
    for k in 1:round(Int, t_end / dt)
        CTS.step!(integ)
        s, g = residual(Y, c)
        fb = (sum(Y.c.ρe_tot) - E0) - records(Y)
        println(
            steps,
            join((float(integ.t), s, g, fb, sum(Y.c.prc_e_precipitation), sum(Y.c.ρ)), ','),
        )
        if k % round(Int, 600 / dt) == 0
            fa, zf, fau, lm = form_a(Y, integ.p)
            println(hourly, join((float(integ.t), s, g, fb, fa, zf, fau, lm), ','))
            (k % round(Int, 3600 / dt) == 0 || float(integ.t) <= 3600) && println(
                "  t = $(lpad(round(Int, float(integ.t)), 6)) s  signed $(round(s; sigdigits = 5))  gross $(round(g; sigdigits = 6))  formB $(round(fb; sigdigits = 4))  formA $(round(fa; sigdigits = 4)) at z = $zf  unrepaired $(round(fau; sigdigits = 4))  ledger $(round(lm; sigdigits = 3))",
            )
            flush(stdout);
            flush(steps);
            flush(hourly)
        end
    end
    close(steps);
    close(hourly)
    println("  done in $(round(time() - t0; digits = 1)) s incl. build")
end
