# The owner's review of #104, finding 5: how much of the 0M rain-out that the
# split attributes comes from a subdomain whose area is negative, where the
# rain-out is a gain, at the states the diagnostics see.
#
#   MODE=default|copies julia --project=<env at WP4a's code> wp4a_negative_area_probe.jl
#
# It runs W26's TRMM 0M column for 6 h (`configs/w4a_trmm0m_<MODE>_6h.yml`,
# without its diagnostics) and after every step reads the two subdomains'
# rain-out as `pr_tag` reads it (`_rainout_updraft`, `_rainout_environment`).
# Per step it takes the column integrals of
#   total    |Δʲ| + |Δ⁰|,
#   negative the same where that subdomain's ρa < 0,
#   gain     max(Δʲ, 0) + max(Δ⁰, 0),
# and writes them to OUTDIR/<run>.csv. It prints the largest per-step fractions
# of the total, over steps whose total is at least 1e-3 of the run's largest,
# and the fractions of the run's summed total.
import ClimaAtmos as CA
import YAML
const lazy = CA.lazy

mode = get(ENV, "MODE", "default")
outdir = get(ENV, "OUTDIR", pwd())
mkpath(outdir)
here = @__DIR__
config_path = joinpath(here, "..", "..", "configs", "w4a_trmm0m_$(mode)_6h.yml")
dict = Dict{String, Any}(YAML.load_file(config_path))
dict["diagnostics"] = []
# The run trees run from the repository's root; here the paths are made absolute.
dict["toml"] = [joinpath(pkgdir(CA), path) for path in dict["toml"]]
dict["output_dir"] = mktempdir(pwd())
run_name = "wp4a_negative_area_$(mode)"
simulation = CA.get_simulation(CA.AtmosConfig(dict; job_id = run_name))
integrator = simulation.integrator
commit = try
    readchomp(`git -C $(pkgdir(CA)) rev-parse --short HEAD`)
catch
    "?"
end
@info "probing" run_name commit
t_end = CA.time_to_seconds(dict["t_end"])
p = integrator.p
turbconv_model = p.atmos.turbconv_model
column(ᶜx) = (
    out = similar(p.scratch.ᶠtemp_field_level);
    CA.Operators.column_integral_definite!(out, ᶜx);
    only(parent(out))
)
rows = NTuple{4, Float64}[]
while CA.time_to_seconds(integrator.t) < t_end - 1e-6
    CA.CTS.step!(integrator)
    Y = integrator.u
    ᶜΔʲ = CA._rainout_updraft(Y, p)
    ᶜΔ⁰ = CA._rainout_environment(Y, p)
    ᶜρaʲ = Y.c.sgsʲs.:(1).ρa
    ᶜρa⁰ = @. lazy(CA.ρa⁰(Y.c.ρ, Y.c.sgsʲs, turbconv_model))
    ᶜtotal = @. lazy(abs(ᶜΔʲ) + abs(ᶜΔ⁰))
    ᶜnegative = @. lazy(
        ifelse(ᶜρaʲ < 0, abs(ᶜΔʲ), zero(ᶜΔʲ)) +
        ifelse(ᶜρa⁰ < 0, abs(ᶜΔ⁰), zero(ᶜΔ⁰))
    )
    ᶜgain = @. lazy(max(ᶜΔʲ, 0) + max(ᶜΔ⁰, 0))
    total = column(ᶜtotal)
    negative = column(ᶜnegative)
    gain = column(ᶜgain)
    push!(rows, (CA.time_to_seconds(integrator.t), total, negative, gain))
end
open(joinpath(outdir, "$run_name.csv"), "w") do io
    println(io, "t_seconds,total,negative_area,gain")
    for row in rows
        println(io, join(repr.(row), ","))
    end
end
largest = maximum(row[2] for row in rows)
raining = filter(row -> row[2] >= 1e-3 * largest && row[2] > 0, rows)
max_negative = isempty(raining) ? NaN : maximum(row[3] / row[2] for row in raining)
max_gain = isempty(raining) ? NaN : maximum(row[4] / row[2] for row in raining)
summed = sum(row[2] for row in rows)
println("RESULT run=$run_name commit=$commit steps=$(length(rows)) raining_steps=$(length(raining))")
println("RESULT per_step_max negative_area_fraction=$max_negative gain_fraction=$max_gain")
println(
    "RESULT run_sum negative_area_fraction=$(sum(row[3] for row in rows) / summed) " *
    "gain_fraction=$(sum(row[4] for row in rows) / summed)",
)
