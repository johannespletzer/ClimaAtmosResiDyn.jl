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
 2. with a composition that varies in space, the same, with each tag's share
    taken cell by cell. Where the clamp and the renormalization change the
    shares, and where the partition holds no water, the kernel takes the
    shares the sedimentation takes. Where the partition holds no water, the
    leak is left;
 3. after the hour the partition stays closed, the partition's ledger moves no
    water through the column's boundaries, it is the sum of the tags' own, and
    the split solver, the audit and the diagnostics read the ledgers;
 4. the model's fields are those of the same column without tags, bit for bit;
 5. against the same column with the correction off, stepped side by side:
    the leak the partition takes from the EDMF diffusion falls by a set
    factor, the closure stays within its bound, and the model's fields are the
    same. The follower's and the repairs' ledgers are printed, not bounded.

The file compiles the EDMF column three times, with the tags, with the tags and
the correction off, and without tags, so it has its own test group. See
`docs/src/tagged_water.md`.
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

# A run stepped by hand to its end, with `reading(integrator)` taken after each
# step. Each step runs the stepper and the callbacks, as `solve_atmos!` does.
function stepped_run(config_dict, job_id, reading)
    simulation = CA.get_simulation(
        CA.AtmosConfig(
            merge(
                config_dict,
                Dict{String, Any}("output_dir" => mktempdir(pwd())),
            );
            job_id,
        ),
    )
    (; integrator, output_writers) = simulation
    t_end = last(integrator.sol.prob.tspan)
    readings = []
    while integrator.t < t_end
        CA.CTS.step!(integrator)
        push!(readings, reading(integrator))
    end
    isnothing(output_writers) || foreach(close, output_writers)
    return simulation, readings
end

altitude_region(above) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => 750.0,
    "width" => 100.0,
    "above" => above,
)

# The largest absolute value of a field.
largest(ᶜf) = maximum(abs, parent(ᶜf))

# The absolute value of a field, integrated over the domain.
gross(ᶜf) = Float64(sum(abs.(ᶜf)))

# The rain and snow that the parent does not diffuse, `q_p`, as a field.
function leaking_water(Y, p)
    ᶜq_p = similar(Y.c.ρ)
    ᶜq_p_lazy = CA._precipitating_water(Y, p)
    @. ᶜq_p = ᶜq_p_lazy
    return ᶜq_p
end

# `ρK_h` on the faces, as the parent's water diffusion takes it.
function face_ρK_h(Y, p)
    ᶠρK_h = CA.Fields.Field(eltype(Y), axes(Y.f))
    @. ᶠρK_h = CA.ᶠinterp(Y.c.ρ) * p.precomputed.ᶠK_h
    return ᶠρK_h
end

# `∇·(ρK_h ∇f)`, with the operator the correction uses, as a field.
function diffusion_of(ᶠρK_h, ᶜf)
    ᶜout = similar(ᶜf)
    ᶜdivergence = CA.ᶜdiffusive_flux_divergenceᵥ(ᶠρK_h, ᶜf)
    @. ᶜout = ᶜdivergence
    return ᶜout
end

# The EDMF vertical diffusion's leak as a run has it after a step, over the
# domain. `gap` is the gross of the partition's tendency from
# `edmfx_sgs_diffusive_flux_tendency!` less the parent's: the leak the tags
# take. `leak` is the gross of the closed form. It reads no tag, so it is the
# same with the correction on and off. `uncovered` is the gross of the closed
# form's part where the partition holds no water, which the correction leaves.
# `ρq_p` and `ρq_p_uncovered` are the rain and snow, and their part there.
function diffusion_reading(integrator)
    Y = integrator.u
    p = integrator.p
    t = integrator.t
    CA.set_precomputed_quantities!(Y, p, t)
    Yₜ = zero(Y)
    CA.edmfx_sgs_diffusive_flux_tendency!(Yₜ, Y, p, t, p.atmos.turbconv_model)
    ᶜleak = similar(Y.c.ρ)
    CA.water_tag_leak!(ᶜleak, Y, p, Val(:vdiff))
    CA.water_tag_share_norm!(p, Y)
    ᶜq_p = leaking_water(Y, p)
    ᶜq_p_uncovered = @. ifelse(
        p.scratch.ᶜtagging_q_share_norm > 0,
        zero(ᶜq_p),
        ᶜq_p,
    )
    return (;
        gap = gross(Yₜ.c.ρq_tag_tropo .+ Yₜ.c.ρq_tag_strat .- Yₜ.c.ρq_tot),
        leak = gross(ᶜleak .* Y.c.ρ),
        uncovered = gross(diffusion_of(face_ρK_h(Y, p), ᶜq_p_uncovered)),
        ρq_p = Float64(sum(Y.c.ρ .* ᶜq_p)),
        ρq_p_uncovered = Float64(sum(Y.c.ρ .* ᶜq_p_uncovered)),
    )
