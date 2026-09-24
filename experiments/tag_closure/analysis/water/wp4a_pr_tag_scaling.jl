# The owner's review of #104, finding 1: the cost of emitting `pr_tag`,
# `prra_tag` and `prsn_tag` for every tag at one output time, against the
# number of tags.
#
#   MODE=default|copies NTAGS=2|8|32 julia --project=<env at WP4a's code> wp4a_pr_tag_scaling.jl
#
# It builds W26's TRMM 0M column (`configs/w4a_trmm0m_<MODE>_6h.yml`) with
# NTAGS water tags: the two region tags and NTAGS - 2 source tags on the
# surface flux, and times, at the initial state:
#   batch    one output pass as the diagnostics make it now: the batch
#            (`update_water_tag_rainouts!`) and then 3 NTAGS column integrals;
#   per_call the same 3 NTAGS diagnostics at #104's reviewed head (53cd2db3),
#            where each call redid the shared work for its one tag.
# Each is the minimum of 20 timed passes after one untimed pass. The two paths
# are checked to give the same values.
import ClimaAtmos as CA
import YAML

mode = get(ENV, "MODE", "default")
ntags = parse(Int, get(ENV, "NTAGS", "2"))
outdir = get(ENV, "OUTDIR", pwd())
mkpath(outdir)
here = @__DIR__
dict = Dict{String, Any}(
    YAML.load_file(
        joinpath(here, "..", "..", "configs", "w4a_trmm0m_$(mode)_6h.yml"),
    ),
)
dict["diagnostics"] = []
dict["output_dir"] = mktempdir(pwd())
dict["toml"] = [joinpath(pkgdir(CA), path) for path in dict["toml"]]
dict["water_tracers"] = [
    dict["water_tracers"][1:2]...,
    [
        Dict{String, Any}("name" => "src$k", "source" => "surface_flux") for
        k in 1:(ntags - 2)
    ]...,
]
run_name = "wp4a_pr_tag_scaling_$(mode)_n$(ntags)"
simulation = CA.get_simulation(CA.AtmosConfig(dict; job_id = run_name))
Y = simulation.integrator.u
p = simulation.integrator.p
t = simulation.integrator.t
model = p.atmos.water_tagging_model
@assert length(model.tags) == ntags
phases = (Val(:all), Val(:rain), Val(:snow))
out = similar(p.scratch.ᶠtemp_field_level)
T_freeze = CA.TD.Parameters.T_freeze(CA.CAP.thermodynamics_params(p.params))

function batch_pass!(out, Y, p, t, tags, phases)
    p.scratch.tagging_q_rainout_time[] = NaN
    for tag in tags, phase in phases
        CA.water_tag_precipitation!(out, Y, p, t, tag, phase)
    end
end
# #104's reviewed head: one tag into one scratch field per call.
function per_call_pass!(out, Y, p, tags, phases, ᶜscratch, T_freeze, model)
    for tag in tags, phase in phases
        fill!(parent(ᶜscratch), 0)
        CA.add_rainout_increments!(
            CA.tag_entry(tag, ᶜscratch),
            Y,
            p,
            model,
            tag,
        )
        CA.Operators.column_integral_definite!(
            out,
            CA._precipitation_phase(ᶜscratch, p.precomputed.ᶜT, T_freeze, phase),
        )
    end
end
ᶜscratch = similar(Y.c.ρ)
function timed(f)
    f()
    return minimum(@elapsed(f()) for _ in 1:20)
end
batch = timed(() -> batch_pass!(out, Y, p, t, model.tags, phases))
per_call = timed(
    () -> per_call_pass!(out, Y, p, model.tags, phases, ᶜscratch, T_freeze, model),
)
# The same values both ways.
difference = 0.0
for tag in model.tags
    CA.water_tag_precipitation!(out, Y, p, t, tag, Val(:all))
    new = copy(parent(out))
    per_call_pass!(out, Y, p, (tag,), (Val(:all),), ᶜscratch, T_freeze, model)
    global difference = max(difference, maximum(abs, new .- parent(out)))
end
commit = try
    readchomp(`git -C $(pkgdir(CA)) rev-parse --short HEAD`)
catch
    "?"
end
println(
    "RESULT run=$run_name commit=$commit ntags=$ntags diagnostics=$(3 * ntags) " *
    "batch_seconds=$batch per_call_seconds=$per_call max_abs_difference=$difference",
)
open(joinpath(outdir, "$run_name.csv"), "w") do io
    println(io, "mode,ntags,diagnostics,batch_seconds,per_call_seconds,max_abs_difference")
    println(io, "$mode,$ntags,$(3 * ntags),$batch,$per_call,$difference")
end
