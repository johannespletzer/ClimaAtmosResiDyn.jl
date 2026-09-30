# Helpers shared by `tagged_water_edmf_copies_integration.jl` and
# `tagged_water_edmf_copies_leak_integration.jl`. The two run as separate test
# groups, each in a process of its own: the copies with the leak correction
# are a third EDMF model type, and three EDMF builds in one process came close
# to the 16 GB a GitHub runner has. Each file imports `Test` and
# `ClimaAtmos as CA` before it includes this one.

function run_simulation(config_dict, job_id)
    simulation = CA.get_simulation(
        CA.AtmosConfig(
            merge(
                config_dict,
                Dict{String, Any}("output_dir" => mktempdir(pwd())),
            );
            job_id,
        ),
    )
    @test CA.solve_atmos!(simulation).ret_code == :success
    return simulation
end

altitude_region(above) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => 750.0,
    "width" => 100.0,
    "above" => above,
)

# The DYCOMS RF02 EDMF column with 1-moment microphysics stepped explicitly.
function copies_edmf_config()
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
        "implicit_microphysics" => false,
        "fixed_terminal_velocity_liquid" => false,
        "z_elem" => 30,
        "z_max" => 1500.0,
        "z_stretch" => false,
        "perturb_initstate" => false,
        "rad" => "DYCOMS",
        "toml" => [joinpath(pkgdir(CA), "toml", "prognostic_edmfx_1M.toml")],
        "ode_algo" => "ARS222",
        # On the explicit microphysics path with one Newton iteration the
        # tags lag the parent's solve: the parent's rows carry the
        # sedimenting species' cross blocks and the tags' do not
        # (`update_water_tag_sedimentation_jacobian!`). After an hour the
        # partition then misses by 0.8% net. With ten iterations it closes to
        # 4e-7 net and 8e-4 gross. That lag is WP5's to follow; this file
        # checks the copies, so it converges the solve.
        "max_newton_iters_ode" => 10,
        "dt" => "120secs",
        "t_end" => "1hours",
        "FLOAT_TYPE" => "Float64",
        "output_default_diagnostics" => false,
    )
end

# Three tags with copies in the updraft, the closure audit and the copies'
# diagnostics.
function copies_tag_config()
    return Dict{String, Any}(
        "water_tracers" => [
            Dict{String, Any}("name" => "tropo", "region" => altitude_region(false)),
            Dict{String, Any}("name" => "strat", "region" => altitude_region(true)),
            Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
        ],
        "water_tag_updraft_copy" => true,
        # The audit and the diagnostics write scratch from callbacks, so the
        # parity check below covers them too.
        "water_closure_check" =>
            Dict{String, Any}("period" => "10mins", "audit" => true),
        "diagnostics" => [
            Dict{String, Any}(
                "short_name" => [
                    "q_tag_leak_vdiff",
                    "q_tag_leak_diffusion_up",
                    "q_tag_copy_res",
                    "q_tag_upfix_tropo",
                    "q_tag_led_upfilter",
                    "q_tag_led_repair_gross",
                    "q_tag_led_uprepair_colgross",
                ],
                "period" => "10mins",
            ),
        ],
    )
end
