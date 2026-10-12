#=
Integration test for the water tags' rain and snow parts under prognostic EDMF
with the default transport of the column without EDMF,
`water_tag_transport: tracer`, and the audit switched off
(`water_tag_precipitation_audit: false`). The transport is a type parameter of
the tags' model, so this is a third EDMF build, and it has a test group of its
own. It checks that the partition stays bounded over the hour on the DYCOMS
RF02 EDMF column, and prints the closing ledger.

The file also builds the column with the parts following the increment and
`tracer_upwinding: first_order`, another model type. There each part's
explicit advection is linear, so the closing ledger is at rounding, and the
non-precipitating parts' column total is the parent's less the follower's
left part. The rest is in `tagged_water_precipitation_edmf_integration.jl`.
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

@testset "Rain and snow parts under PrognosticEDMFX with first-order upwinding" begin
    FT = Float64
    config = merge(
        edmf_column_config(),
        precipitation_tag_config("increment"),
        Dict{String, Any}("tracer_upwinding" => "first_order"),
    )
    simulation = run!(build(config, "water_tags_precipitation_edmf_first_order"))
    Y = simulation.integrator.u
    p = simulation.integrator.p
    # Column integrals (`sum` of a field integrates it), in kg m⁻².
    led_close = abs(sum(Y.c.q_tag_led_close))
    led_close_gross = sum(abs.(Y.c.q_tag_led_close))
    pr = abs(only(parent(p.precomputed.surface_rain_flux)))
    rain_scale = sum(Y.c.ρq_rai) + pr * FT(3600)
    result = closure(Y)
    ᶜN_gap = @. Y.c.ρq_tag_tropo + Y.c.ρq_tag_strat -
       max(Y.c.ρq_tot - Y.c.ρq_rai - Y.c.ρq_sno, 0)
    N_gap = sum(ᶜN_gap)
    N_gross = sum(abs.(ᶜN_gap))
    left = sum(Y.c.q_tag_inc_left)
    @info "The parts under EDMF with first-order upwinding after an hour" led_close led_close_gross rain_scale result N_gap N_gross left
    # The closing ledger at rounding: every operator of the parts sums to the
    # species' where the parent holds rain.
    # With the parts' cross blocks summing to the species' at every cell, the
    # closing step books rounding only: 2.8e-13 kg m⁻² over the hour on this
    # column, against a rain scale of 0.04. The bound leaves a factor of 14.
    @test led_close_gross <= 1e-10 * rain_scale
    @test result.rain < 1e-12
    # The non-precipitating parts' column total is the parent's less the
    # follower's left part, as without the key.
    @test abs(N_gap + left) < 0.05 * N_gross
end
