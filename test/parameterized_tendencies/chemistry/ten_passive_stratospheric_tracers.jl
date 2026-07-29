using Test
import ClimaAtmos as CA
import ClimaCore: Fields

include("../../../examples/ten_passive_stratospheric_tracers.jl")

@testset "ten passive stratospheric tracers" begin
    simulation = build_simulation(Float64; t_end = "5secs")
    Y = simulation.integrator.u
    tracer_names = ntuple(i -> Symbol("ρq_gas_", lpad(i, 2, '0')), N_PASSIVE_GASES)

    @test all(name -> name in propertynames(Y.c), tracer_names)
    @test all(name -> all(iszero, parent(getproperty(Y.c, name))), tracer_names)

    Yₜ = similar(Y)
    Yₜ .= 0
    chemistry = simulation.integrator.p.atmos.chemistry_model
    CA.chemistry_tendency!(Yₜ, Y, simulation.integrator.p, 0, chemistry)

    coordinates = Fields.coordinate_field(axes(Y.c.ρ))
    z = parent(coordinates.z)
    latitude = parent(coordinates.lat)
    for (i, name) in enumerate(tracer_names)
        tendency = parent(getproperty(Yₜ.c, name))
        source_region =
            (abs.(z .- chemistry.source_altitudes[i]) .<=
             chemistry.altitude_half_width) .&
            (abs.(latitude .- chemistry.source_latitudes[i]) .<=
             chemistry.latitude_half_width)
        @test any(source_region)
        @test all(iszero, tendency[.!source_region])
        @test all(tendency[source_region] .> 0)
        @test tendency[source_region] ≈
              chemistry.source_rates[i] .* parent(Y.c.ρ)[source_region]
    end

    @test chemistry.source_altitudes[1] == 12_000
    @test chemistry.source_altitudes[end] == 60_000
    @test all(diff(collect(chemistry.source_altitudes)) .≈ 48_000 / 9)
    @test chemistry.source_latitudes ==
          (-90.0, -70.0, -50.0, -30.0, -10.0, 10.0, 30.0, 50.0, 70.0, 90.0)
end
