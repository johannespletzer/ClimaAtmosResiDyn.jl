# WP9a: where the tendencies allocate with many water tags. It builds W26's TRMM
# 0M column (`configs/w4a_trmm0m_<MODE>_6h.yml`) with NTAGS tags as
# `wp9_plume_cost.jl` does, and records every allocation of one call of
# `water_exchange_inputs!` (default mode), `implicit_tendency!` and
# `remaining_tendency!` after a warm-up call (`Profile.Allocs`, sample rate
# 1). It prints, per function, the 15 source lines inside ClimaAtmos that the
# most bytes were allocated under, with their counts.
#
#   MODE=default NTAGS=32 julia --project=<env> wp9_alloc_profile.jl
import ClimaAtmos as CA
import YAML
import Profile

mode = get(ENV, "MODE", "default")
ntags = parse(Int, get(ENV, "NTAGS", "32"))
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
simulation = CA.get_simulation(
    CA.AtmosConfig(dict; job_id = "wp9_alloc_$(mode)_n$ntags"),
)
Y = simulation.integrator.u
p = simulation.integrator.p
t = simulation.integrator.t
model = p.atmos.water_tagging_model
turbconv_model = p.atmos.turbconv_model
Yₜ = zero(Y)
Yₜ_lim = zero(Y)

calls = Pair{String, Function}[]
mode == "default" && push!(
    calls,
    "water_exchange_inputs!" =>
        () -> CA.water_exchange_inputs!(Y, p, turbconv_model, model),
)
push!(calls, "implicit_tendency!" => () -> CA.implicit_tendency!(Yₜ, Y, p, t))
push!(
    calls,
    "remaining_tendency!" => () -> CA.remaining_tendency!(Yₜ, Yₜ_lim, Y, p, t),
)
src_root = pkgdir(CA)
for (name, f) in calls
    f()
    Profile.Allocs.clear()
    Profile.Allocs.@profile sample_rate = 1 f()
    results = Profile.Allocs.fetch()
    by_line = Dict{String, Tuple{Int, Int}}()
    total = 0
    for alloc in results.allocs
        total += alloc.size
        # The innermost frame inside ClimaAtmos's source.
        frame = findfirst(
            sf ->
                startswith(string(sf.file), src_root) ||
                occursin("ClimaAtmos", string(sf.file)),
            alloc.stacktrace,
        )
        key =
            isnothing(frame) ? "outside ClimaAtmos: $(alloc.type)" :
            "$(relpath(string(alloc.stacktrace[frame].file), src_root)):$(alloc.stacktrace[frame].line) ($(alloc.type))"
        (bytes, count) = get(by_line, key, (0, 0))
        by_line[key] = (bytes + alloc.size, count + 1)
    end
    println(
        "RESULT function=$name total_bytes=$total allocations=$(length(results.allocs))",
    )
    ranked = sort(collect(by_line); by = kv -> -kv[2][1])
    for (key, (bytes, count)) in first(ranked, min(15, length(ranked)))
        println("RESULT   $bytes bytes in $count at $key")
    end
end
