#=
Integration test for the water tags under prognostic EDMF, in the default mode
(`water_tag_updraft_copy: false`).

The tags have no updraft state. Each takes its share of the parent's sub-grid
mass flux of water, from the donor cell. An exchange of provenance at the
updraft's mass flux moves the updraft's own composition, from a plume rescaled
to the updraft's water, and sums to zero over the partition. This file checks,
on the DYCOMS RF02 EDMF column with 1-moment microphysics, after an hour:

 1. the partition stays closed;
 2. the partition's sub-grid tendencies sum to the parent's;
 3. with one composition everywhere and no surface moisture flux, each tag
    takes exactly its share of the parent's sub-grid flux, and the exchange
    moves nothing. With the flux, the plume starts in the lowest cell with the
    updraft's surface water, at the shares the model's own supplies give;
 4. the vertical diffusion's leak, in closed form, is the difference the
    diffusion makes between the partition and the parent, also where the
    parent is negative and the partition is closed to option C's target;
 5. the audit reports where the exchange's bound binds;
 6. the tags' sub-grid flux allocates next to nothing of its own;
 7. the model's fields are those of the same column without tags, bit for bit.

The check against the column without tags needs a second model type, so the
file builds the EDMF column twice and has a test group of its own. See
`docs/src/tagged_water.md`.
=#
using Test
import ClimaAtmos as CA

# One call to compile, then `@allocated` on a second call, inside a function
# that specializes on every argument.
function second_call_allocations(f::F, args::Vararg{Any, N}) where {F, N}
    f(args...)
    return @allocated f(args...)
end

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

# The largest absolute difference of two fields, relative to the largest
# absolute value of the second.
relative_difference(a, b) =
    maximum(abs, parent(a) .- parent(b)) / maximum(abs, parent(b))

# The vertical diffusion's leak with the EDMF flux at `K_h` only, of the water
# `ᶜq_p`, as `water_tag_leak!` took it before option C's target.
function vertical_leak_at_K_h(Y, p, ᶜq_p)
    ᶜleak = similar(Y.c.ρ)
    ᶜleak .= 0
    ᶠρK_h = CA.Fields.Field(eltype(Y), axes(Y.f))
    @. ᶠρK_h = CA.ᶠinterp(Y.c.ρ) * p.precomputed.ᶠK_h
    ᶜdivergence = CA.ᶜdiffusive_flux_divergenceᵥ(ᶠρK_h, ᶜq_p)
    @. ᶜleak -= ᶜdivergence / Y.c.ρ
    CA._add_boundary_layer_leak!(ᶜleak, Y, p, p.atmos.vertical_diffusion, ᶜq_p)
    return ᶜleak
end

