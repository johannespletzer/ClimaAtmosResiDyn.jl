import ClimaAtmos as CA
import ClimaCore: Fields

const N_PASSIVE_GASES = 18
const N_SOURCE_ALTITUDES = 8

"""
Eighteen passive gases with constant production in species-specific
latitude bands at eight shared source altitudes. Target altitudes are spaced
every 6 km from 14--56 km and target latitudes are spaced every 10 degrees from
85 degrees south through 85 degrees north.
"""
struct StratosphericPassiveGases{FT} <: CA.AbstractChemistryModel
    source_altitudes::NTuple{N_SOURCE_ALTITUDES, FT}
    source_latitudes::NTuple{N_PASSIVE_GASES, FT}
    source_rates::NTuple{N_PASSIVE_GASES, FT}
    altitude_half_width::FT
    latitude_half_width::FT
end

function StratosphericPassiveGases(
    ::Type{FT}; source_rate = 1e-10, altitude_half_width = 500,
    latitude_half_width = 5,
) where {FT}
    altitudes = ntuple(i -> FT(14_000 + (i - 1) * 6_000), N_SOURCE_ALTITUDES)
    latitudes = ntuple(i -> FT(-85 + (i - 1) * 10), N_PASSIVE_GASES)
    rates = ntuple(i -> FT(i * source_rate), N_PASSIVE_GASES)
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
    setup::StratosphericTracerSetup, local_geometry, params,
)
    return CA.Setups.center_initial_condition(setup.background, local_geometry, params)
end

@generated function CA.Setups.chemistry_variables(
    ρ, physical_state, ::StratosphericPassiveGases,
)
    names = ntuple(i -> Symbol("ρq_gas_", lpad(i, 2, '0')), N_PASSIVE_GASES)
    values = [:(zero(ρ)) for _ in names]
    return :(NamedTuple{$names}(($(values...),)))
end

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
    is_in_altitude_band = abs(z - source_altitude) <= altitude_half_width
    is_in_latitude_band = abs(latitude - source_latitude) <= latitude_half_width
    source_tendency = ρ * source_rate
    latitude_tendency = ifelse(
        is_in_latitude_band,
        source_tendency,
        zero(source_tendency),
    )
    return ifelse(is_in_altitude_band, latitude_tendency, zero(source_tendency))
end

function CA.chemistry_tendency!(Yₜ, Y, p, t, chemistry::StratosphericPassiveGases)
    coordinates = Fields.coordinate_field(axes(Y.c.ρ))
    z = coordinates.z
    latitude = coordinates.lat
    for (i, source_rate) in enumerate(chemistry.source_rates)
        tracer_name = Symbol("ρq_gas_", lpad(i, 2, '0'))
        tracer_tendency = getproperty(Yₜ.c, tracer_name)
        source_latitude = chemistry.source_latitudes[i]
        for source_altitude in chemistry.source_altitudes
            @. tracer_tendency +=
                tracer_source_tendency(
                    Y.c.ρ,
                    z,
                    latitude,
                    source_rate,
                    source_altitude,
                    source_latitude,
                    chemistry.altitude_half_width,
                    chemistry.latitude_half_width,
                )
        end
    end
    return nothing
end

function build_simulation(::Type{FT} = Float64; t_end = "1mins") where {FT}
    # A 60 km top and 60 uniform elements give 1 km vertical resolution. Each
    # source occupies the model layer nearest its target altitude. The global
    # cubed sphere is required because the sources also depend on latitude.
    z_max = FT(60_000)
    z_elem = 60
    grid = CA.SphereGrid(FT; h_elem = 6, z_elem, z_max, z_stretch = false)
    params = CA.ClimaAtmosParameters(FT)
    chemistry_model = StratosphericPassiveGases(FT)
    model = CA.AtmosModel(; chemistry_model)
    setup = StratosphericTracerSetup(
        CA.Setups.DecayingProfile(; perturb = false, params),
    )
    return CA.AtmosSimulation{FT}(;
        model,
        params,
        grid,
        setup,
        dt = "5secs",
        t_end,
        job_id = "passive_stratospheric_tracers",
        output_dir_style = "removepreexisting",
    )
end

function main()
    simulation = build_simulation()
    CA.solve_atmos!(simulation)
    println("Center-state variables: ", propertynames(simulation.integrator.u.c))
    return simulation
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
