#=
WP4a-J's parity check: with `water_tag_rainout_jacobian` absent, the switch's
branch gives what `main` gives, bit for bit, the tags included.

    julia +1.11 --project=<env> wp4aj_parity_run.jl <out_dir> [names...]

Run it once with an environment whose ClimaAtmos is `main`, and once with one
whose ClimaAtmos is the switch's branch, on the same node, with the same
Manifest. Then compare the two directories with
`../parity/parity_compare.jl`, which checks every array of the state and of the
three tendencies with `isequal`. The file format is `parity_run.jl`'s.
`PARITY_COMMIT` names the commit, since compute nodes have no git.

The configurations are the 0M columns the switch concerns, without the key:

  - `tags_0m_vdiff`: WP4a-J's column (DYCOMS RF02, 0M without EDMF, implicit
    microphysics and diffusion, ARS222, one Newton iteration) with its three
    tags, for 30 minutes at dt 120 s. The tags' diagonal comes from the
    diffusion here;
  - `tags_0m`: the column of `test/tagged_water_integration.jl`, without
    vertical diffusion, where the tags' diagonal is the `-I` fallback;
  - `plain_0m_vdiff`: `tags_0m_vdiff` without tags, a configuration upstream
    can run.
=#
import ClimaAtmos as CA
import SHA
using Serialization

out = ARGS[1]
selected = ARGS[2:end]
mkpath(out)
region(above) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => 750.0,
    "width" => 100.0,
    "above" => above,
)
tags = [
    Dict{String, Any}("name" => "tropo", "region" => region(false)),
    Dict{String, Any}("name" => "strat", "region" => region(true)),
    Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
]
common = Dict{String, Any}(
    "config" => "column",
    "initial_condition" => "DYCOMS_RF02",
    "z_max" => 1500.0,
    "z_elem" => 30,
    "z_stretch" => false,
    "microphysics_model" => "0M",
    "FLOAT_TYPE" => "Float64",
    "output_default_diagnostics" => false,
    "output_dir" => mktempdir(pwd()),
)
column_vdiff = Dict{String, Any}(
    "implicit_microphysics" => true,
    "rad" => "DYCOMS",
    "vert_diff" => "DecayWithHeightDiffusion",
    "implicit_diffusion" => true,
    "ode_algo" => "ARS222",
    "max_newton_iters_ode" => 1,
    "dt" => "120secs",
    "t_end" => "1800secs",
)
configs = [
    "tags_0m_vdiff" => merge(
        column_vdiff,
        Dict{String, Any}("water_tracers" => tags, "water_tag_transport" => "tracer"),
    ),
    "tags_0m" => Dict{String, Any}(
        "dt" => "10secs",
        "t_end" => "100secs",
        "water_tracers" => tags,
    ),
    "plain_0m_vdiff" => column_vdiff,
]

@info "ClimaAtmos source" pkgdir(CA)
for (name, config) in configs
    isempty(selected) || name in selected || continue
    t0 = time()
    simulation = CA.get_simulation(
        CA.AtmosConfig(merge(common, config); job_id = "wp4aj_parity_$name"),
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
                manifest_sha1 = isfile(manifest) ?
                                bytes2hex(SHA.sha1(read(manifest))) : "none",
            ),
        ),
    )
    @info "saved" name seconds = round(time() - t0)
end
