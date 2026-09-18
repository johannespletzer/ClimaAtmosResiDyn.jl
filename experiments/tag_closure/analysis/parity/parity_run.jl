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
]

@info "ClimaAtmos source" pkgdir(CA)
for (name, config) in configs
    isempty(selected) || name in selected || continue
    t0 = time()
    simulation = CA.get_simulation(
        CA.AtmosConfig(merge(common, config); job_id = "parity_$name"),
    )
    result = CA.solve_atmos!(simulation)
    @assert result.ret_code == :success "$name did not finish"
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
    arrays(x) = (; (name => copy(parent(getproperty(x, name))) for name in propertynames(x))...)
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
    manifest = joinpath(dirname(Base.active_project()), "Manifest-v$(VERSION.major).$(VERSION.minor).toml")
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
                manifest_sha1 = isfile(manifest) ? bytes2hex(SHA.sha1(read(manifest))) : "none",
            ),
        ),
    )
    @info "saved" name seconds = round(time() - t0)
end
