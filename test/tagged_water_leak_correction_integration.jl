#=
Integration test for `water_tag_leak_correction: true` (WP4c).

The parent diffuses the water without rain and snow at `K_h`, and the tags
their whole value. So the partition gains the diffusion of the rain and snow
that the parent does not have. The correction gives each tag back the diffusion
of its own share of the rain and snow. This file checks, on the D4-W EDMF column
of the tag-closure experiments (DYCOMS RF02, 1-moment microphysics, the tags
following the parent's increment), after an hour:

 1. with one composition everywhere, the partition's EDMF diffusion is the
    parent's to rounding, where without the correction the two differ by the
    closed-form leak. Each tag's correction is the diffusion of its share of
    the rain and snow, and the ledgers take it;
 2. after the hour the partition stays closed, the partition's ledger moves no
    water through the column's boundaries, it is the sum of the tags' own, and
    the split solver, the audit and the diagnostics read the ledgers;
 3. the model's fields are those of the same column without tags, bit for bit.

The file compiles the EDMF column twice, with the tags and without them, so it
has its own test group. See `docs/src/tagged_water.md`.
=#
using Test
import ClimaAtmos as CA

function run_simulation(config_dict, job_id)
    simulation = CA.get_simulation(
        CA.AtmosConfig(
            merge(
                config_dict,
                Dict{String, Any}("output_dir" => mktempdir(pwd())),
            );
            job_id,
        ),
    )
    @test CA.solve_atmos!(simulation).ret_code == :success
    return simulation
end

altitude_region(above) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => 750.0,
    "width" => 100.0,
    "above" => above,
)

# The largest absolute value of a field.
largest(ᶜf) = maximum(abs, parent(ᶜf))

