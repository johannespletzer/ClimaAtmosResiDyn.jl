import ClimaAtmos as CA
import ClimaCore: Fields

const N_PASSIVE_GASES = 10

"""
Ten passive gases with constant production in species-specific altitude-latitude
source bands. Target altitudes span 12--60 km and target latitudes span
90 degrees south to 90 degrees north, both at equal spacing.
"""
struct StratosphericPassiveGases{FT} <: CA.AbstractChemistryModel
    source_altitudes::NTuple{N_PASSIVE_GASES, FT}
    source_latitudes::NTuple{N_PASSIVE_GASES, FT}
    source_rates::NTuple{N_PASSIVE_GASES, FT}
    altitude_half_width::FT
    latitude_half_width::FT
end

function StratosphericPassiveGases(
    ::Type{FT}; source_rate = 1e-10, altitude_half_width = 500,
    latitude_half_width = 5,
) where {FT}
    altitudes = ntuple(
        i -> FT(12_000 + (i - 1) * (60_000 - 12_000) / 9),
        N_PASSIVE_GASES,
    )
    latitudes = ntuple(i -> FT(-90 + (i - 1) * 180 / 9), N_PASSIVE_GASES)
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

function CA.chemistry_tendency!(Yₜ, Y, p, t, chemistry::StratosphericPassiveGases)
    coordinates = Fields.coordinate_field(axes(Y.c.ρ))
    z = coordinates.z
    latitude = coordinates.lat
    for (i, source_rate) in enumerate(chemistry.source_rates)
        tracer_name = Symbol("ρq_gas_", lpad(i, 2, '0'))
        tracer_tendency = getproperty(Yₜ.c, tracer_name)
        source_altitude = chemistry.source_altitudes[i]
        source_latitude = chemistry.source_latitudes[i]
        @. tracer_tendency +=
            Y.c.ρ * source_rate *
            ifelse(
                (abs(z - source_altitude) <= chemistry.altitude_half_width) &
                abs(latitude - source_latitude) <= chemistry.latitude_half_width,
                1,
                0,
            )
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
        job_id = "ten_passive_stratospheric_tracers",
        output_dir_style = "removepreexisting",
    )
end

function main()
    simulation = build_simulation()
    CA.solve_atmos!(simulation)
    println("Center-state variables: ", propertynames(simulation.integrator.u.c))
    return simulation
end

abspath(PROGRAM_FILE) == @__FILE__ && main()
