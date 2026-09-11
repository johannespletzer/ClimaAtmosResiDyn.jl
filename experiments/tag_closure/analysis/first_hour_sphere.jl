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

# Point 1: the same test on the C9 sphere (propose as a short Slurm job; expect base = 2.5352e20 J at 1 h).
# Steps configs/c9_sphere_enthalpy.yml per step for 2 h in several variants and
# records the closure residual E - (strat + tropo), signed and gross, after every step.
import ClimaComms as CC
CC.@import_required_backends
import ClimaAtmos as CA
import ClimaTimeSteppers as CTS

const OUT = ENV["AGENTB_OUT"]
const BASE = "experiments/tag_closure/configs/c9_sphere_enthalpy.yml"
const NEWTON = Dict{String, Any}(
    "max_newton_iters_ode" => 10,
    "use_newton_rtol" => true,
    "newton_rtol" => 1e-10,
)
const CENTRAL = Dict{String, Any}("energy_q_tot_upwinding" => "none")
const VARIANTS = [
    ("base", Dict{String, Any}()),
    ("newton", NEWTON),]

function simulation(name, overrides)
    config = CA.load_yaml_file(BASE)
    merge!(config,
        Dict{String, Any}(
            "job_id" => name, "output_dir" => joinpath(OUT, name), "t_end" => "2hours",
            "output_default_diagnostics" => false, "diagnostics" => [],
            "log_progress" => false,
        ), overrides)
    return CA.get_simulation(CA.AtmosConfig(config))
end

function residual(Y, c)
    r = @. Y.c.ρe_tot + c * Y.c.ρ - Y.c.ρe_src_tropics - Y.c.ρe_src_extratropics
    return sum(r), sum(abs.(r))
end

for (name, overrides) in VARIANTS
    t0 = time()
    sim = simulation(name, overrides)
    integ = sim.integrator
    c = integ.p.atmos.energy_source_tagging_model.offset
    dt = float(integ.dt)
    nsteps = round(Int, 7200 / dt)
    rows = Vector{NTuple{5, Float64}}()
    s0, g0 = residual(integ.u, c)
    push!(rows, (0.0, s0, g0, maximum(abs, parent(integ.u.f.u₃)), sum(integ.u.c.ρe_tot)))
    for k in 1:nsteps
        CTS.step!(integ)
        s, g = residual(integ.u, c)
        push!(
            rows,
            (
                float(integ.t),
                s,
                g,
                maximum(abs, parent(integ.u.f.u₃)),
                sum(integ.u.c.ρe_tot),
            ),
        )
    end
    open(joinpath(OUT, "$(name)_steps.csv"), "w") do io
        println(io, "t,signed,gross,max_abs_u3,int_rhoe")
        foreach(r -> println(io, join(r, ',')), rows)
    end
    println("== $name ($(round(time() - t0; digits = 1)) s incl. build), dt = $dt")
    for tt in (
        dt,
        2dt,
        3dt,
        5dt,
        10dt,
        60.0,
        120.0,
        300.0,
        600.0,
        1200.0,
        1800.0,
        3600.0,
        5400.0,
        7200.0,
    )
        i = findfirst(r -> isapprox(r[1], tt; atol = 1e-6), rows)
        isnothing(i) && continue
        r = rows[i]
        println(
            "  t = $(lpad(r[1], 7)) s  signed $(round(r[2]; sigdigits = 5))  gross $(round(r[3]; sigdigits = 6))  max|u3| $(round(r[4]; sigdigits = 3))",
        )
    end
    flush(stdout)
end
