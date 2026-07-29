using Test
import ClimaAtmos as CA
import ClimaCore: Fields

include("../../../examples/passive_stratospheric_tracers.jl")

@testset "passive stratospheric tracers" begin
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
    @test all(isinteger, chemistry.source_altitudes)
    @test chemistry.source_altitudes ==
          (12_000.0, 14_824.0, 17_647.0, 20_471.0, 23_294.0, 26_118.0,
        28_941.0, 31_765.0, 34_588.0, 37_412.0, 40_235.0, 43_059.0,
        45_882.0, 48_706.0, 51_529.0, 54_353.0, 57_176.0, 60_000.0)
    @test chemistry.source_latitudes ==
          (-85.0, -75.0, -65.0, -55.0, -45.0, -35.0, -25.0, -15.0, -5.0,
        5.0, 15.0, 25.0, 35.0, 45.0, 55.0, 65.0, 75.0, 85.0)
end
