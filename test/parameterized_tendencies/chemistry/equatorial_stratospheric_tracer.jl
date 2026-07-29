using Test
import ClimaAtmos as CA
import ClimaCore: Fields

include("../../../examples/equatorial_stratospheric_tracer.jl")

@testset "equatorial stratospheric tracer" begin
    for FT in (Float32, Float64)
        chemistry = EquatorialStratosphericTracer(FT)
        ρ = FT(0.8)
        expected_tendency = ρ * chemistry.source_rate
        source_parameters = (
            chemistry.source_rate,
            chemistry.source_altitude,
            chemistry.source_latitude,
            chemistry.altitude_half_width,
            chemistry.latitude_half_width,
        )

        @test chemistry.source_altitude === FT(20_000)
        @test chemistry.source_latitude === zero(FT)
        @test @inferred(
            equatorial_tracer_source_tendency(
                ρ,
                FT(20_000),
                zero(FT),
                source_parameters...,
            )
        ) === expected_tendency
        @test iszero(
            equatorial_tracer_source_tendency(
                ρ,
                FT(19_499),
                zero(FT),
                source_parameters...,
            ),
        )
        @test iszero(
            equatorial_tracer_source_tendency(
                ρ,
                FT(20_000),
                FT(6),
                source_parameters...,
            ),
        )
    end

    simulation = build_equatorial_tracer_simulation(Float64; t_end = "5secs")
    Y = simulation.integrator.u
    coordinates = Fields.coordinate_field(axes(Y.c.ρ))
    z = parent(coordinates.z)
    latitude = parent(coordinates.lat)

    @test maximum(z) < 30_000
    @test maximum(z) ≈ 29_500
    @test :ρq_equatorial in propertynames(Y.c)
    @test all(iszero, parent(Y.c.ρq_equatorial))

    Yₜ = similar(Y)
    Yₜ .= 0
    chemistry = simulation.integrator.p.atmos.chemistry_model
    CA.chemistry_tendency!(Yₜ, Y, simulation.integrator.p, 0, chemistry)

    source_region =
        (abs.(z .- chemistry.source_altitude) .<= chemistry.altitude_half_width) .&
        (abs.(latitude .- chemistry.source_latitude) .<= chemistry.latitude_half_width)
    tendency = parent(Yₜ.c.ρq_equatorial)
    @test any(source_region)
    @test all(iszero, tendency[.!source_region])
    @test tendency[source_region] ≈
          chemistry.source_rate .* parent(Y.c.ρ)[source_region]
end
