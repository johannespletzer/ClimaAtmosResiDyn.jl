import ClimaAtmos as CA
import ClimaCore: Fields
import YAML

"""
A passive gas emitted in a region centered on the equator at 20 km altitude.
"""
struct EquatorialStratosphericTracer{FT} <: CA.AbstractChemistryModel
    source_rate::FT
    source_altitude::FT
    source_latitude::FT
    altitude_half_width::FT
    latitude_half_width::FT
end

function EquatorialStratosphericTracer(
    ::Type{FT};
    source_rate = 1e-10,
    source_altitude = 20_000,
    source_latitude = 0,
    altitude_half_width = 500,
    latitude_half_width = 5,
) where {FT}
    return EquatorialStratosphericTracer{FT}(
        FT(source_rate),
        FT(source_altitude),
        FT(source_latitude),
        FT(altitude_half_width),
        FT(latitude_half_width),
    )
end

struct EquatorialTracerSetup{S}
    background::S
end

function CA.Setups.center_initial_condition(
    setup::EquatorialTracerSetup,
    local_geometry,
    params,
)
    return CA.Setups.center_initial_condition(setup.background, local_geometry, params)
end

function CA.Setups.chemistry_variables(
    ρ,
    physical_state,
    ::EquatorialStratosphericTracer,
)
    return (; ρq_equatorial = zero(ρ))
end

function compute_equatorial_tracer!(out, state, cache, time)
    if isnothing(out)
        return @. state.c.ρq_equatorial / state.c.ρ
    else
        @. out = state.c.ρq_equatorial / state.c.ρ
        return out
    end
end

CA.Diagnostics.add_diagnostic_variable!(;
    short_name = "q_equatorial",
    long_name = "Equatorial passive tracer mass mixing ratio",
    units = "kg kg^-1",
    compute! = compute_equatorial_tracer!,
)

function equatorial_tracer_diagnostics_config()
    config_file = joinpath(
        @__DIR__,
        "..",
        "config",
        "common_configs",
        "diagnostics_equatorial_stratospheric_tracer.yml",
    )
    diagnostics = YAML.load_file(config_file)["diagnostics"]
    return CA.DiagnosticsConfig(; default = false, additional = diagnostics)
end

@inline function equatorial_tracer_source_tendency(
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

function CA.chemistry_tendency!(
    Yₜ,
    Y,
    p,
    t,
    chemistry::EquatorialStratosphericTracer,
)
    coordinates = Fields.coordinate_field(axes(Y.c.ρ))
    (; source_rate, source_altitude, source_latitude) = chemistry
    (; altitude_half_width, latitude_half_width) = chemistry
    @. Yₜ.c.ρq_equatorial += equatorial_tracer_source_tendency(
        Y.c.ρ,
        coordinates.z,
        coordinates.lat,
        source_rate,
        source_altitude,
        source_latitude,
        altitude_half_width,
        latitude_half_width,
    )
    return nothing
end

function build_equatorial_tracer_simulation(
    ::Type{FT} = Float64;
    t_end = "1mins",
) where {FT}
    # Thirty uniform elements over 30 km give 1 km vertical resolution.
    grid = CA.SphereGrid(
        FT;
        h_elem = 6,
        z_elem = 30,
        z_max = FT(30_000),
        z_stretch = false,
    )
    params = CA.ClimaAtmosParameters(FT)
    chemistry_model = EquatorialStratosphericTracer(FT)
    model = CA.AtmosModel(; chemistry_model)
    setup = EquatorialTracerSetup(
        CA.Setups.DecayingProfile(; perturb = false, params),
    )
    return CA.AtmosSimulation{FT}(;
        model,
        params,
        grid,
        setup,
        dt = "5secs",
        t_end,
        job_id = "equatorial_stratospheric_tracer",
        output_dir_style = "removepreexisting",
        diagnostics = equatorial_tracer_diagnostics_config(),
    )
end

function run_equatorial_tracer_example()
    simulation = build_equatorial_tracer_simulation()
    CA.solve_atmos!(simulation)
    println("Center-state variables: ", propertynames(simulation.integrator.u.c))
    return simulation
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_equatorial_tracer_example()
end
