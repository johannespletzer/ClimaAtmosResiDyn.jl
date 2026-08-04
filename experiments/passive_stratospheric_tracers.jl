import ClimaComms as CC
CC.@import_required_backends

import ClimaAtmos as CA
import ClimaCore: Fields
import YAML

const N_PASSIVE_GASES = 18
const N_SOURCE_ALTITUDES = 8

"""
Eighteen passive gases with constant production in species-specific latitude
bands at eight shared source altitudes.

Target altitudes are spaced every 6 km from 14–56 km. Target latitudes are
spaced every 10 degrees from 85 degrees south through 85 degrees north.
"""
struct StratosphericPassiveGases{FT} <: CA.AbstractChemistryModel
    source_altitudes::NTuple{N_SOURCE_ALTITUDES, FT}
    source_latitudes::NTuple{N_PASSIVE_GASES, FT}
    source_rates::NTuple{N_PASSIVE_GASES, FT}
    altitude_half_width::FT
    latitude_half_width::FT
end

function StratosphericPassiveGases(
    ::Type{FT};
    source_rate = 1e-10,
    altitude_half_width = 500,
    latitude_half_width = 5,
) where {FT}
    altitudes =
        ntuple(i -> FT(14_000 + (i - 1) * 6_000), N_SOURCE_ALTITUDES)

    latitudes =
        ntuple(i -> FT(-85 + (i - 1) * 10), N_PASSIVE_GASES)

    rates =
        ntuple(i -> FT(i * source_rate), N_PASSIVE_GASES)

    return StratosphericPassiveGases{FT}(
        altitudes,
        latitudes,
        rates,
        FT(altitude_half_width),
        FT(latitude_half_width),
    )
end

struct StratosphericTracerSetup{S}
    background::S
end

function CA.Setups.center_initial_condition(
    setup::StratosphericTracerSetup,
    local_geometry,
    params,
)
    return CA.Setups.center_initial_condition(
        setup.background,
        local_geometry,
        params,
    )
end

@generated function CA.Setups.chemistry_variables(
    ρ,
    physical_state,
    ::StratosphericPassiveGases,
)
    names =
        ntuple(
            i -> Symbol("ρq_gas_", lpad(i, 2, '0')),
            N_PASSIVE_GASES,
        )

    values = [:(zero(ρ)) for _ in names]

    return :(NamedTuple{$names}(($(values...),)))
end

# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------

"""
Compute the mass mixing ratio for one density-weighted passive tracer.

`density_weighted_name` is wrapped in `Val` when the diagnostic is registered,
allowing Julia to specialize the property lookup for each tracer.
"""
function compute_passive_gas!(
    out,
    state,
    cache,
    time,
    ::Val{density_weighted_name},
) where {density_weighted_name}
    density_weighted_tracer =
        getproperty(state.c, density_weighted_name)

    if isnothing(out)
        return @. density_weighted_tracer / state.c.ρ
    else
        @. out = density_weighted_tracer / state.c.ρ
        return out
    end
end

for i in 1:N_PASSIVE_GASES
    tracer_name = "q_gas_$(lpad(i, 2, '0'))"
    density_weighted_name = Symbol("ρ", tracer_name)
    density_weighted_key = Val(density_weighted_name)

    let tracer_name = tracer_name,
        density_weighted_key = density_weighted_key,
        tracer_index = i

        CA.Diagnostics.add_diagnostic_variable!(;
            short_name = tracer_name,
            long_name =
                "Passive stratospheric gas $(tracer_index) mass mixing ratio",
            units = "kg kg^-1",
            compute! = (out, state, cache, time) ->
                compute_passive_gas!(
                    out,
                    state,
                    cache,
                    time,
                    density_weighted_key,
                ),
        )
    end
end

function passive_tracer_example_config()
    config_file = normpath(
        @__DIR__,
        "..",
        "config",
        "example_configs",
        "passive_stratospheric_tracers.yml",
    )

    return YAML.load_file(config_file)
end

# ---------------------------------------------------------------------------
# Source tendency
# ---------------------------------------------------------------------------

"""
Source tendency for one source altitude.

This method is retained for compatibility with the existing unit tests and for
testing individual source regions.
"""
@inline function tracer_source_tendency(
    ρ,
    z,
    latitude,
    source_rate,
    source_altitude,
    source_latitude,
    altitude_half_width,
    latitude_half_width,
)
    is_in_altitude_band =
        abs(z - source_altitude) <= altitude_half_width

    is_in_latitude_band =
        abs(latitude - source_latitude) <= latitude_half_width

    source_tendency = ρ * source_rate

    latitude_tendency = ifelse(
        is_in_latitude_band,
        source_tendency,
        zero(source_tendency),
    )

    return ifelse(
        is_in_altitude_band,
        latitude_tendency,
        zero(source_tendency),
    )
end

