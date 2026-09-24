# The review of #105 (B1): does the unsplit Jacobian solver, which
# AutoSparseJacobian uses, build under PrognosticEDMFX with the SGS mass flux,
# 1M and water tags? The reviewer's script, kept as it ran.
import ClimaAtmos as CA
altitude_region(above) = Dict{String, Any}("type" => "tanh_altitude", "z_center" => 750.0, "width" => 100.0, "above" => above)
dict = Dict{String, Any}(
    "config" => "column", "initial_condition" => "DYCOMS_RF02", "turbconv" => "prognostic_edmfx",
    "implicit_diffusion" => true, "approximate_linear_solve_iters" => 2,
    "edmfx_entr_model" => "Generalized", "edmfx_detr_model" => "Generalized",
    "edmfx_sgs_mass_flux" => true, "edmfx_sgs_diffusive_flux" => true, "edmfx_nh_pressure" => true,
    "edmfx_vertical_diffusion" => true, "edmfx_filter" => true, "prognostic_tke" => true,
    "microphysics_model" => "1M", "fixed_terminal_velocity_liquid" => false, "z_elem" => 30,
    "z_max" => 1500.0, "z_stretch" => false, "perturb_initstate" => false, "rad" => "DYCOMS",
    "toml" => [joinpath(pkgdir(CA), "toml", "prognostic_edmfx_1M.toml")],
    "ode_algo" => "ARS222", "dt" => "120secs", "t_end" => "1hours", "FLOAT_TYPE" => "Float64",
    "output_default_diagnostics" => false, "output_dir" => mktempdir(),
    "water_tracers" => [
        Dict{String, Any}("name" => "tropo", "region" => altitude_region(false)),
        Dict{String, Any}("name" => "strat", "region" => altitude_region(true)),
    ],
    "water_tag_transport" => "tracer",
)
config = CA.AtmosConfig(dict; job_id = "rev_unsplit")
params = CA.ClimaAtmosParameters(config)
setup = CA.get_setup_type(config.parsed_args, CA.CAP.thermodynamics_params(params))
grid = CA.get_grid(config.parsed_args, params, config.comms_ctx)
atmos = CA.get_atmos(config, params, grid; setup_type = setup)
Y = CA.initial_state(atmos)
t0 = time()
result = try
    cache = CA.jacobian_cache(CA.ManualSparseJacobian(; approximate_solve_iters = 2), Y, atmos; split_uncoupled_fields = false)
    "built: $(typeof(cache.solver).name.name)"
catch err
    "ERROR: " * first(sprint(showerror, err), 600)
end
println("RESULT unsplit EDMF 1M water tags: ", result, " after ", round(time() - t0; digits = 1), " s")
