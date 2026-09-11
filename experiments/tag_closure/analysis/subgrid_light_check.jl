#=
Light build checks: the state and the cache only, no integrator. Building the
integrator of an EDMF column did not finish in 15 minutes on the login node, so
these build what `get_simulation` builds up to the cache, and call single
tendency functions on it.

    julia +1.11 --project=.buildkite experiments/tag_closure/analysis/subgrid_light_check.jl edmf
    julia +1.11 --project=.buildkite experiments/tag_closure/analysis/subgrid_light_check.jl 1M|2M|2MP3

`edmf`: the shipped DYCOMS RF02 EDMF column under 1M, with its
`edmfx_vertical_diffusion: true`, with energy source tags and an offset.
  1. It calls the SGS diffusive flux once, where the code asks the updraft for
     a tag field it does not carry.
  2. It gives the updraft a synthetic anomaly, since at t = 0 the updraft equals
     the grid mean. Then it measures what the SGS mass flux and sedimentation do
     to `E = ρe_tot + c·ρ`, against what they do to the tags' partition. The
     sizes mean nothing; whether the partition gets any of it does.

`1M`, `2M`, `2MP3`: `PrecipitatingColumn`, which starts with ice at 6 to 9 km
and snow at 5 to 8 km, in the cold. At t = 0 it checks sedimentation's
closure, the cells where falling water carries negative energy, the upward
branch on a step partition, and each species' own sedimentation against what
`ρq_tot` is moved by.

No repository file is touched.
=#
import ClimaAtmos as CA
using Printf

case = get(ARGS, 1, "edmf")
scratch = joinpath(get(ENV, "SCRATCH", tempdir()), "tag_closure", "subgrid_checks")
mkpath(scratch)
c = 110495.0
t0 = time()
function stamp(msg)
    @printf("[%s] %-58s at %5.0f s\n", case, msg, time() - t0)
    flush(stdout)
end
say(args...) = (println("[$case] ", args...); flush(stdout))
gross(f) = sum(abs.(f))
maxabs(f) = maximum(abs, parent(f))

alt(z, above, width) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => z,
    "width" => width,
    "above" => above,
)

if case == "edmf"
    tags = [
        Dict{String, Any}("name" => "strat", "region" => alt(750.0, true, 100.0)),
        Dict{String, Any}("name" => "tropo", "region" => alt(750.0, false, 100.0)),
        Dict{String, Any}("name" => "sfc", "source" => "surface_flux"),
    ]
    # `config/model_configs/prognostic_edmfx_dycoms_rf02_column.yml`, written
    # out, with the tags and an offset.
    dict = Dict{String, Any}(
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
        "config" => "column",
        "z_elem" => 30,
        "z_max" => 1500.0,
        "z_stretch" => false,
        "perturb_initstate" => false,
        "dt" => "120secs",
        "toml" => ["toml/prognostic_edmfx_1M.toml"],
        "ode_algo" => "ARS222",
        "FLOAT_TYPE" => "Float64",
        "output_default_diagnostics" => false,
        "output_dir" => joinpath(scratch, "out_light_edmf"),
        "energy_source_tags" => tags,
        "energy_source_tag_offset" => c,
    )
    region = (:ρe_src_strat, :ρe_src_tropo)
else
    tags = [
        Dict{String, Any}("name" => "upper", "region" => alt(5000.0, true, 200.0)),
        Dict{String, Any}("name" => "lower", "region" => alt(5000.0, false, 200.0)),
        Dict{String, Any}("name" => "sfc", "source" => "surface_flux"),
    ]
    # `config/model_configs/single_column_precipitation_2M_test.yml`, written
    # out, with the scheme, the tags and an offset.
    dict = Dict{String, Any}(
        "config" => "column",
        "initial_condition" => "PrecipitatingColumn",
        "surface_setup" => "DefaultMoninObukhov",
        "z_elem" => 100,
        "z_max" => 10000.0,
        "z_stretch" => false,
        "dt" => "10secs",
        "cloud_model" => "grid_scale",
        "implicit_microphysics" => case == "1M",
        "microphysics_model" => case,
        "use_sgs_quadrature" => false,
        "vert_diff" => "DecayWithHeightDiffusion",
        "implicit_diffusion" => true,
        "approximate_linear_solve_iters" => 2,
        "FLOAT_TYPE" => "Float64",
        "output_default_diagnostics" => false,
        "output_dir" => joinpath(scratch, "out_light_$case"),
        "energy_source_tags" => tags,
        "energy_source_tag_offset" => c,
    )
    region = (:ρe_src_upper, :ρe_src_lower)