"""
Return the number of source-altitude bands containing `z`.

Counting matching bands, rather than returning only a Boolean, preserves the
behavior of the original nested loop even when source bands overlap.
"""
@inline function number_of_matching_altitude_bands(
    z,
    source_altitudes::NTuple{N_SOURCE_ALTITUDES, FT},
    altitude_half_width,
) where {FT}
    @inbounds return (
        Int(abs(z - source_altitudes[1]) <= altitude_half_width) +
        Int(abs(z - source_altitudes[2]) <= altitude_half_width) +
        Int(abs(z - source_altitudes[3]) <= altitude_half_width) +
        Int(abs(z - source_altitudes[4]) <= altitude_half_width) +
        Int(abs(z - source_altitudes[5]) <= altitude_half_width) +
        Int(abs(z - source_altitudes[6]) <= altitude_half_width) +
        Int(abs(z - source_altitudes[7]) <= altitude_half_width) +
        Int(abs(z - source_altitudes[8]) <= altitude_half_width)
    )
end

"""
Source tendency summed over all configured source altitudes.

This scalar function is broadcast once per gas. The original implementation
broadcast the scalar source function separately for every altitude.
"""
@inline function tracer_source_tendency(
    ρ,
    z,
    latitude,
    source_rate,
    source_altitudes::NTuple{N_SOURCE_ALTITUDES, FT},
    source_latitude,
    altitude_half_width,
    latitude_half_width,
) where {FT}
    matching_altitude_bands =
        number_of_matching_altitude_bands(
            z,
            source_altitudes,
            altitude_half_width,
        )

    is_in_latitude_band =
        abs(latitude - source_latitude) <= latitude_half_width

    source_tendency =
        ρ * source_rate * matching_altitude_bands

    return ifelse(
        is_in_latitude_band,
        source_tendency,
        zero(source_tendency),
    )
end

"""
Return direct references to all passive-tracer tendency fields.

Using a concrete tuple avoids constructing tracer names and calling
`getproperty` with dynamically generated symbols during every RHS evaluation.
"""
@inline function passive_tracer_tendency_fields(Yₜ)
    return (
        Yₜ.c.ρq_gas_01,
        Yₜ.c.ρq_gas_02,
        Yₜ.c.ρq_gas_03,
        Yₜ.c.ρq_gas_04,
        Yₜ.c.ρq_gas_05,
        Yₜ.c.ρq_gas_06,
        Yₜ.c.ρq_gas_07,
        Yₜ.c.ρq_gas_08,
        Yₜ.c.ρq_gas_09,
        Yₜ.c.ρq_gas_10,
        Yₜ.c.ρq_gas_11,
        Yₜ.c.ρq_gas_12,
        Yₜ.c.ρq_gas_13,
        Yₜ.c.ρq_gas_14,
        Yₜ.c.ρq_gas_15,
        Yₜ.c.ρq_gas_16,
        Yₜ.c.ρq_gas_17,
        Yₜ.c.ρq_gas_18,
    )
end

function CA.chemistry_tendency!(
    Yₜ,
    Y,
    p,
    t,
    chemistry::StratosphericPassiveGases,
)
    coordinates = Fields.coordinate_field(axes(Y.c.ρ))
    z = coordinates.z
    latitude = coordinates.lat

    density = Y.c.ρ
    tracer_tendencies = passive_tracer_tendency_fields(Yₜ)

    # Ref makes the altitude tuple a scalar argument during broadcasting.
    source_altitudes = Ref(chemistry.source_altitudes)

    @inbounds for i in 1:N_PASSIVE_GASES
        tracer_tendency = tracer_tendencies[i]
        source_rate = chemistry.source_rates[i]
        source_latitude = chemistry.source_latitudes[i]

        @. tracer_tendency += tracer_source_tendency(
            density,
            z,
            latitude,
            source_rate,
            source_altitudes,
            source_latitude,
            chemistry.altitude_half_width,
            chemistry.latitude_half_width,
        )
    end

    return nothing
end

# ---------------------------------------------------------------------------
# Simulation setup
# ---------------------------------------------------------------------------

function passive_tracer_model_setup(::Type{FT}) where {FT}
    params = CA.ClimaAtmosParameters(FT)
    chemistry_model = StratosphericPassiveGases(FT)
    model = CA.AtmosModel(; chemistry_model)

    setup = StratosphericTracerSetup(
        CA.Setups.DecayingProfile(;
            perturb = false,
            params,
        ),
    )

    return (; model, params, setup)
end

function build_simulation(::Type{FT} = Float32) where {FT}
    device = CC.device()
    context = CC.context(device)
    CC.init(context)

    config = passive_tracer_example_config()

    grid = CA.SphereGrid(
        FT;
        h_elem = config["h_elem"],
        z_elem = config["z_elem"],
        z_max = FT(config["z_max"]),
        z_stretch = config["z_stretch"],
    )

    (; model, params, setup) =
        passive_tracer_model_setup(FT)

    diagnostics = CA.DiagnosticsConfig(;
        default = config["output_default_diagnostics"],
        additional = config["diagnostics"],
    )

    return CA.AtmosSimulation{FT}(;
        model,
        params,
        grid,
        setup,
        dt = config["dt"],
        t_end = config["t_end"],
        job_id = config["job_id"],
        output_dir_style = config["output_dir_style"],
        diagnostics,
    )
end

function main()
    simulation = build_simulation()
    CA.solve_atmos!(simulation)

    println(
        "Center-state variables: ",
        propertynames(simulation.integrator.u.c),
    )

    return simulation
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
