#=
Integration test for the water tags' rain and snow parts under prognostic EDMF
with the default transport of the column without EDMF,
`water_tag_transport: tracer`, and the audit switched off
(`water_tag_precipitation_audit: false`). The transport is a type parameter of
the tags' model, so this is a third EDMF build, and it has a test group of its
own. It checks that the partition stays bounded over the hour on the DYCOMS
RF02 EDMF column, and prints the closing ledger. The rest is in
`tagged_water_precipitation_edmf_integration.jl`.
=#
using Test
import ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
include("tagged_water_precipitation_common.jl")
include("tagged_water_precipitation_edmf_common.jl")

@testset "Rain and snow parts under PrognosticEDMFX as tracers" begin
    config = merge(
        edmf_column_config(),
        precipitation_tag_config("tracer"),
        Dict{String, Any}("water_tag_precipitation_audit" => false),
    )
    simulation = run!(build(config, "water_tags_precipitation_edmf_tracer"))
    Y = simulation.integrator.u
    model = simulation.integrator.p.atmos.water_tagging_model
    @test !CA.follows_water_increment(model)
    @test !CA.has_water_tag_precipitation_audit(model)
    @test !any(CA.is_water_tag_audit_name, propertynames(Y.c))
    result = closure(Y)
    led_close = sum(Y.c.q_tag_led_close)
    @info "The parts under EDMF as tracers after an hour" result led_close
    for prefix in (:ρq_tag_, :ρq_rtag_, :ρq_stag_)
        for name in (:tropo, :strat, :evap)
            @test all(isfinite, parent(getproperty(Y.c, Symbol(prefix, name))))
            @test minimum(parent(getproperty(Y.c, Symbol(prefix, name)))) >= 0
        end
    end
    # The closing step closes the compartments at every follow, so the
    # partition stays bounded by them.
    @test result.rain < 1e-8
    @test result.total < 1e-2
end