end

# The per-step gross of each named state ledger over the hour, as a fraction of
# the column's water now. `NaN` for a ledger the run does not have.
function ledger_grosses(Y, p, names)
    (; ledgers) = p.tagging.tag_ledger_steps
    water = Float64(sum(Y.c.ρq_tot))
    return NamedTuple{names}(
        map(
            name ->
                haskey(ledgers, name) ?
                Float64(sum(getproperty(ledgers, name).ᶜgross)) / water : NaN,
            names,
        ),
    )
end

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
        ᶠρK_h = face_ρK_h(Y_uniform, p)
        ᶜq_p = CA._precipitating_water(Y_uniform, p)
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

    # 2. A composition that varies in space (the review of #119, point 1). The
    # correction takes each tag's share cell by cell, so a tag's correction is
    # not its share times the partition's. First a closed partition, through
    # the model's tendency. Then shares that the clamp and the renormalization
    # change, and a band where the partition holds no water, through the
    # kernel, against the shares computed here by hand.
    @testset "A composition that varies in space" begin
        @test all(>(0), parent(Y.c.ρq_tot))
        ᶜz = CA.Fields.coordinate_field(Y.c).z
        # tropo's share falls from about 0.94 at the ground to 0.06 at the
        # top, across the cloud, and evap's from 0.3.
        ᶜs = @. 0.5 - 0.45 * tanh((ᶜz - 700) / 300)
        ᶜe = @. 0.3 * exp(-(ᶜz / 500))
        Y_varied = copy(Y)
        @. Y_varied.c.ρq_tag_tropo = ᶜs * Y.c.ρq_tot
        @. Y_varied.c.ρq_tag_strat = (1 - ᶜs) * Y.c.ρq_tot
        @. Y_varied.c.ρq_tag_evap = ᶜe * Y.c.ρq_tot
        CA.set_precomputed_quantities!(Y_varied, p, t)
        ᶜρleak = similar(Y.c.ρ)
        CA.water_tag_leak!(ᶜρleak, Y_varied, p, Val(:vdiff))
        @. ᶜρleak *= Y.c.ρ
        scale = largest(ᶜρleak)
        @test scale > 0
        ᶠρK_h = face_ρK_h(Y_varied, p)
        ᶜq_p = leaking_water(Y_varied, p)

        # The closed partition, through the model's tendency.
        Yₜ = zero(Y)
        CA.edmfx_sgs_diffusive_flux_tendency!(Yₜ, Y_varied, p, t, turbconv_model)
        @test largest(Yₜ.c.ρq_tag_tropo .+ Yₜ.c.ρq_tag_strat .- Yₜ.c.ρq_tot) <
              1e-8 * scale
        for (name, ᶜshare) in ((:tropo, ᶜs), (:strat, 1 .- ᶜs), (:evap, ᶜe))
            ᶜledger = getproperty(Yₜ.c, Symbol(:q_tag_led_leak_, name))
            @test largest(ᶜledger .- diffusion_of(ᶠρK_h, ᶜshare .* ᶜq_p)) <
                  1e-10 * scale
            # The share's gradient counts: the correction is not the share
            # times the partition's.
            share_times_net = largest(ᶜledger .- ᶜshare .* Yₜ.c.q_tag_led_leaknet)
            @info "A varying share against the share times the partition's correction" name share_times_net /
                                                                                            scale
            @test share_times_net > 1e-3 * scale
        end
        @test largest(Yₜ.c.q_tag_led_leaknet .+ ᶜρleak) < 1e-10 * scale

        # The kernel against the shares computed here by hand, as the
        # sedimentation mirror takes them. Returns the tendency and the
        # partition's norm.
        clamped_share(ᶜρq_tag) = @. min(max(ᶜρq_tag / Y.c.ρq_tot, 0), 1)
        function kernel_against_hand(Y_state)
            ᶜφ_tropo = clamped_share(Y_state.c.ρq_tag_tropo)
            ᶜφ_strat = clamped_share(Y_state.c.ρq_tag_strat)
            ᶜnorm = ᶜφ_tropo .+ ᶜφ_strat
            partition_share(ᶜφ) = @. ifelse(ᶜnorm > 0, ᶜφ / ᶜnorm, 0.0)
            CA.set_precomputed_quantities!(Y_state, p, t)
            Yₜ = zero(Y)
            CA.apply_water_tag_leak_correction!(
                Yₜ,
                Y_state,
                p,
                ᶠρK_h,
                similar(Y.c.ρ),
                CA.water_tag_leak_ledgers(Yₜ, model),
                false,
            )
            for (name, ᶜshare) in (
                (:tropo, partition_share(ᶜφ_tropo)),
                (:strat, partition_share(ᶜφ_strat)),
                (:evap, clamped_share(Y_state.c.ρq_tag_evap)),
            )
                ᶜexpected = diffusion_of(ᶠρK_h, ᶜshare .* ᶜq_p)
                ᶜtagₜ = getproperty(Yₜ.c, Symbol(:ρq_tag_, name))
                ᶜledger = getproperty(Yₜ.c, Symbol(:q_tag_led_leak_, name))
                @test largest(ᶜexpected) > 0
                @test largest(ᶜtagₜ .- ᶜexpected) < 1e-10 * scale
                @test largest(ᶜledger .- ᶜexpected) < 1e-10 * scale
            end
            return Yₜ, ᶜnorm
        end

        # Clamped and renormalized shares. tropo holds more than the cell's
        # water near the ground, strat goes negative there, and elsewhere the
        # two sum to more than the water. The partition's shares still sum to
        # one, so its correction is still the leak with the opposite sign.
        Y_clamped = copy(Y_varied)
        @. Y_clamped.c.ρq_tag_tropo = 1.2 * ᶜs * Y.c.ρq_tot
        @. Y_clamped.c.ρq_tag_strat = (1 - 1.1 * ᶜs) * Y.c.ρq_tot
        @test minimum(parent(Y_clamped.c.ρq_tag_strat)) < 0
        @test maximum(parent(Y_clamped.c.ρq_tag_tropo .- Y.c.ρq_tot)) > 0
        Yₜ, ᶜnorm = kernel_against_hand(Y_clamped)
        @test all(>(0), parent(ᶜnorm))
        @test maximum(abs, parent(ᶜnorm) .- 1) > 0.01
        @test largest(Yₜ.c.q_tag_led_leaknet .+ ᶜρleak) < 1e-10 * scale

        # And where the partition holds no water, at the level with the most
        # rain and snow, the shares are zero and the leak there is left. The
        # partition's correction is the diffusion of the rain and snow where
        # it holds water.
        ᶜband = ᶜq_p .== maximum(parent(ᶜq_p))
        Y_band = copy(Y_clamped)
        @. Y_band.c.ρq_tag_tropo = ifelse(ᶜband, 0.0, Y_band.c.ρq_tag_tropo)
        @. Y_band.c.ρq_tag_strat = ifelse(ᶜband, 0.0, Y_band.c.ρq_tag_strat)
        Yₜ, ᶜnorm = kernel_against_hand(Y_band)
        @test count(iszero, parent(ᶜnorm)) == 1
        ᶜcovered = diffusion_of(ᶠρK_h, (@. ifelse(ᶜnorm > 0, ᶜq_p, 0.0)))
        ᶜuncovered = diffusion_of(ᶠρK_h, (@. ifelse(ᶜnorm > 0, 0.0, ᶜq_p)))
        @test largest(Yₜ.c.q_tag_led_leaknet .- ᶜcovered) < 1e-10 * scale
        @test largest(Yₜ.c.q_tag_led_leaknet .+ ᶜρleak .+ ᶜuncovered) <
              1e-10 * scale
        # Both parts are there, so the check is not vacuous.
        @info "The rain and snow by level, kg/kg" parent(ᶜq_p)[:]
        @test gross(ᶜuncovered) > 0
        @test gross(ᶜcovered) > 0.01 * gross(ᶜρleak)
        @info "The leak left where the partition holds no water, at one level" gross(
            ᶜuncovered,
        ) / gross(ᶜρleak)
    end

    # 3. After the hour.
    @testset "The column after an hour" begin
        closure = CA.tag_closure(
            Y,
            p,
            :ρq_tot,
            CA.water_region_tag_state_names(model),
        )
        @info "Water tags with the leak correction after an hour" closure.relative closure.gross_relative
        # `tagged_water_increment_integration.jl` bounds the same column
        # without the correction at 1e-4. Section 5 compares with it.
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
        # The ratios of #109 (the second review of #119, finding 1). A pure
        # region tag is read by its inventory, where the flag says a ratio
        # applies. `evap`, a source tag, is read by its burden. The parent
        # scale is `∫ρq_tot`.
        @test audit.led_leak_tropo_applicable == 1
        @test 0 < audit.led_leak_tropo_parent_fraction < Inf
        @test 0 < audit.led_leak_evap_burden_fraction < Inf
        @test audit.ledger_parent_scale > 0
        @test audit.ledger_parent_scale == Float64(sum(Y.c.ρq_tot))
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

    # 4. The model's own fields.
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

    # 5. Against the same column with the correction off (the review of #119,
    # point 1). Both are stepped by hand, and after each step the EDMF
    # diffusion's leak is read as each run has it: what the partition takes
    # from `edmfx_sgs_diffusive_flux_tendency!` beyond the parent. The
    # closed form reads no tag, so it is the same in both. The corrected run
    # is a second simulation of the first's type, so it compiles in seconds.
    @testset "Against the same column without the correction" begin
        off_dict = merge(
            tag_dict,
            Dict{String, Any}(
                "water_tag_leak_correction" => false,
                "diagnostics" => [
                    Dict{String, Any}(
                        "short_name" => ["q_tag_res", "q_tag_leak_vdiff"],
                        "period" => "10mins",
                    ),
                ],
            ),
        )
        off, readings_off = stepped_run(
            merge(edmf_dict, off_dict),
            "water_tags_leak_off",
            diffusion_reading,
        )
        on, readings_on = stepped_run(
            merge(edmf_dict, tag_dict),
            "water_tags_leak_on",
            diffusion_reading,
        )
        Y_off = off.integrator.u
        p_off = off.integrator.p
        Y_on = on.integrator.u
        p_on = on.integrator.p
        @test !CA.has_water_tag_leak_correction(p_off.atmos.water_tagging_model)
        @test CA.has_water_tag_leak_correction(p_on.atmos.water_tagging_model)
        @test length(readings_off) == length(readings_on) == 30

        # The model's fields do not depend on the key.
        @test Set(filter(!is_diagnostic, propertynames(Y_off.c))) ==
              Set(filter(!is_diagnostic, propertynames(Y_on.c)))
        for name in filter(!is_diagnostic, propertynames(Y_off.c))
            name == :sgsʲs && continue
            @test isequal(
                parent(getproperty(Y_off.c, name)),
                parent(getproperty(Y_on.c, name)),
            )
        end
        @test isequal(parent(Y_off.c.sgsʲs), parent(Y_on.c.sgsʲs))
        @test isequal(parent(Y_off.f), parent(Y_on.f))
        # So the closed form is the same after every step.
        @test [r.leak for r in readings_off] == [r.leak for r in readings_on]

        # The leak over the hour, as a fraction of the column's water, and its
        # largest rate per step, as a fraction per hour.
        water = Float64(sum(Y_on.c.ρq_tot))
        step_seconds = 120.0 # `edmf_dict`'s `dt`
        over_hour(readings, key) =
            sum(r -> getproperty(r, key), readings) * step_seconds / water
        per_hour(readings, key) =
            maximum(r -> getproperty(r, key), readings) * 3600 / water
        leak = over_hour(readings_on, :leak)
        gap_off = over_hour(readings_off, :gap)
        gap_on = over_hour(readings_on, :gap)
        factor = gap_off / gap_on
        max_factor =
            per_hour(readings_off, :gap) / per_hour(readings_on, :gap)
        @info "The EDMF diffusion's leak the partition takes, off and on, of the water" leak gap_off gap_on factor per_hour(
            readings_off,
            :gap,
        ) per_hour(readings_on, :gap) max_factor
        # The zero-norm part (the review of #119, point 3): the largest
        # fraction, over the steps, of the closed form and of the rain and
        # snow that falls where the partition holds no water.
        fraction(part, whole) = whole > 0 ? part / whole : 0.0
        uncovered_leak =
            maximum(r -> fraction(r.uncovered, r.leak), readings_on)
        uncovered_water =
            maximum(r -> fraction(r.ρq_p_uncovered, r.ρq_p), readings_on)
        @info "The leak where the partition holds no water, largest over the steps" uncovered_leak uncovered_water
        # Without the correction the partition takes the closed form's leak.
        # The two differ by the diffusion of the closure's residual: 2e-7 of
        # the leak on terrabyte, Julia 1.11.
        @test isapprox(gap_off, leak; rtol = 1e-3)
        # With it the partition takes that leak reduced by a factor. On
        # terrabyte, Julia 1.11, it was 5.3e3 over the hour and 2.7e3 in the
        # worst step. What is left is again the diffusion of the closure's
        # residual. The bounds leave a margin of five.
        @test factor > 1000
        @test max_factor > 500

        # The closure stays within its bound, with the correction and without.
        names = CA.water_region_tag_state_names(model)
        closure_off = CA.tag_closure(Y_off, p_off, :ρq_tot, names)
        closure_on = CA.tag_closure(Y_on, p_on, :ρq_tot, names)
        @info "The closure after an hour, off and on" closure_off.relative closure_off.gross_relative closure_on.relative closure_on.gross_relative
        @test closure_on.gross_relative < 1e-4

        # Printed, not bounded: what the follower and the repairs moved, and
        # the correction's own ledger, each the per-step gross over the hour as
        # a fraction of the column's water. The follower's `moved` is the
        # reference the record's gate reads (FINDINGS W40 and W45).
        ledger_names = (
            :q_tag_inc_moved,
            :q_tag_inc_left,
            :q_tag_inc_negative,
            :q_tag_led_inc_tropo,
            :q_tag_led_inc_strat,
            :q_tag_led_inc_evap,
            :q_tag_led_rescale,
            :q_tag_led_empty,
            :q_tag_led_repair,
            :q_tag_led_repairnet,
            :q_tag_led_leaknet,
        )
        grosses_off = ledger_grosses(Y_off, p_off, ledger_names)
        grosses_on = ledger_grosses(Y_on, p_on, ledger_names)
        fix_off = CA.tag_gross_total(p_off.tagging.ᶜwater_fix_gross) / water
        fix_on = CA.tag_gross_total(p_on.tagging.ᶜwater_fix_gross) / water
        @info "The ledgers' per-step gross over the hour, of the water, off" grosses_off fix_off
        @info "The ledgers' per-step gross over the hour, of the water, on" grosses_on fix_on
        @test all(isfinite, grosses_on)
    end
end
