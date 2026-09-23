#=
Fork parity: run configurations that upstream ClimaAtmos can run, with no fork
diagnostic on, and save the final state and one implicit, remaining and
limiter tendency of each, so that two checkouts can be compared bit for bit
with `parity_compare.jl`. See "Fork parity with upstream" in
`docs/clima_atmos_specific.md`.

    julia +1.11 --project=<checkout>/.buildkite parity_run.jl <out_dir> [names...]

Run it once per checkout, from each checkout's own `.buildkite` environment,
with the same manifest and on the same machine. Without names it runs every
configuration below. `PARITY_COMMIT` names the checkout's commit in the
saved provenance, because compute nodes have no git.

First used on 2026-09-18 for #89 (the fork after the upstream v0.42.11 merge
against upstream d331fe30, job 13503291) and for C1b against `main`. A review
of those runs asked for every component of `Y`, a finiteness check,
provenance in each file and an explicit list of configurations, which this
version has.

#89's review (R2) asked for the paths those runs did not cover: a restart, the
vertical water borrowing limiter and a prescribed flow. `restart_first` writes
a checkpoint at 5 minutes, and `restart_column` restarts from it in the same
process, so run the two together and in that order.
=#
import ClimaAtmos as CA
import SHA
using Serialization

out = ARGS[1]
selected = ARGS[2:end]
common = Dict{String, Any}(
    "FLOAT_TYPE" => "Float64",
    "output_default_diagnostics" => false,
    "output_dir" => mktempdir(pwd()),
)
configs = [
    # The shipped DYCOMS RF02 EDMF column, 1M, with the updrafts' vertical
    # diffusion on: the fork's hooks in sedimentation, the SGS fluxes and the
    # implicit tendency.
    "edmf_column" => Dict{String, Any}(
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
        "toml" => [joinpath(pkgdir(CA), "toml", "prognostic_edmfx_1M.toml")],
        "ode_algo" => "ARS222",
        "dt" => "120secs",
        "t_end" => "1hours",
    ),
    # B1's moist baroclinic wave without tags, for a day: hyperdiffusion,
    # vertical diffusion and horizontal transport on a sphere.
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
    # A DYCOMS column under 1M without EDMF: sedimentation's grid-mean path.
    "column_1m" => Dict{String, Any}(
        "config" => "column",
        "initial_condition" => "DYCOMS_RF02",
        "z_max" => 1500.0,
        "z_elem" => 30,
        "z_stretch" => false,
        "rad" => "DYCOMS",
        "microphysics_model" => "1M",
        "fixed_terminal_velocity_liquid" => false,
        "dt" => "10secs",
        "t_end" => "10mins",
    ),
    # The restart path: `column_1m` with a checkpoint at 5 minutes, then the
    # same column restarted from it. Both end at 10 minutes. It reads the
    # checkpoint's attributes and model hash, which the fork writes more of.
    "restart_first" => Dict{String, Any}(
        "config" => "column",
        "initial_condition" => "DYCOMS_RF02",
        "z_max" => 1500.0,
        "z_elem" => 30,
        "z_stretch" => false,
        "rad" => "DYCOMS",
        "microphysics_model" => "1M",
        "fixed_terminal_velocity_liquid" => false,
        "dt" => "10secs",
        "t_end" => "10mins",
        "dt_save_state_to_disk" => "5mins",
        "output_dir" => mktempdir(pwd()),
    ),
    "restart_column" => Dict{String, Any}(
        "config" => "column",
        "initial_condition" => "DYCOMS_RF02",
        "z_max" => 1500.0,
        "z_elem" => 30,
        "z_stretch" => false,
        "rad" => "DYCOMS",
        "microphysics_model" => "1M",
        "fixed_terminal_velocity_liquid" => false,
        "dt" => "10secs",
        "t_end" => "10mins",
        "output_dir" => mktempdir(pwd()),
        "restart_from" => ("restart_first", "day0.300.hdf5"),
    ),
    # `column_1m` with the vertical water borrowing limiter, where the fork
    # decides which tracers the limiter applies to.
    "column_1m_borrowing" => Dict{String, Any}(
        "config" => "column",
        "initial_condition" => "DYCOMS_RF02",
        "z_max" => 1500.0,
        "z_elem" => 30,
        "z_stretch" => false,
        "rad" => "DYCOMS",
        "microphysics_model" => "1M",
        "fixed_terminal_velocity_liquid" => false,
        "tracer_nonnegativity_method" => "vertical_water_borrowing",
        "dt" => "10secs",
        "t_end" => "10mins",
    ),
    # `config/model_configs/kinematic_driver.yml`, the Shipway-Hill column with
    # a prescribed flow, for 5 minutes instead of 20. The fork's
    # `prescribe_flow!` keeps a copy of `ρq_tot` in a scratch field.
    "prescribed_flow" => Dict{String, Any}(
        "config" => "column",
        "initial_condition" => "ShipwayHill2012",
        "energy_q_tot_upwinding" => "first_order",
        "tracer_upwinding" => "first_order",
        "microphysics_model" => "1M",
        "cloud_model" => "grid_scale",
        "implicit_microphysics" => false,
        "use_sgs_quadrature" => false,
        "hyperdiff" => nothing,
        "z_max" => 8e3,
        "z_elem" => 512,
        "z_stretch" => false,
        "dt" => "1secs",
        "t_end" => "5mins",
        "toml" => [joinpath(pkgdir(CA), "toml", "kinematic_driver.toml")],
        "check_nan_every" => 1,
    ),
]