end

# What `get_simulation` does, up to the cache.
try
    config = CA.AtmosConfig(dict; job_id = "agentD_light_$case")
    pa = config.parsed_args
    params = CA.ClimaAtmosParameters(config)
    setup = CA.get_setup_type(pa, CA.Parameters.thermodynamics_params(params))
    model = CA.get_atmos(config, params; setup_type = setup)
    stamp("model built")
    grid = CA.get_grid(pa, params, config.comms_ctx)
    spaces = CA.get_spaces(grid)
    global Y = CA.Setups.initial_state(
        setup, params, model, spaces.center_space, spaces.face_space,
    )
    CA.Setups.overwrite_initial_state!(setup, Y, params.thermodynamics_params)
    stamp("state built")
    start_date = CA.parse_date(pa["start_date"])
    dt, t_start, _ =
        CA.convert_time_args(pa["dt"], pa["t_start"], pa["t_end"], start_date)
    global p = CA.build_cache(
        Y, model, params, dt, start_date,
        Tuple(pa["prescribed_aerosols"]), Tuple(pa["time_varying_trace_gases"]),
        CA.steady_state_velocity_from_config(config, params),
        CA.vertical_water_borrowing_species_from_config(config),
    )
    global t = t_start
    CA.set_precomputed_quantities!(Y, p, t)
    stamp("cache built")
catch err
    say("BUILD FAILED:")
    println(first(sprint(showerror, err), 2500))
    stamp("done")
    exit(0)
end
say("state: ", propertynames(Y.c))
FT = eltype(Y)
ᶜz = CA.Fields.coordinate_field(Y.c).z
ᶜE = @. Y.c.ρe_tot + c * Y.c.ρ
say("cells with E <= 0: ", count(<=(0), parent(ᶜE)))

function partition_report(label, Yₜ)
    ᶜEₜ = @. Yₜ.c.ρe_tot + c * Yₜ.c.ρ
    ᶜPₜ = zero.(Y.c.ρ)
    for name in region
        @. ᶜPₜ += getproperty(Yₜ.c, name)
    end
    @printf(
        "[%s] %-36s gross E-tendency %.4e, gross partition %.4e, max|partition - E| / max|E| %.3e\n",
        case, label, gross(ᶜEₜ), gross(ᶜPₜ),
        maxabs(@. ᶜPₜ - ᶜEₜ) / max(maxabs(ᶜEₜ), eps(FT)),
    )
    flush(stdout)
end

if case == "edmf"
    tc = p.atmos.turbconv_model
    say("turbconv: ", nameof(typeof(tc)))
    say("updraft fields: ", propertynames(Y.c.sgsʲs.:(1)))
    # 1. The SGS diffusive flux, with the updrafts diffused.
    try
        CA.edmfx_sgs_diffusive_flux_tendency!(zero(Y), Y, p, t, tc)
        say("edmfx_sgs_diffusive_flux_tendency! ran without error")
    catch err
        say("edmfx_sgs_diffusive_flux_tendency! FAILED:")
        println(first(sprint(showerror, err), 1500))
        flush(stdout)
    end
    stamp("diffusive flux called")

    # 2. A synthetic updraft: a tenth of the area, rising, warmer and moister
    # below 800 m, and holding more rain than the grid mean between 300 and
    # 900 m, so that the sedimentation corrections act.
    sgs = Y.c.sgsʲs.:(1)
    @. sgs.ρa = FT(0.1) * Y.c.ρ
    @. sgs.mse += ifelse(ᶜz < 800, FT(1500), FT(-500))
    @. sgs.q_tot += ifelse(ᶜz < 800, FT(1e-3), FT(0))
    band = @. (ᶜz > 300) & (ᶜz < 900)
    @. Y.c.ρq_rai = Y.c.ρ * ifelse(band, FT(1e-4), FT(0))
    @. sgs.q_rai = ifelse(band, FT(3e-4), FT(0))
    @. Y.f.sgsʲs.:(1).u₃ = CA.Geometry.Covariant3Vector(FT(1))
    CA.set_precomputed_quantities!(Y, p, t)
    stamp("synthetic updraft set")

    Yₜ = zero(Y)
    CA.edmfx_sgs_mass_flux_tendency!(Yₜ, Y, p, t, tc)
    partition_report("SGS mass flux", Yₜ)
    @printf("[edmf]   of which the c·ρ part, gross %.4e\n", gross(@. c * Yₜ.c.ρ))
    stamp("SGS mass flux done")

    Yₜ = zero(Y)
    CA.vertical_advection_of_water_tendency!(Yₜ, Y, p, t)
    partition_report("sedimentation, with EDMF corrections", Yₜ)
    stamp("done")
    exit(0)
