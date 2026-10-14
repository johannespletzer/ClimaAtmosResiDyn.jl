# Helpers shared by `tagged_water_precipitation_edmf_integration.jl` and
# `tagged_water_precipitation_edmf_tracer_integration.jl`, two test groups,
# each in a process of its own. Each file imports `Test` and
# `ClimaAtmos as CA` and includes `tagged_water_precipitation_common.jl`
# before this one.

# `config/model_configs/prognostic_edmfx_dycoms_rf02_column.yml` as a single
# column with 1-moment microphysics, for an hour, as in
# `tagged_water_edmf_integration.jl`. It drizzles from the first minutes. SGS
# quadrature is set here, as the default configuration has it, so that a test
# names the branch it runs. A build without it overrides the key.
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
        "use_sgs_quadrature" => true,
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

# Steps the simulation to its end by hand and sums the surface rain and snow
# fluxes, sampled after each step, times the step, in kg m⁻². The model
# applies the fluxes at every stage, so the sum samples the run's accumulated
# precipitation once per step. It is not its discrete applications.
function run_sampling_precipitation!(simulation)
    (; integrator, output_writers) = simulation
    p = integrator.p
    t_end = last(integrator.sol.prob.tspan)
    sampled = 0.0
    while integrator.t < t_end
        t_before = Float64(integrator.t)
        CA.CTS.step!(integrator)
        flux =
            only(parent(p.precomputed.surface_rain_flux)) +
            only(parent(p.precomputed.surface_snow_flux))
        sampled += abs(flux) * (Float64(integrator.t) - t_before)
    end
    isnothing(output_writers) || foreach(close, output_writers)
    return sampled
end

# The weighted nets at an iterate whose areas differ from the precomputed
# state's are the model's nets, and the flows' nets are the model's rain and
# snow tendencies. With SGS quadrature the environment's flows take `λ⁰` and
# `mu_S⁰` positionally, as the model does, and a wrong input shows here.
function test_weighted_nets(Y, p, t, turbconv_model)
    FT = eltype(Y)
    Y_iterate = copy(Y)
    parent(Y_iterate.c.sgsʲs.:(1).ρa) .*= 1.05
    (ᶜF, ᶜnets) = CA.water_tag_microphysics_inputs!(Y_iterate, p, turbconv_model)
    Yₜ = similar(Y)
    fill!(parent(Yₜ), 0)
    CA.microphysics_tendency!(
        Yₜ,
        Y_iterate,
        p,
        t,
        p.atmos.microphysics_model,
        turbconv_model,
    )
    water = maximum(parent(Y.c.ρq_tot) ./ parent(Y.c.ρ)) / FT(p.dt)
    ᶜflow_net_rai = @. (ᶜF.NR + ᶜF.SR) - (ᶜF.RN + ᶜF.RS)
    ᶜflow_net_sno = @. (ᶜF.NS + ᶜF.RS) - (ᶜF.SN + ᶜF.SR)
    for (species, ᶜnet, ᶜflow_net) in (
        (:ρq_rai, ᶜnets.dq_rai_dt, ᶜflow_net_rai),
        (:ρq_sno, ᶜnets.dq_sno_dt, ᶜflow_net_sno),
    )
        model_net =
            parent(getproperty(Yₜ.c, species)) ./ parent(Y_iterate.c.ρ)
        scale = maximum(abs, model_net)
        @test maximum(abs, parent(ᶜnet) .- model_net) <=
              1e-12 * max(scale, floatmin(FT))
        # The flows' net is the model's to the rounding of the step's water.
        mismatch = maximum(abs, parent(ᶜflow_net) .- model_net)
        @info "The flows' net against the model's tendency of $species" mismatch scale water
        @test mismatch <= 1e-10 * water
    end
end