@info "ClimaAtmos source" pkgdir(CA)
output_dirs = Dict{String, String}()
for (name, config) in configs
    isempty(selected) || name in selected || continue
    t0 = time()
    # A restart reads the checkpoint that an earlier configuration of this
    # run wrote.
    if haskey(config, "restart_from")
        config = copy(config)
        (source, file) = pop!(config, "restart_from")
        haskey(output_dirs, source) ||
            error("$name restarts from $source, which has not run")
        config["restart_file"] = joinpath(output_dirs[source], file)
    end
    simulation = CA.get_simulation(
        CA.AtmosConfig(merge(common, config); job_id = "parity_$name"),
    )
    result = CA.solve_atmos!(simulation)
    @assert result.ret_code == :success "$name did not finish"
    output_dirs[name] = simulation.output_dir
    Y = simulation.integrator.u
    p = simulation.integrator.p
    t = simulation.integrator.t
    Yₜ_implicit = zero(Y)
    CA.implicit_tendency!(Yₜ_implicit, Y, p, t)
    Yₜ_remaining = zero(Y)
    Yₜ_lim = zero(Y)
    CA.remaining_tendency!(Yₜ_remaining, Yₜ_lim, Y, p, t)
    # Every component of the state, not only `c` and `f`, so that a surface
    # state such as `Y.sfc` is compared as well.
    arrays(x) =
        (; (name => copy(parent(getproperty(x, name))) for name in propertynames(x))...)
    state = arrays(Y)
    tendencies = (;
        implicit = arrays(Yₜ_implicit),
        remaining = arrays(Yₜ_remaining),
        lim = arrays(Yₜ_lim),
    )
    # Two runs full of matching NaNs would compare equal, so refuse them here.
    for (label, group) in pairs((; state, tendencies...)), (key, a) in pairs(group)
        all(isfinite, a) || error("$name: $label.$key holds a NaN or an Inf")
    end
    manifest = joinpath(
        dirname(Base.active_project()),
        "Manifest-v$(VERSION.major).$(VERSION.minor).toml",
    )
    serialize(
        joinpath(out, "$name.jls"),
        (;
            t,
            names = map(k -> propertynames(getproperty(Y, k)), propertynames(Y)),
            state,
            tendencies,
            provenance = (;
                julia = string(VERSION),
                host = gethostname(),
                cpu = Sys.cpu_info()[1].model,
                climaatmos = pkgdir(CA),
                commit = get(ENV, "PARITY_COMMIT", "unknown"),
                manifest_sha1 = isfile(manifest) ? bytes2hex(SHA.sha1(read(manifest))) :
                                "none",
            ),
        ),
    )
    @info "saved" name seconds = round(time() - t0)
end
