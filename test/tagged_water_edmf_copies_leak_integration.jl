#=
Integration test for `water_tag_updraft_copy: true` with
`water_tag_leak_correction: true` (WP4c) on the DYCOMS RF02 EDMF column of
`tagged_water_edmf_copies_integration.jl` (item 8 of its list):

 8. with both keys, over five steps: the correction runs in the model's
    diffusive-flux tendency, the copies' leak ledgers exist, advance and reach
    the audit, and the model's fields are those without tags, bit for bit.

The copies with the leak correction are a model type of their own, and the
check against the column without tags needs a second. With the copies' own two
builds, three EDMF builds in one process came close to the 16 GB a GitHub
runner has, so this file is a test group of its own.
=#
using Test
import ClimaAtmos as CA
include("tagged_water_edmf_copies_common.jl")

@testset "Water tags with updraft copies and the leak correction" begin
    edmf_dict = copies_edmf_config()
    tag_dict = copies_tag_config()

    # 8. The leak correction (WP4c) with the copies, in the model (the review
    # of #119, point 5). Test 4c calls the kernel by hand on a model without
    # the key. Here both keys are on, with each tag's own ledgers, so the
    # model's diffusive-flux tendency runs the correction and writes the
    # copies' ledgers. The model is a type of its own, so it runs five steps,
    # against the column without tags run as far.
    @testset "The leak correction with the copies, in the model" begin
        largest(ᶜf) = maximum(abs, parent(ᶜf))
        short = Dict{String, Any}("t_end" => "10mins")
        leak_dict = merge(
            tag_dict,
            Dict{String, Any}(
                "water_tag_leak_correction" => true,
                "water_tag_ledger_per_tag" => true,
                "diagnostics" => [
                    Dict{String, Any}(
                        "short_name" => [
                            "q_tag_led_upleaknet",
                            "q_tag_led_upleaknet_gross",
                            "q_tag_led_upleak_tropo",
                            "q_tag_led_upleakgross_evap",
                        ],
                        "period" => "10mins",
                    ),
                ],
            ),
        )
        both = run_simulation(
            merge(edmf_dict, leak_dict, short),
            "water_tags_edmf_copies_leak",
        )
        Y_both = both.integrator.u
        p_both = both.integrator.p
        t_both = both.integrator.t
        model_both = p_both.atmos.water_tagging_model
        @test CA.has_water_tag_leak_correction(model_both)
        @test CA.has_water_tag_updraft_copies(model_both)
        @test CA.water_tag_leak_mechanism_names(model_both) ==
              (:q_tag_led_leaknet, :q_tag_led_upleaknet)
        upleak_names = CA.water_tag_ledger_upleak_names(model_both)
        @test upleak_names == (
            :q_tag_led_upleak_tropo,
            :q_tag_led_upleak_strat,
            :q_tag_led_upleak_evap,
        )

        # The copies' ledgers exist and have moved from zero, and the per-step
        # gross follows them. The partition's is the sum of its copies'.
        (; ledgers) = p_both.tagging.tag_ledger_steps
        for name in (:q_tag_led_leaknet, :q_tag_led_upleaknet, upleak_names...)
            ᶜL = getproperty(Y_both.c, name)
            @test largest(ᶜL) > 0
            @test haskey(ledgers, name)
            ᶜgross = getproperty(ledgers, name).ᶜgross
            @test all(parent(ᶜgross) .>= abs.(parent(ᶜL)) .* (1 - 1e-12))
        end
        @test largest(
            Y_both.c.q_tag_led_upleaknet .- Y_both.c.q_tag_led_upleak_tropo .-
            Y_both.c.q_tag_led_upleak_strat,
        ) < 1e-10 * largest(Y_both.c.q_tag_led_upleaknet)

        # The audit reads the copies' ledgers against the grid-mean tag, not
        # the copy's own water.
        audit = CA.water_tag_extra_audit(Y_both, p_both, model_both, 1.0)
        @test audit.led_upleaknet_retained > 0
        @test isnan(audit.led_upleaknet_attempted)
        @test audit.led_upleak_tropo_retained > 0
        @test audit.led_upleak_tropo_applicable == 1
        @test audit.led_upleak_tropo_inventory_fraction ≈
              audit.led_upleak_tropo_retained /
              Float64(sum(Y_both.c.ρq_tag_tropo)) rtol = 1e-12
        @test 0 < audit.led_upleak_evap_burden_fraction < Inf

        # Through the model's tendency. With one composition everywhere, the
        # partition's diffusion is the parent's and the copies' is `q_totʲ`'s,
        # to rounding. Without the key they differ by the leak (test 4c).
        shares = (; tropo = 0.3, strat = 0.7, evap = 0.2)
        Y_uniform = copy(Y_both)
        ᶜsgsʲ_both = Y_both.c.sgsʲs.:(1)
        for (name, share) in pairs(shares)
            getproperty(Y_uniform.c, Symbol(:ρq_tag_, name)) .=
                share .* Y_both.c.ρq_tot
            getproperty(Y_uniform.c.sgsʲs.:(1), Symbol(:q_tag_, name)) .=
                share .* ᶜsgsʲ_both.q_tot
        end
        CA.set_precomputed_quantities!(Y_uniform, p_both, t_both)
        ᶜleak = similar(Y_both.c.ρ)
        CA.water_tag_leak!(ᶜleak, Y_uniform, p_both, Val(:vdiff))
        scale = largest(ᶜleak)
        @test scale > 0
        Yₜ = zero(Y_both)
        CA.edmfx_sgs_diffusive_flux_tendency!(
            Yₜ,
            Y_uniform,
            p_both,
            t_both,
            p_both.atmos.turbconv_model,
        )
        ᶜsgsʲₜ = Yₜ.c.sgsʲs.:(1)
        @test largest(
            (Yₜ.c.ρq_tag_tropo .+ Yₜ.c.ρq_tag_strat .- Yₜ.c.ρq_tot) ./
            Y_both.c.ρ,
        ) < 1e-8 * scale
        @test largest(
            ᶜsgsʲₜ.q_tag_tropo .+ ᶜsgsʲₜ.q_tag_strat .- ᶜsgsʲₜ.q_tot,
        ) < 1e-8 * scale
        # Only the correction writes the copies' ledger.
        @test largest(Yₜ.c.q_tag_led_upleaknet) > 0

        # The model's fields are those without tags, bit for bit.
        plain = run_simulation(
            merge(edmf_dict, short),
            "water_tags_edmf_copies_leak_plain",
        )
        Y_plain = plain.integrator.u
        is_tag(name) =
            startswith(string(name), "ρq_tag_") ||
            CA.is_tag_mechanism_ledger_name(name) ||
            CA.is_water_tag_leak_mechanism_name(name) ||
            CA.is_water_tag_exp_ledger_name(name) ||
            CA.is_tag_per_tag_ledger_name(name)
        @test Set(filter(!is_tag, propertynames(Y_both.c))) ==
              Set(propertynames(Y_plain.c))
        for name in propertynames(Y_plain.c)
            name == :sgsʲs && continue
            @test isequal(
                parent(getproperty(Y_both.c, name)),
                parent(getproperty(Y_plain.c, name)),
            )
        end
        for name in propertynames(Y_plain.c.sgsʲs.:(1))
            @test isequal(
                parent(getproperty(Y_both.c.sgsʲs.:(1), name)),
                parent(getproperty(Y_plain.c.sgsʲs.:(1), name)),
            )
        end
        @test isequal(parent(Y_both.f), parent(Y_plain.f))

        # The copies' ledgers advance with one more step, taken by hand after
        # the parity check.
        names = (:q_tag_led_upleaknet, upleak_names...)
        L_before = map(n -> copy(parent(getproperty(Y_both.c, n))), names)
        CA.CTS.step!(both.integrator)
        for (i, n) in enumerate(names)
            @test parent(getproperty(both.integrator.u.c, n)) != L_before[i]
        end
    end
end
