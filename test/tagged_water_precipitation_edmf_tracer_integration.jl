#=
Integration test for the water tags' rain and snow parts under prognostic EDMF
with the default transport of the column without EDMF,
`water_tag_transport: tracer`, and the audit switched off
(`water_tag_precipitation_audit: false`). The transport is a type parameter of
the tags' model, so this is a third EDMF build, and it has a test group of its
own. It checks that the partition stays bounded over the hour on the DYCOMS
RF02 EDMF column, and prints the closing ledger.

The file also builds the column with the parts following the increment,
`tracer_upwinding: first_order`, no SGS quadrature and rain at the default
fixed speed, another model type. There each part's explicit advection is
linear, and the parts follow the negative rain that the stages leave at the
rain's top, so the closing ledger is at rounding, and the non-precipitating
parts' column total is the parent's less the follower's left part. The flows'
nets are checked against the model's on the branch without quadrature. The
rest, with quadrature, is in `tagged_water_precipitation_edmf_integration.jl`.
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
    minima = Dict(
        Symbol(prefix, name) =>
            minimum(parent(getproperty(Y.c, Symbol(prefix, name)))) for
        prefix in (:ρq_tag_, :ρq_rtag_, :ρq_stag_),
        name in (:tropo, :strat, :evap)
    )
    # A `NamedTuple`, which the log prints in full, unlike a `Dict`.
    @info "The parts' minima under EDMF as tracers" (; sort(collect(minima))...)
    for part in keys(minima)
        @test all(isfinite, parent(getproperty(Y.c, part)))
    end
    # Without the follow nothing restores a part that the microphysics or the
    # advection takes below zero. Each part is checked on its own, so a new
    # negative part fails here. The source tag's rain part reaches
    # -2.1e-20 kg m⁻³ on Julia 1.11 and 1.10, against rain of order
    # 1e-7 kg m⁻³. It is held to 1e-18. Its non-precipitating part stays
    # non-negative in this regime. With the default fixed rain speed it
    # reaches -5.1e-5 kg m⁻³.
    known_negative = (; ρq_rtag_evap = -1e-18)
    for (part, value) in minima
        if haskey(known_negative, part)
            @test value >= known_negative[part]
        else
            @test value >= 0
        end
    end
    test_water_tag_diagnostics_compute(Y, simulation.integrator.p, simulation.integrator.t)
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
        Dict{String, Any}(
            "tracer_upwinding" => "first_order",
            "use_sgs_quadrature" => false,
            "rain_terminal_velocity" => "Fixed",
        ),
    )
    simulation = build(config, "water_tags_precipitation_edmf_first_order")
    p = simulation.integrator.p
    @test CA.not_quadrature(p.atmos.sgs_quadrature)
    (sampled_precipitation, led_close_step_gross) = run_sampling_precipitation!(
        simulation;
        ledger = Y -> Y.c.q_tag_led_close,
    )
    Y = simulation.integrator.u
    # Column integrals (`sum` of a field integrates it), in kg m⁻². The
    # precipitation is the hour's surface rain and snow, sampled once per step.
    # The ledger is signed and cumulative, so its column norm can hide closing
    # work that cancels over the hour. The norm of each step's change adds up
    # the work that cancels between steps.
    led_close = abs(sum(Y.c.q_tag_led_close))
    led_close_norm = sum(abs.(Y.c.q_tag_led_close))
    column_precipitation = sum(Y.c.ρq_rai) + sum(Y.c.ρq_sno)
    result = closure(Y)
    ᶜN_gap = @. Y.c.ρq_tag_tropo + Y.c.ρq_tag_strat -
       max(Y.c.ρq_tot - Y.c.ρq_rai - Y.c.ρq_sno, 0)
    N_gap = sum(ᶜN_gap)
    N_gross = sum(abs.(ᶜN_gap))
    left = sum(Y.c.q_tag_inc_left)
    @info "The parts under EDMF with first-order upwinding after an hour" led_close led_close_norm led_close_step_gross sampled_precipitation column_precipitation result N_gap N_gross left
    # The closing ledger at rounding: every operator of the parts sums to the
    # species' where the parent holds rain, and where a Newton stage holds
    # negative rain the parts follow it. The rain falls at the default fixed
    # speed. The IMEX stages then drain the rain's top cell below zero twice in
    # the hour, and the implicit microphysics changes that negative rain. On
    # this column without quadrature the closing step's work, summed over
    # every application and every tag, is 1.9e-17 kg m⁻² over the hour. The
    # ledger's column norm is 7.8e-18 and the steps' changes add up to
    # 1.4e-17, against 0.030 kg m⁻² of sampled precipitation.
    @test led_close_norm <= 1e-10 * sampled_precipitation
    @test led_close_step_gross <= 1e-10 * sampled_precipitation
    @test result.rain < 1e-12
    # The non-precipitating parts' column total is the parent's less the
    # follower's left part, as without the key. Here both are at the rounding
    # of the column's water, -3.7e-15 and -3.4e-16 kg m⁻², so the bound has
    # that floor.
    rounding = 10 * eps(FT) * sum(Y.c.ρq_tot)
    @test abs(N_gap + left) < max(0.05 * N_gross, rounding)
    @testset "The weighted nets without SGS quadrature" begin
        CA.set_precomputed_quantities!(Y, p, simulation.integrator.t)
        test_weighted_nets(Y, p, simulation.integrator.t, p.atmos.turbconv_model)
    end
end
