# WP9a: the cost of the water tags' default-mode plume and of the model's
# tendencies against the number of tags, and the copies' build time (FINDINGS
# W30 found the plume superlinear and allocating past 8 tags, and 32 copies not
# building in 4 h).
#
#   MODE=default|copies NTAGS=2|8|16|32 LABEL=before|after \
#       julia --project=<env at the code> wp9_plume_cost.jl
#
# It builds W26's TRMM 0M column (`configs/w4a_trmm0m_<MODE>_6h.yml`) with
# NTAGS water tags: the two region tags and NTAGS - 2 source tags on the surface
# flux, and prints the build's wall time (`get_simulation`). Then, at the
# initial state, the minimum of 20 timed calls after one untimed, and the
# second call's allocations, of:
#   - `water_exchange_inputs!` and `sgs_exchange_of_water_tags!` (default mode);
#   - `implicit_tendency!` and `remaining_tendency!`, the model's whole
#     tendencies with the tags.
import ClimaAtmos as CA
import YAML

mode = get(ENV, "MODE", "default")
ntags = parse(Int, get(ENV, "NTAGS", "2"))
label = get(ENV, "LABEL", "after")
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
run_name = "wp9_plume_cost_$(label)_$(mode)_n$(ntags)"
build_seconds = @elapsed simulation =
    CA.get_simulation(CA.AtmosConfig(dict; job_id = run_name))
println("RESULT run=$run_name build_seconds=$build_seconds")
Y = simulation.integrator.u
p = simulation.integrator.p
t = simulation.integrator.t
model = p.atmos.water_tagging_model
turbconv_model = p.atmos.turbconv_model
@assert length(model.tags) == ntags

function timed(f)
    f()
    bytes = @allocated f()
    seconds = minimum(@elapsed(f()) for _ in 1:20)
    return (seconds, bytes)
end
results = Dict{String, Tuple{Float64, Int}}()
if mode == "default"
    results["exchange_inputs"] =
        timed(() -> CA.water_exchange_inputs!(Y, p, turbconv_model, model))
    Yₜ = zero(Y)
    results["exchange"] = timed(
        () -> CA.sgs_exchange_of_water_tags!(Yₜ, Y, p, turbconv_model, model),
    )
end
Yₜ = zero(Y)
results["implicit_tendency"] = timed(() -> CA.implicit_tendency!(Yₜ, Y, p, t))
Yₜ_lim = zero(Y)
results["remaining_tendency"] =
    timed(() -> CA.remaining_tendency!(Yₜ, Yₜ_lim, Y, p, t))
for key in sort(collect(keys(results)))
    (seconds, bytes) = results[key]
    println("RESULT run=$run_name part=$key seconds=$seconds bytes=$bytes")
end
