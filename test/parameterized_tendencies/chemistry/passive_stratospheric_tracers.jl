using Test
import ClimaAtmos as CA
import ClimaCore: Fields

include("../../../examples/passive_stratospheric_tracers.jl")

@testset "passive stratospheric tracers" begin
    @testset "source tendency calculation" begin
        for FT in (Float32, Float64)
            ρ = FT(0.8)
            source_rate = FT(2e-10)
            source_altitude = FT(20_000)
            source_latitude = FT(15)
            altitude_half_width = FT(500)
            latitude_half_width = FT(5)

            tendency(z, latitude) = tracer_source_tendency(
                ρ,
                FT(z),
                FT(latitude),
                source_rate,
                source_altitude,
                source_latitude,
                altitude_half_width,
                latitude_half_width,
            )

            @test @inferred(tendency(20_000, 15)) === ρ * source_rate
            @test tendency(19_500, 10) === ρ * source_rate
            @test iszero(tendency(19_499, 15))
            @test iszero(tendency(20_000, 9))
        end
    end

    simulation = build_simulation(Float64)
    Y = simulation.integrator.u
    tracer_names = ntuple(i -> Symbol("ρq_gas_", lpad(i, 2, '0')), N_PASSIVE_GASES)

    @test all(name -> name in propertynames(Y.c), tracer_names)
    @test all(name -> all(iszero, parent(getproperty(Y.c, name))), tracer_names)
    @test length(simulation.output_writers) == 4

    config = passive_tracer_example_config()
    @test config["dt"] == "5secs"
    @test config["t_end"] == "1mins"
    @test !config["output_default_diagnostics"]
    @test length(config["diagnostics"]) == 2
    @test all(
        diagnostic -> diagnostic["pressure_coordinates"],
        config["diagnostics"],
    )

    for i in 1:N_PASSIVE_GASES
        short_name = "q_gas_$(lpad(i, 2, '0'))"
        tracer_diagnostic = CA.Diagnostics.get_diagnostic_variable(short_name)
        tracer_output = tracer_diagnostic.compute!(nothing, Y, simulation.integrator.p, 0)
        @test all(iszero, parent(tracer_output))
    end

    Yₜ = similar(Y)
    Yₜ .= 0
    chemistry = simulation.integrator.p.atmos.chemistry_model
    CA.chemistry_tendency!(Yₜ, Y, simulation.integrator.p, 0, chemistry)

    coordinates = Fields.coordinate_field(axes(Y.c.ρ))
    z = parent(coordinates.z)
    latitude = parent(coordinates.lat)
    for (i, name) in enumerate(tracer_names)
        tendency = parent(getproperty(Yₜ.c, name))
        altitude_region = reduce(
            (region_a, region_b) -> region_a .| region_b,
            (
                abs.(z .- source_altitude) .<= chemistry.altitude_half_width for
                source_altitude in chemistry.source_altitudes
            ),
        )
        source_region = altitude_region .&
            (abs.(latitude .- chemistry.source_latitudes[i]) .<=
             chemistry.latitude_half_width)
        @test any(source_region)
        @test all(iszero, tendency[.!source_region])
        @test all(tendency[source_region] .> 0)
        @test tendency[source_region] ≈
              chemistry.source_rates[i] .* parent(Y.c.ρ)[source_region]
    end

    @test chemistry.source_altitudes[1] == 14_000
    @test chemistry.source_altitudes[end] == 56_000
    @test all(isinteger, chemistry.source_altitudes)
    @test chemistry.source_altitudes ==
          (14_000.0, 20_000.0, 26_000.0, 32_000.0, 38_000.0, 44_000.0,
        50_000.0, 56_000.0)
    @test chemistry.source_latitudes ==
          (-85.0, -75.0, -65.0, -55.0, -45.0, -35.0, -25.0, -15.0, -5.0,
        5.0, 15.0, 25.0, 35.0, 45.0, 55.0, 65.0, 75.0, 85.0)
end
