# T3: where remaining_tendency! allocates, with and without tags. The first
# exploration found 58,160 bytes per call with tags and 22,576 without.
#
# Run from the root of a worktree at the commit under test, on a login node:
#   julia +1.11 --project=.buildkite experiments/tag_closure/analysis/t3_allocation_profile.jl
# T3_TAGS=false runs it without tags. Output groups Profile.Allocs by the innermost ClimaAtmos frame. FINDINGS T10.

import ClimaAtmos as CA
import ClimaComms
ClimaComms.@import_required_backends
import Profile

with_tags = get(ENV, "T3_TAGS", "true") == "true"

tags = [
    Dict{String, Any}(
        "name" => "strat",
        "region" => Dict{String, Any}(
            "type" => "tanh_altitude",
            "z_center" => 750.0,
            "width" => 100.0,
        ),
    ),
    Dict{String, Any}(
        "name" => "tropo",
        "region" => Dict{String, Any}(
            "type" => "tanh_altitude",
            "z_center" => 750.0,
            "width" => 100.0,
            "above" => false,
        ),
    ),
    Dict{String, Any}("name" => "rad", "source" => "radiation"),
    Dict{String, Any}("name" => "sfc", "source" => "surface_flux"),
]
test_dict = Dict{String, Any}(
    "config" => "column",
    "initial_condition" => "DYCOMS_RF02",
    "z_max" => 1500.0,
    "z_elem" => 30,
    "z_stretch" => false,
    "rad" => "DYCOMS",
    "microphysics_model" => "1M",
    "fixed_terminal_velocity_liquid" => false,
    "dt" => "10secs",
    "t_end" => "20secs",
    "FLOAT_TYPE" => "Float64",
    "output_default_diagnostics" => false,
    "output_dir" => mktempdir(),
)
if with_tags
    test_dict["energy_source_tags"] = tags
    test_dict["energy_source_tag_offset"] = 50000.0
    test_dict["energy_process_record"] = ["radiation", "precipitation", "surface_flux"]
end

simulation = CA.get_simulation(CA.AtmosConfig(test_dict; job_id = "t3_allocs_profile"))
Y = simulation.integrator.u
p = simulation.integrator.p
t = simulation.integrator.t

function measure(label, f::F, args...) where {F}
    f(args...)
    a1 = @allocated f(args...)
    a2 = @allocated f(args...)
    println(rpad(label, 44), " allocs ", a1, " / ", a2)
    flush(stdout)
end

Yₜ = zero(Y)
Yₜ_lim = zero(Y)
measure("remaining_tendency!", CA.remaining_tendency!, Yₜ, Yₜ_lim, Y, p, t)
measure("horizontal_tracer_advection_tendency!", CA.horizontal_tracer_advection_tendency!, Yₜ_lim, Y, p, t)
measure("horizontal_dynamics_tendency!", CA.horizontal_dynamics_tendency!, Yₜ, Y, p, t)
measure("hyperdiffusion_tendency!", CA.hyperdiffusion_tendency!, Yₜ, Yₜ_lim, Y, p, t)
measure("explicit_vertical_advection_tendency!", CA.explicit_vertical_advection_tendency!, Yₜ, Y, p, t)
measure("additional_tendency!", CA.additional_tendency!, Yₜ, Y, p, t)
measure("surface_flux_tendency!", CA.surface_flux_tendency!, Yₜ, Y, p, t)
measure("radiation_tendency!", CA.radiation_tendency!, Yₜ, Y, p, t, p.atmos.radiation_mode)
measure("subsidence_tendency!", CA.subsidence_tendency!, Yₜ, Y, p, t, p.atmos.subsidence)

# Every allocation in one call, grouped by the innermost ClimaAtmos frame.
CA.remaining_tendency!(Yₜ, Yₜ_lim, Y, p, t)
Profile.Allocs.clear()
Profile.Allocs.@profile sample_rate = 1 CA.remaining_tendency!(Yₜ, Yₜ_lim, Y, p, t)
results = Profile.Allocs.fetch()
groups = Dict{String, Tuple{Int, Int}}()
for alloc in results.allocs
    frame = findfirst(sf -> occursin("ClimaAtmos", string(sf.file)), alloc.stacktrace)
    key = if isnothing(frame)
        "no ClimaAtmos frame"
    else
        sf = alloc.stacktrace[frame]
        "$(sf.func) at $(basename(string(sf.file))):$(sf.line) [$(alloc.type)]"
    end
    n, bytes = get(groups, key, (0, 0))
    groups[key] = (n + 1, bytes + alloc.size)
end
println("allocations in one call: ", length(results.allocs), ", bytes ", sum(a -> a.size, results.allocs; init = 0))
for (key, (n, bytes)) in sort(collect(groups); by = x -> -x[2][2])
    println(lpad(bytes, 8), " bytes ", lpad(n, 4), " allocs  ", key)
end
