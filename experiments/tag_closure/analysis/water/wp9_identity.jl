# WP9a: write the plume and the exchange's tendency at TRMM's initial state,
# with NTAGS tags in the default mode (as `wp9_plume_cost.jl`), as raw bits to
# OUTDIR/<LABEL>_n<NTAGS>.bin, so that two codes can be compared bit for bit.
#
#   LABEL=before|after NTAGS=32 OUTDIR=... julia --project=<env> wp9_identity.jl
import ClimaAtmos as CA
import YAML

label = ENV["LABEL"]
ntags = parse(Int, get(ENV, "NTAGS", "32"))
outdir = ENV["OUTDIR"]
mkpath(outdir)
here = @__DIR__
dict = Dict{String, Any}(
    YAML.load_file(joinpath(here, "..", "..", "configs", "w4a_trmm0m_default_6h.yml")),
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
simulation =
    CA.get_simulation(CA.AtmosConfig(dict; job_id = "wp9_identity_$(label)_n$ntags"))
Y = simulation.integrator.u
p = simulation.integrator.p
model = p.atmos.water_tagging_model
CA.water_exchange_inputs!(Y, p, p.atmos.turbconv_model, model)
Yₜ = zero(Y)
CA.sgs_exchange_of_water_tags!(Yₜ, Y, p, p.atmos.turbconv_model, model)
open(joinpath(outdir, "$(label)_n$ntags.bin"), "w") do io
    write(io, vec(parent(p.scratch.ᶜq_tag_mean)))
    write(io, vec(parent(p.scratch.ᶜq_tag_plume)))
    write(io, vec(parent(Yₜ)))
end
println("RESULT wrote $(label)_n$ntags.bin")
