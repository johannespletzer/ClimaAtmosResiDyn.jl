# Three configurations upstream ClimaAtmos can run, for parity_run.jl. They
# cover the paths the fork hooks into most: EDMF's sub-grid fluxes and
# implicit tendency, 1M sedimentation, and transport on a sphere. On 1.11 the
# EDMF column took 930 s, the sphere 610 s and the 1M column 187 s
# (2026-10-14).
dycoms_column = Dict{String, Any}(
    "config" => "column",
    "initial_condition" => "DYCOMS_RF02",
    "z_max" => 1500.0,
    "z_elem" => 30,
    "z_stretch" => false,
    "rad" => "DYCOMS",
    "microphysics_model" => "1M",
    # Cloud liquid falls at the Stokes speed. Upstream 5af1766c replaced the
    # key, so the checkout's defaults decide which one to set.
    (
        haskey(CA.default_config_dict(), "cloud_liquid_terminal_velocity") ?
        "cloud_liquid_terminal_velocity" => "Stokes" :
        "fixed_terminal_velocity_liquid" => false
    ),
)
configs = [
    # The DYCOMS RF02 EDMF column with 1M and the updrafts' vertical
    # diffusion: the hooks in sedimentation, the SGS fluxes and the implicit
    # tendency.
    "edmf_column" => merge(
        dycoms_column,
        Dict{String, Any}(
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
            "perturb_initstate" => false,
            "toml" => [joinpath(pkgdir(CA), "toml", "prognostic_edmfx_1M.toml")],
            "ode_algo" => "ARS222",
            "dt" => "120secs",
            "t_end" => "1hours",
        ),
    ),
    # A DYCOMS column under 1M without EDMF: sedimentation's grid-mean path.
    "column_1m" => merge(
        dycoms_column,
        Dict{String, Any}("dt" => "10secs", "t_end" => "10mins"),
    ),
    # A moist baroclinic wave under 0M for a day: hyperdiffusion, vertical
    # diffusion and horizontal transport on a sphere.
    "moist_sphere" => Dict{String, Any}(
        "config" => "sphere",
        "h_elem" => 6,
        "nh_poly" => 3,
        "z_elem" => 10,
        "z_max" => 30000.0,
        "dz_bottom" => 500.0,
        "dt" => "400secs",
        "ode_algo" => "ARS343",
        "rayleigh_sponge" => false,
        "viscous_sponge" => false,
        "initial_condition" => "MoistBaroclinicWave",
        "microphysics_model" => "0M",
        "hyperdiff" => "Hyperdiffusion",
        "vert_diff" => "DecayWithHeightDiffusion",
        "t_end" => "1days",
    ),
]
