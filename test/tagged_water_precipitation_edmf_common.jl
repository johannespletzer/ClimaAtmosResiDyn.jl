# Helpers shared by `tagged_water_precipitation_edmf_integration.jl` and
# `tagged_water_precipitation_edmf_tracer_integration.jl`, two test groups,
# each in a process of its own. Each file imports `Test` and
# `ClimaAtmos as CA` and includes `tagged_water_precipitation_common.jl`
# before this one.

# `config/model_configs/prognostic_edmfx_dycoms_rf02_column.yml` as a single
# column with 1-moment microphysics, for an hour, as in
# `tagged_water_edmf_integration.jl`. It drizzles from the first minutes.
function edmf_column_config()
    entrainment_toml = joinpath(mktempdir(pwd()), "interface_entrainment.toml")
    write(
        entrainment_toml,
        """
        [EDMF_interface_entr_efficiency]
        value = 0.4
        type = "float"
        """,
    )
    return Dict{String, Any}(
        "config" => "column",
        "initial_condition" => "DYCOMS_RF02",
        "turbconv" => "prognostic_edmfx",
        "implicit_diffusion" => true,
        "approximate_linear_solve_iters" => 2,
        "edmfx_entr_model" => "Generalized",
        "edmfx_detr_model" => "Generalized",
        "edmfx_sgs_mass_flux" => true,
        "edmfx_sgs_diffusive_flux" => true,
        "edmfx_nh_pressure" => true,
        "edmfx_vertical_diffusion" => true,
        "edmfx_filter" => true,
        "prognostic_tke" => true,
        "microphysics_model" => "1M",
        "fixed_terminal_velocity_liquid" => false,
        "z_elem" => 30,
        "z_max" => 1500.0,
        "z_stretch" => false,
        "perturb_initstate" => false,
        "rad" => "DYCOMS",
        "toml" => [
            joinpath(pkgdir(CA), "toml", "prognostic_edmfx_1M.toml"),
            entrainment_toml,
        ],
        "ode_algo" => "ARS222",
        "dt" => "120secs",
        "t_end" => "1hours",
        "FLOAT_TYPE" => "Float64",
        "output_default_diagnostics" => false,
        "output_dir" => mktempdir(pwd()),
    )
end

edmf_altitude_region(above) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => 750.0,
    "width" => 100.0,
    "above" => above,
)

# An altitude region and its complement, and a `surface_flux` source tag.
precipitation_tag_config(transport) = Dict{String, Any}(
    "water_tag_precipitation" => true,
    "water_tag_transport" => transport,
    "water_tracers" => [
        Dict{String, Any}("name" => "tropo", "region" => edmf_altitude_region(false)),
        Dict{String, Any}("name" => "strat", "region" => edmf_altitude_region(true)),
        Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
    ],
)

# The partition's largest departure from each compartment, relative to the
# compartment's largest value: rain, snow, and the parts' sum against
# `ρq_tot`. Where a compartment is empty everywhere its scale is one.
function closure(Y)
    part_sum(prefix) =
        parent(getproperty(Y.c, Symbol(prefix, :tropo))) .+
        parent(getproperty(Y.c, Symbol(prefix, :strat)))
    relative(a, b) = maximum(abs, a .- b) / max(maximum(abs, b), 1e-30)
    (ᶜN, ᶜR, ᶜS) = values(compartments(Y))
    total = part_sum(:ρq_tag_) .+ part_sum(:ρq_rtag_) .+ part_sum(:ρq_stag_)
    return (;
        rain = relative(part_sum(:ρq_rtag_), max.(ᶜR, 0)),
        snow = relative(part_sum(:ρq_stag_), max.(ᶜS, 0)),
        nonprecipitating = relative(part_sum(:ρq_tag_), max.(ᶜN, 0)),
        total = relative(total, max.(ᶜN, 0) .+ max.(ᶜR, 0) .+ max.(ᶜS, 0)),
    )
end