@testset "Water tags under PrognosticEDMFX" begin
    # `config/model_configs/prognostic_edmfx_dycoms_rf02_column.yml` as a
    # single column with 1-moment microphysics, for an hour. It drizzles, so
    # the diffusion's leak is not zero.
    #
    # Test 4b needs the entrainment diffusivity `K_e`. ClimaParams 1.1.15 sets
    # its efficiency `EDMF_interface_entr_efficiency` to 0, which switches
    # `K_e` off. The other versions checked, 1.1.6, 1.1.9, 1.1.11, 1.1.13
    # and 1.1.17, set 0.4. So this file sets 0.4 itself, and `K_e` acts under
    # each of them.
    entrainment_toml = joinpath(mktempdir(pwd()), "interface_entrainment.toml")
    write(
        entrainment_toml,
        """
        [EDMF_interface_entr_efficiency]
        value = 0.4
        type = "float"
        """,
    )
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
        "toml" => [
            joinpath(pkgdir(CA), "toml", "prognostic_edmfx_1M.toml"),
            entrainment_toml,
        ],
        "ode_algo" => "ARS222",
        "dt" => "120secs",
        "t_end" => "1hours",
        "FLOAT_TYPE" => "Float64",
        "output_default_diagnostics" => false,
    )
    tag_dict = Dict{String, Any}(
        # The default mode's tracer transport, whose sub-grid flux and exchange
        # this file tests. Under EDMF `increment` is the default, which
        # `tagged_water_increment_integration.jl` tests.
        "water_tag_transport" => "tracer",
        "water_tracers" => [
            Dict{String, Any}("name" => "tropo", "region" => altitude_region(false)),
            Dict{String, Any}("name" => "strat", "region" => altitude_region(true)),
            Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
        ],
        # The audit and the leak's diagnostic write scratch from callbacks, so
        # the parity check below covers them too.
        "water_closure_check" =>
            Dict{String, Any}("period" => "10mins", "audit" => true),
        "diagnostics" => [
            Dict{String, Any}(
                "short_name" => ["q_tag_leak_vdiff", "q_tag_tropo"],
                "period" => "10mins",
            ),
        ],
    )
    tagged = run_simulation(merge(edmf_dict, tag_dict), "water_tags_edmf")
    Y = tagged.integrator.u
    p = tagged.integrator.p
    t = tagged.integrator.t
    model = p.atmos.water_tagging_model
    turbconv_model = p.atmos.turbconv_model
    @test !CA.has_water_tag_updraft_copies(model)
    @test !hasproperty(Y.c.sgsʲs.:(1), :q_tag_tropo)

    # 1. The partition stays closed, within bounds about twice what this column
    # gives after an hour on Julia 1.11: 3.5e-5 net and 5.4e-4 gross, relative
    # to the column's water. This test does not split that by cause; the
    # vertical diffusion's leak under 1M and the advection split are two
    # candidates (`docs/src/tagged_water.md`). The same column with grid-scale
    # tags only, which miss the sub-grid flux, gave 2.2e-2 gross after the hour
    # (FINDINGS W17), so the bound tells the two apart.
    @testset "The partition stays closed" begin
        closure = CA.tag_closure(
            Y,
            p,
            :ρq_tot,
            CA.water_region_tag_state_names(model),
        )
        @info "Water tags on the EDMF column after an hour" closure.relative closure.gross_relative
        @test abs(closure.relative) < 1e-4
        @test closure.gross_relative < 1e-3
        @test all(isfinite, parent(Y.c))
    end

    Yₜ_parent = zero(Y)
    CA.edmfx_sgs_mass_flux_tendency!(Yₜ_parent, Y, p, t, turbconv_model)
    ᶜparent_flux = Yₜ_parent.c.ρq_tot
    @test maximum(abs, parent(ᶜparent_flux)) > 0

    # 2. The donor shares are renormalized over the partition, and the exchange
    # sums to zero over it. So the partition's sub-grid tendencies add up to
    # the parent's, at rounding.
    @testset "The partition takes the parent's sub-grid flux" begin
        Yₜ = zero(Y)
        CA.sgs_mass_flux_of_water_tags!(Yₜ, Y, p, turbconv_model)
        @test maximum(abs, parent(Yₜ.c.ρq_tag_evap)) > 0
        @test relative_difference(
            Yₜ.c.ρq_tag_tropo .+ Yₜ.c.ρq_tag_strat,
            ᶜparent_flux,
        ) < 1e-12
    end

    # With one composition everywhere, the plume's is the grid mean's, except
    # for the surface water it starts with (3b).
    shares = (; ρq_tag_tropo = 0.3, ρq_tag_strat = 0.7, ρq_tag_evap = 0.2)
    Y_uniform = copy(Y)
    for (name, share) in pairs(shares)
        getproperty(Y_uniform.c, name) .= share .* Y.c.ρq_tot
    end

    # 3. Each tag then takes exactly its share of the parent's flux, and the
    # exchange, which moves only a difference of composition, moves nothing.
    # That holds without the surface moisture flux, whose water the plume
    # starts with, so the flux is set to zero here and restored after.
    @testset "One composition moves as the parent" begin
        ᶠρ_flux_q_tot = parent(p.precomputed.sfc_conditions.ρ_flux_q_tot)
        saved = copy(ᶠρ_flux_q_tot)
        fill!(ᶠρ_flux_q_tot, 0)
        Yₜ = zero(Y)
        CA.sgs_mass_flux_of_water_tags!(Yₜ, Y_uniform, p, turbconv_model)
        ᶠρ_flux_q_tot .= saved
        for (name, share) in pairs(shares)
            @test relative_difference(
                getproperty(Yₜ.c, name),
                share .* ᶜparent_flux,
            ) < 1e-12
        end
    end

    # 3b. W21's surface rule (the owner, 2026-09-28): in the lowest cell the
    # plume starts with the updraft's surface water. Its shares there are
    # `(1 - f) φ̄ᵢ + f gᵢ`, where `f` is the surface flux's part of the three
    # supplies of that cell, and `gᵢ` the surface flux's weight: the mask of a
    # region tag, one for `evap`. That is the copies' steady state there.
    # Here `f` is rebuilt from the model's own tendencies.
    @testset "The plume starts with the updraft's surface water" begin
        lowest(ᶜx) = vec(Array(parent(CA.Fields.level(ᶜx, 1))))
        lowest_one(ᶜx) = only(lowest(ᶜx))
        ᶜsgsʲ = Y_uniform.c.sgsʲs.:(1)
        q_totʲ = lowest_one(ᶜsgsʲ.q_tot)
        (; ᶜρʲs, sfc_mass_flux_sourceʲs, sfc_q_tot_buoyantʲs) = p.precomputed
        # The surface flux's increment of `q_totʲ`.
        Yₜ = zero(Y)
        CA.surface_flux_tendency!(Yₜ, Y_uniform, p, t)
        Δ = lowest_one(Yₜ.c.sgsʲs.:(1).q_tot)
        # The relaxation's rate, as the model's tendency has it.
        q_b = only(vec(Array(parent(sfc_q_tot_buoyantʲs))))
        a_min = CA.CAP.min_area(CA.CAP.turbconv_params(p.params))
        r =
            only(vec(Array(parent(sfc_mass_flux_sourceʲs)))) /
            max(lowest_one(ᶜsgsʲ.ρa), lowest_one(ᶜρʲs.:(1)) * a_min)
        Yₜ = zero(Y)
        CA.edmfx_boundary_condition_tendency!(Yₜ, Y_uniform, p, t, turbconv_model)
        @test lowest_one(Yₜ.c.sgsʲs.:(1).q_tot) ≈ r * (q_b - q_totʲ) rtol = 1e-12
        # Entrainment's rate, from the model's tendency.
        ᶜq⁰ = similar(Y.c.ρ)
        ᶜq⁰ .= CA.ᶜspecific_env_value(CA.@name(q_tot), Y_uniform, p)
        q⁰ = lowest_one(ᶜq⁰)
        @test q⁰ ≈ lowest_one(p.precomputed.ᶜq_tot_nonneg⁰) rtol = 1e-12
        Yₜ = zero(Y)
        CA.edmfx_entr_detr_tendency!(Yₜ, Y_uniform, p, t, turbconv_model)
        e = lowest_one(Yₜ.c.sgsʲs.:(1).q_tot) / (q⁰ - q_totʲ)
        f = max(Δ, 0) / (r * q_b + e * q⁰ + max(Δ, 0))
        @info "The surface flux's part of the lowest cell's supplies" Δ r * q_b e * q⁰ f
        # A part well above rounding, so the check below can fail.
        @test f > 1e-4
        # The plume's start, rescaled to the updraft's water.
        masks = p.tagging.ᶜwater_masks
        gains = (
            lowest_one(masks.ρq_tag_tropo),
            lowest_one(masks.ρq_tag_strat),
            1.0,
        )
        φ̄ = (0.3, 0.7, 0.2)
        ψ = map((φ, g) -> (1 - f) * φ + f * g, φ̄, gains)
        expected = map(s -> s * q_totʲ / (ψ[1] + ψ[2]), ψ)
        inputs = CA.water_exchange_inputs!(Y_uniform, p, turbconv_model, model)
        plume = lowest(inputs.ᶜεʲ)
        @test isapprox(collect(plume), collect(expected); rtol = 1e-10)
        # `evap` holds more in the updraft than its grid share.
        @test plume[3] > φ̄[3] * q_totʲ * (1 + f / 2)
    end

    # 4. The diffusion moves the tags at `K_h + K_e` on their whole value, and
    # the parent at `K_h` on the water without rain and snow. The closed form
    # is that difference.
    @testset "The vertical diffusion's leak in closed form" begin
        Yₜ = zero(Y)
        CA.edmfx_sgs_diffusive_flux_tendency!(Yₜ, Y_uniform, p, t, turbconv_model)
        ᶜleak = similar(Y.c.ρ)
        CA.water_tag_leak!(ᶜleak, Y_uniform, p, Val(:vdiff))
        @info "The vertical diffusion's leak on the EDMF column, kg/kg/s" maximum(
            abs,
            parent(ᶜleak),
        )
        @test maximum(abs, parent(ᶜleak)) > 0
        @test relative_difference(
            Yₜ.c.ρq_tag_tropo .+ Yₜ.c.ρq_tag_strat .- Yₜ.c.ρq_tot,
            ᶜleak .* Y.c.ρ,
        ) < 1e-8
        # It is the source from an exactly closed partition, so it does not
        # read the tags: the tags as the run left them give the same value.
        ᶜleak_run = similar(Y.c.ρ)
        CA.water_tag_leak!(ᶜleak_run, Y, p, Val(:vdiff))
        CA.water_tag_leak!(ᶜleak, Y_uniform, p, Val(:vdiff))
        @test isequal(parent(ᶜleak_run), parent(ᶜleak))
        # The paths this column does not have leak nothing.
        for path in (:hdiff, :hyperdiff, :sponge)
            CA.water_tag_leak!(ᶜleak, Y_uniform, p, Val(path))
            @test all(iszero, parent(ᶜleak))
        end
    end

    # 4b. The leak is taken where the partition sums to option C's target,
    # `max(ρq_tot, 0)`. Where the parent is never negative, that is `ρq_tot`
    # itself, and the leak is the diffusion of the rain and snow at `K_h`, as
    # before, bit for bit. Where it is negative, the partition exceeds the
    # parent by `-min(ρq_tot, 0)`. The tags diffuse that at `K_h + K_e` and the
    # parent not, and the leak includes it.
    @testset "The vertical diffusion's leak at option C's target" begin
        @test all(>=(0), parent(Y_uniform.c.ρq_tot))
        ᶜleak = similar(Y.c.ρ)
        CA.water_tag_leak!(ᶜleak, Y_uniform, p, Val(:vdiff))
        ᶜrain_and_snow = CA._precipitating_water(Y_uniform, p)
        @test isequal(
            parent(ᶜleak),
            parent(vertical_leak_at_K_h(Y_uniform, p, ᶜrain_and_snow)),
        )

        # The parent negative across the inversion, where `K_e` acts, and the
        # partition closed to its target there. The checks below need `K_e`,
        # so a `K_e` of zero everywhere fails here first.
        @test CA.Parameters.interface_entr_efficiency(p.params) == 0.4
        @test maximum(abs, parent(p.precomputed.ᶠK_entr)) > 0
        ᶜz = CA.Fields.coordinate_field(Y.c).z
        Y_negative = copy(Y_uniform)
        @. Y_negative.c.ρq_tot =
            ifelse(500 < ᶜz < 1000, -Y.c.ρq_tot, Y.c.ρq_tot)
        @test any(<(0), parent(Y_negative.c.ρq_tot))
        ᶜtarget = CA.water_tag_partition_target.(Y_negative.c.ρq_tot)
        for (name, share) in pairs(shares)
            getproperty(Y_negative.c, name) .= share .* ᶜtarget
        end
        Yₜ = zero(Y)
        CA.edmfx_sgs_diffusive_flux_tendency!(Yₜ, Y_negative, p, t, turbconv_model)
        ᶜρgap = Yₜ.c.ρq_tag_tropo .+ Yₜ.c.ρq_tag_strat .- Yₜ.c.ρq_tot
        CA.water_tag_leak!(ᶜleak, Y_negative, p, Val(:vdiff))
        @info "The vertical diffusion's leak where the parent is negative" relative_difference(
            ᶜρgap,
            ᶜleak .* Y.c.ρ,
        )
        @test relative_difference(ᶜρgap, ᶜleak .* Y.c.ρ) < 1e-8
        # Without the negative part, or without its `K_e` diffusion, the closed
        # form would miss the model's difference.
        ᶜwithout_negative_part = vertical_leak_at_K_h(
            Y_negative,
            p,
            CA._precipitating_water(Y_negative, p),
        )
        ᶜwithout_K_e = vertical_leak_at_K_h(
            Y_negative,
            p,
            CA._leaking_water(Y_negative, p),
        )
        @info "Relative errors without the negative part and without its K_e term" relative_difference(
            ᶜρgap,
            ᶜwithout_negative_part .* Y.c.ρ,
        ) relative_difference(ᶜρgap, ᶜwithout_K_e .* Y.c.ρ)
        @test relative_difference(ᶜρgap, ᶜwithout_negative_part .* Y.c.ρ) > 1e-6
        @test relative_difference(ᶜρgap, ᶜwithout_K_e .* Y.c.ρ) > 1e-6
    end

    # 5. The audit's own columns.
    @testset "The audit reports the exchange's bound" begin
        audit = CA.water_tag_edmf_audit(Y, p, model, 1.0)
        @info "Where the exchange's bound binds" audit
        @test propertynames(audit) ==
              (:exchange_volume_fraction, :bound_partition, :bound_evap)
        @test 0 < audit.exchange_volume_fraction <= 1
        @test 0 <= audit.bound_partition <= 1
        @test 0 <= audit.bound_evap <= 1
    end

    # 6. The flux reads the environment's water through the parent's helper,
    # which broadcasts over a closure that Julia wraps in a `Ref`, as the
    # energy source tags' flux does.
    @testset "The tags' sub-grid flux does not allocate" begin
        Yₜ = zero(Y)
        @test second_call_allocations(
            CA.sgs_mass_flux_of_water_tags!,
            Yₜ,
            Y,
            p,
            turbconv_model,
        ) <= 64
    end

    # 7. The model's own fields. `isequal` tells signed zeros apart, which `==`
    # does not. See "Fork parity with upstream" in
    # `docs/clima_atmos_specific.md`.
    @testset "The model's fields do not depend on the tags" begin
        plain = run_simulation(edmf_dict, "water_tags_edmf_plain")
        Y_plain = plain.integrator.u
        @test isnothing(plain.integrator.p.atmos.water_tagging_model)
        is_tag(name) =
            startswith(string(name), "ρq_tag_") ||
            CA.is_tag_mechanism_ledger_name(name) ||
            CA.is_water_tag_exp_ledger_name(name)
        @test Set(filter(!is_tag, propertynames(Y.c))) ==
              Set(propertynames(Y_plain.c))
        for name in propertynames(Y_plain.c)
            @test isequal(
                parent(getproperty(Y.c, name)),
                parent(getproperty(Y_plain.c, name)),
            )
        end
        @test propertynames(Y.f) == propertynames(Y_plain.f)
        @test isequal(parent(Y.f), parent(Y_plain.f))
    end
end