end

# The cold column.
for name in propertynames(Y.c)
    startswith(string(name), "ρq_") || continue
    @printf("[%s] max specific %-8s %.3e\n", case, name,
        maximum(parent(getproperty(Y.c, name)) ./ parent(Y.c.ρ)))
end
Yₜ = zero(Y)
CA.vertical_advection_of_water_tendency!(Yₜ, Y, p, t)
partition_report("sedimentation", Yₜ)
stamp("sedimentation done")

thp = CA.Parameters.thermodynamics_params(p.params)
(; ᶜT) = p.precomputed
(; ᶜΦ) = p.core
species = (
    (:ρq_lcl, CA.TD.internal_energy_liquid),
    (:ρq_icl, CA.TD.internal_energy_ice),
    (:ρq_rai, CA.TD.internal_energy_liquid),
    (:ρq_sno, CA.TD.internal_energy_ice),
)
for (name, e_int) in species
    hasproperty(Y.c, name) || continue
    ᶜρq = getproperty(Y.c, name)
    ᶜe = @. e_int(thp, ᶜT) + ᶜΦ + c
    wet = parent(ᶜρq) .> 1e-9 .* parent(Y.c.ρ)
    negative = wet .& (parent(ᶜe) .< 0)
    @printf(
        "[%s] %-7s cells with q > 1e-9: %3d, with e_int + Φ + c < 0: %3d, min there %.4e J/kg, T there %.1f to %.1f K\n",
        case, name, count(wet), count(negative),
        count(negative) > 0 ? minimum(parent(ᶜe)[negative]) : NaN,
        count(negative) > 0 ? minimum(parent(ᶜT)[negative]) : NaN,
        count(negative) > 0 ? maximum(parent(ᶜT)[negative]) : NaN)
end
flush(stdout)

# A step partition inside the ice layer. With only the downward branch, the
# lower tag could never gain above the step.
z_step = 6500.0
Y_step = copy(Y)
upper_name, lower_name = region
@. Y_step.c.ρe_src_upper = ifelse(ᶜz > z_step, ᶜE, FT(0))
@. Y_step.c.ρe_src_lower = ᶜE - Y_step.c.ρe_src_upper
Yₜ = zero(Y_step)
CA.vertical_advection_of_water_tendency!(Yₜ, Y_step, p, t)
above = parent(ᶜz) .> z_step
upper = parent(Yₜ.c.ρe_src_upper)
lower = parent(Yₜ.c.ρe_src_lower)
ᶜEₜ = @. Yₜ.c.ρe_tot + c * Yₜ.c.ρ
@printf(
    "[%s] step at %.0f m: cells above it where `lower` moves: %d; cells below it where `upper` moves: %d; closure %.2e\n",
    case, z_step, count(!iszero, lower[above]), count(!iszero, upper[.!above]),
    maximum(abs, upper .+ lower .- parent(ᶜEₜ)) / maxabs(ᶜEₜ))
flush(stdout)

# Each species' own sedimentation against what ρq_tot is moved by. The species
# advect with the mean flow in the explicit tendency, so in the implicit
# vertical advection their tendency is sedimentation alone.
Yₜ_all = zero(Y)
CA.implicit_vertical_advection_tendency!(Yₜ_all, Y, p, t)
Yₜ_sed = zero(Y)
CA.vertical_advection_of_water_tendency!(Yₜ_sed, Y, p, t)
ᶜspecies = zero.(Y.c.ρ)
for (name, _) in species
    hasproperty(Y.c, name) || continue
    ᶜs = getproperty(Yₜ_all.c, name)
    @. ᶜspecies += ᶜs
    @printf("[%s] %-7s own sedimentation, gross %.4e\n", case, name, gross(ᶜs))
end
@printf(
    "[%s] ρq_tot moved by sedimentation, gross %.4e; minus the species' own, gross %.4e\n",
    case, gross(Yₜ_sed.c.ρq_tot), gross(@. Yₜ_sed.c.ρq_tot - ᶜspecies))
stamp("done")
