import ClimaAtmos as CA
import ClimaCore: Fields

const N_PASSIVE_GASES = 10

"""
Ten passive gases with constant, species-dependent production above a fixed
tropopause height. The production tendency is exactly zero below the tropopause.
"""
struct StratosphericPassiveGases{FT} <: CA.AbstractChemistryModel
    tropopause_height::FT
    source_rates::NTuple{N_PASSIVE_GASES, FT}
end

function StratosphericPassiveGases(
    ::Type{FT}; tropopause_height = 12_000, source_rate = 1e-10,
) where {FT}
    rates = ntuple(i -> FT(i * source_rate), N_PASSIVE_GASES)
    return StratosphericPassiveGases{FT}(FT(tropopause_height), rates)
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
    z = Fields.coordinate_field(axes(Y.c.ρ)).z
    for (i, source_rate) in enumerate(chemistry.source_rates)
        tracer_name = Symbol("ρq_gas_", lpad(i, 2, '0'))
        tracer_tendency = getproperty(Yₜ.c, tracer_name)
        @. tracer_tendency +=
            Y.c.ρ * source_rate * ifelse(z >= chemistry.tropopause_height, 1, 0)
    end
    return nothing
end

function build_simulation(::Type{FT} = Float64; t_end = "1mins") where {FT}
    # A 30 km top includes 18 km of source region above the 12 km tropopause.
    # Sixty uniform elements give 500 m vertical resolution and place the
    # tropopause exactly on an element boundary.
    z_max = FT(30_000)
    z_elem = 60
    grid = CA.ColumnGrid(FT; z_elem, z_max, z_stretch = false)
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
