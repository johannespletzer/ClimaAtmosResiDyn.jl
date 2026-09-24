# The owner's review of #104, finding 1: where the batch's time goes, against
# the number of tags. A companion of `wp4a_pr_tag_scaling.jl`.
#
#   MODE=default|copies NTAGS=2|8|32 julia --project=<env at WP4a's code> wp4a_pr_tag_breakdown.jl
#
# It builds W26's TRMM 0M column (`configs/w4a_trmm0m_<MODE>_6h.yml`) with
# NTAGS water tags as the scaling script does, and times each part of the
# batch at the initial state, the minimum of 20 timed calls after one untimed:
# the share norm, the exchange's inputs (default mode), the two sets of share
# differences (default mode), the whole split, and 3 NTAGS column integrals.
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
run_name = "wp4a_pr_tag_breakdown_$(mode)_n$(ntags)"
simulation = CA.get_simulation(CA.AtmosConfig(dict; job_id = run_name))
Y = simulation.integrator.u
p = simulation.integrator.p
t = simulation.integrator.t
model = p.atmos.water_tagging_model
@assert length(model.tags) == ntags
out = similar(p.scratch.ᶠtemp_field_level)
function timed(f)
    f()
    return minimum(@elapsed(f()) for _ in 1:20)
end
turbconv_model = p.atmos.turbconv_model
ᶜrainouts = p.scratch.ᶜtagging_q_rainouts
parts = Dict{String, Float64}()
parts["share_norm"] = timed(() -> CA.water_tag_share_norm!(p, Y))
if mode == "default"
    parts["exchange_inputs"] =
        timed(() -> CA.water_exchange_inputs!(Y, p, turbconv_model, model))
    inputs = CA.water_exchange_inputs!(Y, p, turbconv_model, model)
    (; ᶜεʲ, ᶜε̄, ᶜroom, ᶜwater_ratio, flags) = inputs
    environment_differences = CA.ShareDifferences(flags, true)
    ᶜΔφ⁰ = p.scratch.ᶜq_tag_environment
    parts["share_differences_one"] = timed(
        () -> (@. ᶜΔφ⁰ = environment_differences(ᶜεʲ, ᶜε̄, ᶜroom, ᶜwater_ratio)),
    )
end
parts["split_all"] = timed(() -> CA.add_split_rainout!(ᶜrainouts, Y, p, model))
ᶜtag = CA.tag_field(ᶜrainouts, first(model.tags))
parts["integrals_3n"] = timed(
    () -> for _ in 1:(3 * ntags)
        CA.Operators.column_integral_definite!(out, ᶜtag)
    end,
)
parts["update_batch"] = timed(() -> CA.update_water_tag_rainouts!(Y, p, t))
split_bytes = (CA.add_split_rainout!(ᶜrainouts, Y, p, model);
@allocated CA.add_split_rainout!(ᶜrainouts, Y, p, model))
println(
    "RESULT run=$run_name ntags=$ntags split_bytes=$split_bytes " *
    join(("$k=$(parts[k])" for k in sort(collect(keys(parts)))), " "),
)