@testset "The water tags' diffusion leak correction" begin
    edmf_dict = Dict{String, Any}(
        "config" => "column",
        "initial_condition" => "DYCOMS_RF02",
        "turbconv" => "prognostic_edmfx",
        "implicit_diffusion" => true,
        "approximate_linear_solve_iters" => 2,
        "edmfx_entr_model" => "Generalized",
        "edmfx_detr_model" => "Generalized",
        "edmfx_sgs_mass_flux" => true,
        "edmfx_sgs_diffusive_flux" => true,
        "edmfx_nh_pressure" => true,
        "edmfx_vertical_diffusion" => true,
        "edmfx_filter" => true,
        "prognostic_tke" => true,
        "microphysics_model" => "1M",
        "fixed_terminal_velocity_liquid" => false,
        "z_elem" => 30,
        "z_max" => 1500.0,
        "z_stretch" => false,
        "perturb_initstate" => false,
        "rad" => "DYCOMS",
        "toml" => [joinpath(pkgdir(CA), "toml", "prognostic_edmfx_1M.toml")],
        "ode_algo" => "ARS222",
        "dt" => "120secs",
        "t_end" => "1hours",
        "FLOAT_TYPE" => "Float64",
        "output_default_diagnostics" => false,
    )
    tag_dict = Dict{String, Any}(
        "water_tracers" => [
            Dict{String, Any}("name" => "tropo", "region" => altitude_region(false)),
            Dict{String, Any}("name" => "strat", "region" => altitude_region(true)),
            Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
        ],
        "water_tag_transport" => "increment",
        "water_tag_leak_correction" => true,
        "water_tag_ledger_per_tag" => true,
        # The audit and the diagnostics write scratch from callbacks, so the
        # parity check below covers them too.
        "water_closure_check" =>
            Dict{String, Any}("period" => "10mins", "audit" => true),
        "diagnostics" => [
            Dict{String, Any}(
                "short_name" => [
                    "q_tag_res",
                    "q_tag_leak_vdiff",
                    "q_tag_led_leaknet",
                    "q_tag_led_leaknet_gross",
                    "q_tag_led_leak_tropo",
                    "q_tag_led_leakgross_evap",
                ],
                "period" => "10mins",
            ),
        ],
    )
    corrected = run_simulation(merge(edmf_dict, tag_dict), "water_tags_leak")
    Y = corrected.integrator.u
    p = corrected.integrator.p
    t = corrected.integrator.t
    FT = eltype(Y)
    model = p.atmos.water_tagging_model
    turbconv_model = p.atmos.turbconv_model
    @test CA.has_water_tag_leak_correction(model)
    @test CA.water_tag_leak_mechanism_names(model) == (:q_tag_led_leaknet,)
    leak_names = CA.water_tag_ledger_leak_names(model)
    @test leak_names ==
          (:q_tag_led_leak_tropo, :q_tag_led_leak_strat, :q_tag_led_leak_evap)
    @test CA.water_tag_ledger_upleak_names(model) == ()
    @test hasproperty(Y.c, :q_tag_led_leaknet)
    @test all(name -> hasproperty(Y.c, name), leak_names)
    @test hasproperty(p.scratch, :ᶜtagging_q_leak_correction)

    is_diagnostic(name) =
        CA.is_water_tag_name(name) ||
        CA.is_water_tag_ledger_name(name) ||
        CA.is_tag_mechanism_ledger_name(name) ||
        CA.is_water_tag_leak_mechanism_name(name) ||
        CA.is_tag_per_tag_ledger_name(name)

    # 1. One composition everywhere, in the state the run left. Each tag's
    # share of the rain and snow is then its share of the water.
    shares = (; tropo = 0.3, strat = 0.7, evap = 0.2)
    Y_uniform = copy(Y)
    for (name, share) in pairs(shares)
        getproperty(Y_uniform.c, Symbol(:ρq_tag_, name)) .= share .* Y.c.ρq_tot
    end
    CA.set_precomputed_quantities!(Y_uniform, p, t)
    @testset "The partition diffuses as the parent" begin
        ᶜleak = similar(Y.c.ρ)
        CA.water_tag_leak!(ᶜleak, Y_uniform, p, Val(:vdiff))
        ᶜρleak = ᶜleak .* Y.c.ρ
        @info "The vertical diffusion's leak on the D4-W column, kg/m³/s" largest(
            ᶜρleak,
        )
        @test largest(ᶜρleak) > 0
        Yₜ = zero(Y)
        CA.edmfx_sgs_diffusive_flux_tendency!(Yₜ, Y_uniform, p, t, turbconv_model)
        ᶜpartition = Yₜ.c.ρq_tag_tropo .+ Yₜ.c.ρq_tag_strat
        # With the correction the partition's diffusion is the parent's. The
        # difference is rounding against the leak, and without the correction
        # it is the leak itself (`tagged_water_edmf_integration.jl`).
        @test largest(ᶜpartition .- Yₜ.c.ρq_tot) < 1e-8 * largest(ᶜρleak)
        # Each tag's correction is the diffusion of its share of the rain and
        # snow, its ledger holds it, and the partition's ledger their sum, the
        # leak with the opposite sign.
        ᶠρK_h = CA.Fields.Field(FT, axes(Y.f))
        @. ᶠρK_h = CA.ᶠinterp(Y_uniform.c.ρ) * p.precomputed.ᶠK_h
        ᶜq_p = CA._leaking_water(Y_uniform, p)
        for (name, share) in pairs(shares)
            ᶜpart = similar(Y.c.ρ)
            @. ᶜpart = share * ᶜq_p
            ᶜdivergence = CA.ᶜdiffusive_flux_divergenceᵥ(ᶠρK_h, ᶜpart)
            ᶜexpected = similar(Y.c.ρ)
            @. ᶜexpected = ᶜdivergence
            ᶜledger = getproperty(Yₜ.c, Symbol(:q_tag_led_leak_, name))
            @test largest(ᶜledger .- ᶜexpected) < 1e-10 * largest(ᶜρleak)
        end
        @test largest(Yₜ.c.q_tag_led_leaknet .+ ᶜρleak) <
              1e-10 * largest(ᶜρleak)
        @test largest(
            Yₜ.c.q_tag_led_leaknet .- Yₜ.c.q_tag_led_leak_tropo .-
            Yₜ.c.q_tag_led_leak_strat,
        ) < 1e-12 * largest(ᶜρleak)
        # Only the tags and their ledgers take the correction: the kernel
        # called on its own writes nothing else.
        Yₜ_alone = zero(Y)
        CA.correct_water_tag_diffusion_leak!(Yₜ_alone, Y_uniform, p, ᶠρK_h, true)
        for name in propertynames(Y.c)
            name == :sgsʲs && continue
            is_diagnostic(name) && continue
            @test all(iszero, parent(getproperty(Yₜ_alone.c, name)))
        end
        @test all(iszero, parent(Yₜ_alone.c.sgsʲs))
        @test all(iszero, parent(Yₜ_alone.f))
        @test largest(Yₜ_alone.c.q_tag_led_leaknet) > 0
    end

    # 2. After the hour.
    @testset "The column after an hour" begin
        closure = CA.tag_closure(
            Y,
            p,
            :ρq_tot,
            CA.water_region_tag_state_names(model),
        )
        @info "Water tags with the leak correction after an hour" closure.relative closure.gross_relative
        # `tagged_water_increment_integration.jl` bounds the same column
        # without the correction at 1e-4.
        @test closure.gross_relative < 1e-4
        # The correction is in flux form, so it moves no water through the
        # column's boundaries, and the partition's ledger is its tags' sum.
        ᶜnet = Y.c.q_tag_led_leaknet
        @test sum(abs.(ᶜnet)) > 0
        @test abs(sum(ᶜnet)) < 1e-10 * sum(abs.(ᶜnet))
        @test largest(ᶜnet .- Y.c.q_tag_led_leak_tropo .- Y.c.q_tag_led_leak_strat) <
              1e-10 * largest(ᶜnet)
        @test largest(Y.c.q_tag_led_leak_evap) > 0
        # The per-step gross follows the ledgers, and the audit reports them
        # without an attempted total.
        steps = p.tagging.tag_ledger_steps
        for name in (:q_tag_led_leaknet, leak_names...)
            @test haskey(steps.ledgers, name)
            @test !haskey(steps.attempted, name)
            ᶜgross = parent(getproperty(steps.ledgers, name).ᶜgross)
            @test all(ᶜgross .>= abs.(parent(getproperty(Y.c, name))) .* (1 - 1e-12))
        end
        audit = CA.water_tag_extra_audit(Y, p, model, FT(1))
        @test audit.led_leaknet_retained > 0
        @test isnan(audit.led_leaknet_attempted)
        @test audit.led_leak_tropo_retained > 0
        @test 0 < audit.led_leak_tropo_inventory_fraction < Inf
        # The split solver solves the ledgers apart, as it does the tags.
        cache = CA.jacobian_cache(
            CA.ManualSparseJacobian(; approximate_solve_iters = 2),
            Y,
            p.atmos,
        )
        @test cache.solver isa CA.SplitJacobianSolver
        uncoupled = Set(map(field -> field.name, cache.solver.uncoupled))
        for name in (:q_tag_led_leaknet, leak_names...)
            @test CA.MatrixFields.FieldName(:c, name) in uncoupled
        end
    end

    # 3. The model's own fields.
    @testset "The model's fields do not depend on the tags" begin
        plain = run_simulation(edmf_dict, "water_tags_leak_plain")
        Y_plain = plain.integrator.u
        @test isnothing(plain.integrator.p.atmos.water_tagging_model)
        @test Set(filter(!is_diagnostic, propertynames(Y.c))) ==
              Set(propertynames(Y_plain.c))
        for name in propertynames(Y_plain.c)
            name == :sgsʲs && continue
            @test isequal(
                parent(getproperty(Y.c, name)),
                parent(getproperty(Y_plain.c, name)),
            )
        end
        for name in propertynames(Y_plain.c.sgsʲs.:(1))
            @test isequal(
                parent(getproperty(Y.c.sgsʲs.:(1), name)),
                parent(getproperty(Y_plain.c.sgsʲs.:(1), name)),
            )
        end
        @test propertynames(Y.f) == propertynames(Y_plain.f)
        @test isequal(parent(Y.f), parent(Y_plain.f))
    end
end
