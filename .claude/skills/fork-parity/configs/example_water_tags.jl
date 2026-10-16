# The candidate side of an off-against-on run: upstream.jl's configurations
# with water tags switched on. Copy this file next to the run's output and edit
# the keys for the diagnostic under test. Keep the names, so that the compare
# pairs each configuration with its untagged twin.
include(joinpath(@__DIR__, "upstream.jl"))
altitude_region(above, z) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => z,
    "width" => 300.0,
    "above" => above,
)
diagnostic = Dict{String, Any}(
    "water_tracers" => [
        Dict{String, Any}("name" => "lower", "region" => altitude_region(false, 750.0)),
        Dict{String, Any}("name" => "upper", "region" => altitude_region(true, 750.0)),
        Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
    ],
)
configs = [name => merge(config, diagnostic) for (name, config) in configs]
# On a checkout that refuses the key for a configuration, return `true` here,
# for example `skip(name, config) = !isdefined(CA, :some_new_function)`.
