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

    z = Fields.coordinate_field(axes(Y.c.ρ)).z
    below = parent(z) .< chemistry.tropopause_height
    above = .!below
    for (i, name) in enumerate(tracer_names)
        tendency = parent(getproperty(Yₜ.c, name))
        @test all(iszero, tendency[below])
        @test all(tendency[above] .> 0)
        @test tendency[above] ≈
              i .* chemistry.source_rates[1] .* parent(Y.c.ρ)[above]
    end
end
